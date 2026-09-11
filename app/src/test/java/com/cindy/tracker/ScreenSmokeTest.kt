package com.cindy.tracker

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Builds every screen that does not need a camera, and lays it out.
 *
 * These exist because of a crash that reached a device: `HelpActivity` reached for
 * `(layoutParams as LinearLayout.LayoutParams).marginStart` inside an `apply {}`, and a view
 * built in code has no layoutParams until a parent adds it. Nothing could have caught it — the
 * suite was two hundred tests of pure engine logic and not one of a single view, lint does not
 * model null layoutParams, and there is no emulator on the machine this is developed on.
 *
 * They are deliberately shallow. They assert that a screen *constructs, inflates, styles and
 * measures* without throwing, which is the failure mode hand-built view hierarchies actually
 * have. They are not a claim about how anything looks.
 *
 * [MainActivity] is absent on purpose: it binds CameraX and loads a TFLite interpreter in
 * `onCreate`, neither of which Robolectric can stand in for honestly.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ScreenSmokeTest {

    /** Through to RESUMED, then measured and laid out — styles resolve during measure. */
    private inline fun <reified T : android.app.Activity> smoke(intent: Intent? = null) {
        val controller = if (intent == null) {
            Robolectric.buildActivity(T::class.java)
        } else {
            Robolectric.buildActivity(T::class.java, intent)
        }
        val activity = controller.setup().get()
        val root = activity.findViewById<android.view.View>(android.R.id.content)
        root.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(1080, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(2400, android.view.View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2400)
        assertTrue("nothing was laid out", root.width > 0 && root.height > 0)
        controller.destroy()
    }

    @Test
    fun `the help screen builds`() = smoke<HelpActivity>()

    @Test
    fun `the menu builds`() {
        smoke<MenuActivity>(
            MenuActivity.intent(ApplicationProvider.getApplicationContext(), workoutLive = false)
        )
    }

    /** The menu refuses the movement picker mid-workout, and says so in an extra row. */
    @Test
    fun `the menu builds mid-workout`() {
        smoke<MenuActivity>(
            MenuActivity.intent(ApplicationProvider.getApplicationContext(), workoutLive = true)
        )
    }

    @Test
    fun `the records screen builds when empty`() = smoke<RecordsActivity>()

    /**
     * With history, which is a different screen: the streak card, the calendar and the progress
     * chart only exist once there is something to draw them from.
     */
    @Test
    fun `the records screen builds with history`() {
        val store = RecordStore(ApplicationProvider.getApplicationContext())
        store.clear()
        val day = 24L * 60 * 60 * 1000
        val now = System.currentTimeMillis()
        repeat(3) { i ->
            store.add(
                Attempt(
                    rounds = 12 + i,
                    reps = i,
                    atMillis = now - (2 - i) * day,
                    durationMs = 20 * 60 * 1000L,
                    roundSplitsMs = List(12 + i) { 60_000L + it * 500L },
                    profile = CindyProfile.STANDARD
                )
            )
        }
        smoke<RecordsActivity>()
        store.clear()
    }

    @Test
    fun `the results screen builds`() {
        val attempt = Attempt(
            rounds = 18,
            reps = 7,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = List(18) { 55_000L + it * 1_200L },
            profile = CindyProfile.STANDARD,
            manualReps = 4
        )
        smoke<ResultsActivity>(
            ResultsActivity.intent(
                ApplicationProvider.getApplicationContext(), attempt, stoppedEarly = false
            )
        )
    }

    /**
     * A session at non-standard movements takes the other branch of the level panel — no rung,
     * no progress bar, and a different line under the title.
     */
    @Test
    fun `the results screen builds for an adaptive session`() {
        val attempt = Attempt(
            rounds = 9,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = emptyList(),
            profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        )
        smoke<ResultsActivity>(
            ResultsActivity.intent(
                ApplicationProvider.getApplicationContext(), attempt, stoppedEarly = true
            )
        )
    }
}
