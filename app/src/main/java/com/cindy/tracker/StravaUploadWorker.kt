package com.cindy.tracker

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ListenableWorker.Result
import androidx.work.WorkerParameters
import java.io.IOException
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONException

/**
 * Where [StravaUploadWorker] gets the two things a test needs to replace: the transport every
 * Strava call goes over, and how long the worker waits between polls.
 *
 * [FakeTransport] stands in for [transport] in every test; [sleep] exists only so a test that
 * exercises the polling loop does not also have to wait out thirty real seconds — production
 * never touches it.
 */
object StravaServices {
    var transport: () -> HttpTransport = { UrlConnectionTransport() }
    var sleep: suspend (Long) -> Unit = { delay(it) }
}

/**
 * Sends one saved attempt to Strava, and keeps polling until it knows what happened.
 *
 * Input is a single `atMillis`, matching [StravaUploads.uniqueWorkName]. Every branch below ends
 * by writing [StravaUploads]'s ledger and returning a [androidx.work.ListenableWorker.Result] —
 * never both retrying *and* leaving the ledger saying something that retry might contradict.
 */
class StravaUploadWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val atMillis = inputData.getLong(KEY_AT_MILLIS, NO_MILLIS)
        if (atMillis == NO_MILLIS) return@withContext Result.failure()

        val ctx = applicationContext
        val tokens = StravaTokenStore(ctx)

        // The work must not spin waiting for a reconnect that has to come from the athlete.
        if (!tokens.connected) {
            StravaUploads.write(ctx, atMillis, StravaUploadStatus(StravaUploadState.NEEDS_RECONNECT))
            return@withContext Result.success()
        }

        val attempt = RecordStore(ctx).all().firstOrNull { it.atMillis == atMillis }
        val sets = attempt?.let(StravaSets::from)
        if (attempt == null || sets == null) {
            StravaUploads.write(ctx, atMillis, StravaUploadStatus(StravaUploadState.UNAVAILABLE))
            return@withContext Result.success()
        }

        val transport = StravaServices.transport()
        val auth = StravaAuth(transport)
        val session = StravaSession(tokens, auth)
        val api = StravaApi(transport, session)

        val trace = HeartRateStore(ctx).load(atMillis)
        val startMillis = trace?.startedAtMillis ?: startMillisOf(attempt)

        fun send(): UploadOutcome {
            val existingId = StravaUploads.status(ctx, atMillis)?.uploadId
            return if (existingId != null) {
                api.status(existingId)
            } else {
                val offsetSeconds = TimeZone.getDefault().getOffset(startMillis) / 1000
                val composed = StravaComposer.compose(
                    attempt, sets, startMillis, offsetSeconds, trace, Profile(ctx).body()
                )
                api.upload(composed.payload, composed.name, composed.description, externalId(atMillis))
            }
        }

        try {
            var outcome = send()
            // A token that looked valid a moment ago can still be refused. One forced refresh
            // and one retry is worth it before asking the athlete to reconnect over what may
            // just have been a token that expired between the check above and the request.
            if (outcome is UploadOutcome.Unauthorized) {
                outcome = if (forceRefresh(tokens, auth)) send() else UploadOutcome.Unauthorized
            }
            handle(ctx, atMillis, outcome, api)
        } catch (e: StravaAuthException) {
            StravaUploads.write(ctx, atMillis, StravaUploadStatus(StravaUploadState.NEEDS_RECONNECT))
            Result.success()
        } catch (e: IOException) {
            // A refresh or a call that failed on the network, with no Strava semantics in it at
            // all — always worth retrying.
            Result.retry()
        } catch (e: JSONException) {
            Result.retry()
        }
    }

    /** True once a fresh grant is stored; false (and the grant cleared) once Strava says no. */
    private fun forceRefresh(tokens: StravaTokenStore, auth: StravaAuth): Boolean {
        val grant = tokens.grant ?: return false
        return try {
            tokens.grant = auth.refresh(grant.refreshToken)
            true
        } catch (e: StravaAuthException) {
            if (e.revoked) tokens.clearGrant()
            false
        }
    }

    private fun externalId(atMillis: Long) = "cindy-$atMillis"

    /** Writes the ledger for [outcome] and says whether the worker should retry. */
    private suspend fun handle(
        ctx: Context, atMillis: Long, outcome: UploadOutcome, api: StravaApi
    ): Result = when (outcome) {
        is UploadOutcome.Processing -> {
            // Persisted with commit(): the next run must see this uploadId even if the process
            // dies before this call returns, or a retry would re-POST a file Strava already has.
            StravaUploads.write(
                ctx, atMillis, StravaUploadStatus(StravaUploadState.PROCESSING, uploadId = outcome.uploadId)
            )
            poll(ctx, atMillis, outcome.uploadId, api)
        }
        is UploadOutcome.Ready -> {
            StravaUploads.write(
                ctx, atMillis, StravaUploadStatus(StravaUploadState.DONE, activityId = outcome.activityId)
            )
            Result.success()
        }
        is UploadOutcome.Duplicate -> {
            StravaUploads.write(
                ctx, atMillis, StravaUploadStatus(StravaUploadState.DONE, activityId = outcome.activityId)
            )
            Result.success()
        }
        is UploadOutcome.Rejected -> {
            StravaUploads.write(
                ctx, atMillis, StravaUploadStatus(StravaUploadState.FAILED, message = outcome.message)
            )
            Result.failure()
        }
        UploadOutcome.Unauthorized -> {
            StravaUploads.write(ctx, atMillis, StravaUploadStatus(StravaUploadState.NEEDS_RECONNECT))
            Result.success()
        }
        is UploadOutcome.RateLimited -> Result.retry()
        is UploadOutcome.Transient -> Result.retry()
    }

    /**
     * Polls [uploadId] at 1 s, 2 s, 3 s … until it stops processing or about [POLL_BUDGET_MS]
     * has passed, whichever comes first. Strava's own docs put mean processing under two
     * seconds, so this is generous rather than expected to run out; when it does, the worker
     * retries and the *next* run resumes the poll — the ledger already has the uploadId, so
     * that resumed run never POSTs again.
     */
    private suspend fun poll(ctx: Context, atMillis: Long, uploadId: String, api: StravaApi): Result {
        var waitMs = 1_000L
        var elapsedMs = 0L
        while (elapsedMs < POLL_BUDGET_MS) {
            StravaServices.sleep(waitMs)
            elapsedMs += waitMs
            val outcome = api.status(uploadId)
            if (outcome !is UploadOutcome.Processing) return handle(ctx, atMillis, outcome, api)
            waitMs += 1_000L
        }
        return Result.retry()
    }

    companion object {
        const val KEY_AT_MILLIS = "at_millis"
        private const val NO_MILLIS = -1L
        private const val POLL_BUDGET_MS = 30_000L
    }
}
