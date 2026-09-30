package com.cindy.tracker

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/** Where an attempt's Strava upload has got to. */
enum class StravaUploadState { QUEUED, PROCESSING, DONE, FAILED, NEEDS_RECONNECT, UNAVAILABLE }

/**
 * One ledger entry: the state, plus whatever [StravaUploadWorker] has learned along the way.
 *
 * [uploadId] is set the moment the file is accepted, before anything is polled — it is what
 * stops a retried worker ever sending the same file twice. [activityId] is set once Strava has
 * finished processing it. [message] is only ever [StravaUploadState.FAILED]'s reason.
 */
data class StravaUploadStatus(
    val state: StravaUploadState,
    val uploadId: String? = null,
    val activityId: Long? = null,
    val message: String? = null
)

/**
 * Queues a saved attempt's Strava upload, and remembers what happened to it.
 *
 * The ledger lives in prefs file `"strava"` — the same one [StravaTokenStore] uses, and for the
 * same reason: it is excluded from every kind of backup, and a queued or half-finished upload is
 * exactly the state that must not resurrect itself on a restored backup or a new phone. It is
 * keyed by [Attempt.atMillis], one entry per attempt, so a worker resumed after a process death
 * can find its own status again rather than starting the attempt over from nothing.
 */
object StravaUploads {

    private const val PREFS_NAME = "strava"
    private const val KEY_PREFIX = "upload_"

    /** The unique [WorkManager] name for one attempt's upload — one worker per attempt, ever. */
    fun uniqueWorkName(atMillis: Long): String = "strava-upload-$atMillis"

    /** The ledger entry for [atMillis], or null when nothing has ever been queued for it. */
    fun status(context: Context, atMillis: Long): StravaUploadStatus? =
        decode(prefs(context).getString(key(atMillis), null))

    /**
     * Marks [atMillis] as queued and schedules the worker for it.
     *
     * Unique work, [ExistingWorkPolicy.KEEP]: a second call for an attempt already queued or
     * running changes nothing, but one whose previous run already finished — successfully or
     * not — gets a fresh attempt, which is how a tapped retry actually retries.
     *
     * An upload id already on file is carried over. It means Strava accepted the file on an
     * earlier run, and the next run has to poll that id rather than send the file again.
     */
    fun enqueue(context: Context, atMillis: Long) {
        val acceptedAs = status(context, atMillis)?.uploadId
        write(context, atMillis, StravaUploadStatus(StravaUploadState.QUEUED, uploadId = acceptedAs))
        val request = OneTimeWorkRequestBuilder<StravaUploadWorker>()
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setInputData(
                Data.Builder().putLong(StravaUploadWorker.KEY_AT_MILLIS, atMillis).build()
            )
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(uniqueWorkName(atMillis), ExistingWorkPolicy.KEEP, request)
    }

    /**
     * What [MainActivity.finishWorkout] calls after a save.
     *
     * Enqueues only when the feature is available, the athlete is connected, and automatic
     * upload is switched on — every reason an attempt might *not* upload on its own lives in
     * this one decision, so it is testable without a running activity, and [MainActivity] never
     * has to know any of them.
     */
    fun onAttemptSaved(context: Context, atMillis: Long) {
        if (!StravaConfig.available) return
        val tokens = StravaTokenStore(context)
        if (!tokens.connected || !tokens.autoUpload) return
        enqueue(context, atMillis)
    }

    /**
     * Re-schedules every attempt still waiting on a reconnect. Called once the athlete has
     * connected again, so the attempts that piled up while disconnected are not left stranded.
     */
    fun requeueNeedingReconnect(context: Context) {
        val prefs = prefs(context)
        prefs.all.keys.filter { it.startsWith(KEY_PREFIX) }.forEach { k ->
            val atMillis = k.removePrefix(KEY_PREFIX).toLongOrNull() ?: return@forEach
            val status = decode(prefs.getString(k, null)) ?: return@forEach
            if (status.state == StravaUploadState.NEEDS_RECONNECT) enqueue(context, atMillis)
        }
    }

    /**
     * Forgets every ledger entry. Called when the record board is cleared, so the app stops
     * asking Strava about attempts it no longer has on file. Nothing already on Strava is
     * touched — this is only the app's own memory of what it did.
     */
    fun clear(context: Context) {
        val prefs = prefs(context)
        val edit = prefs.edit()
        prefs.all.keys.filter { it.startsWith(KEY_PREFIX) }.forEach { edit.remove(it) }
        edit.apply()
    }

    /**
     * Written by [StravaUploadWorker] as it learns more; also used by [enqueue] above.
     *
     * `commit()`, not `apply()`: an upload id has to be on disk before the worker goes on to
     * poll it, or a process death in between leaves the next run no way to know the file was
     * already accepted.
     */
    internal fun write(context: Context, atMillis: Long, status: StravaUploadStatus) {
        prefs(context).edit().putString(key(atMillis), encode(status)).commit()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun key(atMillis: Long) = "$KEY_PREFIX$atMillis"

    // ---- codec ----------------------------------------------------------------------------

    internal fun encode(status: StravaUploadStatus): String = listOf(
        status.state.name,
        status.uploadId.orEmpty(),
        status.activityId?.toString().orEmpty(),
        status.message.orEmpty()
    ).joinToString("|")

    internal fun decode(raw: String?): StravaUploadStatus? {
        if (raw == null) return null
        val p = raw.split("|", limit = 4)
        if (p.size != 4) return null
        val state = StravaUploadState.entries.firstOrNull { it.name == p[0] } ?: return null
        return StravaUploadStatus(
            state = state,
            uploadId = p[1].takeIf { it.isNotEmpty() },
            activityId = p[2].toLongOrNull(),
            message = p[3].takeIf { it.isNotEmpty() }
        )
    }
}
