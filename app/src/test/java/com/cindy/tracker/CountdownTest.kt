package com.cindy.tracker

import android.os.Looper
import android.view.View
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration

/**
 * The countdown that stands between tapping REC and the camera rolling.
 *
 * Worth a test of its own rather than a line in [ScreenSmokeTest], because the thing that can go
 * wrong here is not inflation but *timing*: a callback that fires twice starts two recordings, a
 * callback that fires early films the athlete still holding the phone, and a cancelled countdown
 * that fires anyway records a session nobody asked to record. Robolectric's paused looper makes
 * all three checkable without waiting three real seconds.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CountdownTest {

    private fun view(): CountdownView {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.setTheme(R.style.Theme_Cindy)
        return CountdownView(context).apply {
            // Sized as it would be between the two bands, so onSizeChanged builds its paints.
            measure(
                View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(1200, View.MeasureSpec.EXACTLY)
            )
            layout(0, 0, 1080, 1200)
        }
    }

    private fun advance(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))

    @Test
    fun `the callback fires once, after the full count`() {
        val countdown = view()
        var fired = 0
        countdown.start(3) { fired++ }

        assertTrue("the countdown should be running", countdown.isRunning)
        assertEquals("it is visible while it counts", View.VISIBLE, countdown.visibility)

        advance(2_900)
        assertEquals("recording started before the count was up", 0, fired)

        advance(200)
        assertEquals("recording did not start when the count ran out", 1, fired)
        assertFalse("it kept running past zero", countdown.isRunning)
        assertEquals("it stayed on the picture", View.GONE, countdown.visibility)

        // Nothing is left scheduled that could fire the callback a second time.
        advance(5_000)
        assertEquals("the callback fired more than once", 1, fired)
    }

    @Test
    fun `a cancelled countdown never fires`() {
        val countdown = view()
        var fired = 0
        countdown.start(3) { fired++ }

        advance(1_200)
        countdown.cancel()

        assertFalse(countdown.isRunning)
        assertEquals(View.GONE, countdown.visibility)
        advance(5_000)
        assertEquals("a cancelled countdown still started a recording", 0, fired)
    }

    /** Drawing is where the digit is worked out, so it has to survive every frame of a count. */
    @Test
    fun `it draws at every point of the count`() {
        val countdown = view()
        countdown.start(3) {}
        val bitmap = android.graphics.Bitmap.createBitmap(
            1080, 1200, android.graphics.Bitmap.Config.ARGB_8888
        )
        val canvas = android.graphics.Canvas(bitmap)
        repeat(30) {
            countdown.draw(canvas)
            advance(100)
        }
        // A frame past zero: the count ends on the first frame scheduled after its deadline,
        // which is up to one frame late by design rather than on the stroke of it.
        advance(32)
        assertFalse("the count should have finished", countdown.isRunning)
        // Drawing when it is not running is a no-op rather than a crash.
        countdown.draw(canvas)
    }
}
