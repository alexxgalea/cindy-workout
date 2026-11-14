package com.cindy.tracker

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.cindy.tracker.databinding.ActivityMainBinding
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowChoreographer
import java.time.Duration

/**
 * The scoreboard's figure answering "did it count me?": a banked rep rolls the count up and
 * pulses it green, a rep taken back rolls it down with no green, and neither ever holds back
 * the value itself.
 *
 * Read the way the athlete reads it: the figure's text, the count's colour (the count has no
 * colour of its own, so it is the view's), and whether its digits are rolling. Robolectric's
 * paused looper plays the motion without waiting for it.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ScoreboardFigureTest {

    init {
        // Frames only as the clock is advanced (see [advance]): by default Robolectric runs every
        // frame an animation asks for at once, so a 300 ms pulse is over in one idle.
        ShadowChoreographer.setPaused(true)
        ShadowChoreographer.setFrameDelay(Duration.ofMillis(FRAME_MS))
    }

    private val context: Context = ApplicationProvider.getApplicationContext<Context>().apply {
        setTheme(R.style.Theme_Cindy)
    }
    private val green = context.getColor(R.color.state_ok)
    private val white = context.getColor(R.color.label)

    /** The camera screen's own figure, in its own zone, inflated the way the HUD tests do it. */
    private val view: FitFigureView = ActivityMainBinding.inflate(LayoutInflater.from(context)).run {
        root.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(2340, View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2340)
        reps
    }

    private val figure = ScoreboardFigure(view).apply { show("0", "/5") }

    /** Lets [ms] pass a frame at a time, at a 60 Hz screen's pace, so motion plays as on a phone. */
    private fun advance(ms: Long) {
        var left = ms
        while (left > 0) {
            val step = minOf(FRAME_MS, left)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(step))
            left -= step
        }
    }

    private companion object {
        const val FRAME_MS = 16L
    }

    @After
    fun animationsBackOn() = durationScale(1f)

    /** The system's "remove animations" switch, as the platform itself reads it. */
    private fun durationScale(scale: Float) {
        ValueAnimator::class.java.getMethod("setDurationScale", Float::class.javaPrimitiveType)
            .invoke(null, scale)
    }

    @Test
    fun `a banked rep shows at once, green during the pulse and its own colour after it`() {
        figure.show("1", "/5", FigureMotion.BANKED)

        assertEquals("the value waited for the motion", "1/5", view.text.toString())
        assertEquals("the count is not green as the rep is banked", green, view.currentTextColor)
        advance(100)
        assertEquals("the count is not green during the pulse", green, view.currentTextColor)
        advance(400)
        assertEquals("the count did not go back to its own colour", white, view.currentTextColor)
        assertEquals("1/5", view.text.toString())
    }

    @Test
    fun `a banked rep rolls the count up, over about 150 ms`() {
        figure.show("1", "/5", FigureMotion.BANKED)

        assertEquals("the count is not rolling up", FitFigureView.Roll.UP, view.rolling)
        advance(100)
        assertEquals("the roll ended early", FitFigureView.Roll.UP, view.rolling)
        advance(150)
        assertEquals("the roll did not end", null, view.rolling)
    }

    @Test
    fun `a rep taken back rolls the count down, and nothing is green`() {
        figure.show("1", "/5", FigureMotion.BANKED)
        advance(500)

        figure.show("0", "/5", FigureMotion.TAKEN_BACK)
        assertEquals("0/5", view.text.toString())
        assertEquals("the count is not rolling down", FitFigureView.Roll.DOWN, view.rolling)
        repeat(10) {
            assertNotEquals("a rep taken back turned the count green", green, view.currentTextColor)
            advance(40)
        }
        assertEquals("the roll did not end", null, view.rolling)
        assertEquals(white, view.currentTextColor)
    }

    @Test
    fun `two reps banked 100 ms apart both show, and the figure ends on the right value`() {
        figure.show("1", "/5", FigureMotion.BANKED)
        advance(100)

        figure.show("2", "/5", FigureMotion.BANKED)
        assertEquals("the second rep waited for the first one's motion", "2/5", view.text.toString())
        assertEquals("the second rep did not roll", FitFigureView.Roll.UP, view.rolling)
        // The first pulse would be fading by now; the second one started again when its rep was banked.
        advance(150)
        assertEquals("the second rep's pulse did not start again", green, view.currentTextColor)
        advance(400)
        assertEquals("2/5", view.text.toString())
        assertEquals(null, view.rolling)
        assertEquals(white, view.currentTextColor)
    }

    @Test
    fun `mid-roll the count is drawn moving and the target stands still`() {
        figure.show("9", "/10")
        figure.show("10", "/10", FigureMotion.BANKED)
        advance(64)
        assertEquals(FitFigureView.Roll.UP, view.rolling)
        val rolling = picture()
        // The roll is over and the pulse is still green, so only the roll can tell the two apart.
        advance(120)
        assertEquals(null, view.rolling)
        assertEquals(green, view.currentTextColor)
        val still = picture()

        // Where the count ends and the slash begins, in the view's pixels.
        val split = (view.totalPaddingLeft + view.layout.getPrimaryHorizontal(2)).toInt()
        assertTrue("the count was drawn still mid-roll", !same(rolling, still, 0, split))
        assertTrue("the target moved with the count", same(rolling, still, split + 1, view.width))
    }

    private fun picture(): Bitmap =
        Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }

    private fun same(a: Bitmap, b: Bitmap, fromX: Int, toX: Int): Boolean {
        for (x in fromX until toX) for (y in 0 until a.height) if (a.getPixel(x, y) != b.getPixel(x, y)) return false
        return true
    }

    @Test
    fun `with animations off a banked rep does not roll, and only the colour changes`() {
        durationScale(0f)

        figure.show("1", "/5", FigureMotion.BANKED)
        assertEquals("1/5", view.text.toString())
        assertEquals("the count rolled with animations off", null, view.rolling)
        assertEquals("the colour did not change with animations off", green, view.currentTextColor)
        advance(100)
        assertEquals("the green went before the pulse was over", green, view.currentTextColor)
        advance(400)
        assertEquals("the count did not go back to its own colour", white, view.currentTextColor)
    }

    @Test
    fun `a workout ending mid-pulse keeps the green, then leaves the count in the stop colour`() {
        val red = context.getColor(R.color.state_alert)
        for (scale in listOf(1f, 0f)) {
            durationScale(scale)
            figure.colour(white)
            figure.show("0", "/5")
            figure.show("1", "/5", FigureMotion.BANKED)
            advance(50)

            figure.colour(red)
            assertEquals("the pulse was cut short (animation scale $scale)", green, view.currentTextColor)
            advance(500)
            assertEquals("the count is not in the stop colour (animation scale $scale)", red, view.currentTextColor)
        }
    }

    @Test
    fun `with animations off a rep taken back changes the count and nothing else`() {
        durationScale(0f)
        figure.show("1", "/5", FigureMotion.BANKED)
        advance(500)

        figure.show("0", "/5", FigureMotion.TAKEN_BACK)
        assertEquals("0/5", view.text.toString())
        assertEquals(null, view.rolling)
        assertEquals(white, view.currentTextColor)
    }
}
