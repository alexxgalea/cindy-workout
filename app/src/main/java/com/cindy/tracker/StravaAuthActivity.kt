package com.cindy.tracker

import android.os.Bundle
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The redirect target for Strava's OAuth flow: `com.cindy.tracker://localhost/strava`.
 *
 * There is no real screen — just a footnote over the app's own black background, up for the
 * second or two the code exchange takes. Everything else about this class exists to protect that
 * exchange: the state it checks against is the one [MenuActivity] minted and stashed in
 * [StravaTokenStore.pendingState] right before it ever opened a browser, so an intent this
 * activity did not ask for — a stale entry replayed from task history, or a deep link crafted by
 * something else on the phone — is silently ignored rather than acted on.
 *
 * Nothing here is logged: the authorization code and the tokens it becomes are the one thing a
 * stack trace or a `Log.*` call from this feature must never carry, so every failure path below
 * ends in a plain, code-free toast instead.
 */
class StravaAuthActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContentView(FrameLayout(this).apply {
            setBackgroundColor(getColor(R.color.bg))
            addView(
                styledText(R.style.Cindy_Footnote, "Connecting to Strava…").apply {
                    setTextColor(getColor(R.color.label_secondary))
                },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
                ).apply { gravity = Gravity.CENTER }
            )
        })

        handleRedirect()
    }

    private fun handleRedirect() {
        val tokens = StravaTokenStore(this)
        val expected = tokens.pendingState
        val data = intent?.data?.toString()

        // No attempt in flight, or no data at all: there is nothing this intent could be an
        // answer to, so it is dropped without a toast rather than guessed at.
        if (expected == null || data == null) {
            finish()
            return
        }

        when (val result = StravaAuth.parseRedirect(data, expected)) {
            is RedirectResult.Code -> {
                tokens.pendingState = null
                exchange(tokens, result.code)
            }
            RedirectResult.Denied -> {
                tokens.pendingState = null
                finishWith("Not connected to Strava")
            }
            RedirectResult.MissingWriteScope -> {
                tokens.pendingState = null
                finishWith("Strava needs permission to upload activities to connect")
            }
            // Neither one is this app's own pending request; the real one (if any) is left
            // untouched so it can still complete when it actually arrives.
            RedirectResult.StateMismatch, RedirectResult.Malformed -> finish()
        }
    }

    private fun exchange(tokens: StravaTokenStore, code: String) {
        lifecycleScope.launch {
            val grant = try {
                withContext(Dispatchers.IO) {
                    StravaAuth(UrlConnectionTransport()).exchange(code)
                }
            } catch (e: StravaAuthException) {
                null
            } catch (e: IOException) {
                null
            }

            if (grant == null) {
                finishWith("Couldn't connect to Strava — check your connection and try again")
                return@launch
            }
            tokens.grant = grant
            finishWith("Connected to Strava" + (grant.athleteName?.let { " as $it" } ?: ""))
        }
    }

    private fun finishWith(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        finish()
    }
}
