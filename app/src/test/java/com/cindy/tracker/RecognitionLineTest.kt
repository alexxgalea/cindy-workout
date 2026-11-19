package com.cindy.tracker

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.cindy.tracker.databinding.ActivityMainBinding
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The debug line that says where the athlete is. The camera screen itself cannot be built on the
 * JVM (it binds CameraX), so the line is checked here on its own and on the screen's real layout;
 * that it shows live, before START and during a workout, is checked by hand on the phone.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RecognitionLineTest {

    private val context: Context = ApplicationProvider.getApplicationContext<Context>().also {
        it.setTheme(R.style.Theme_Cindy)
    }

    private val line = RecognitionLine(context)

    private fun text() = line.view.text.toString()

    @Test
    fun `it says no position before the first frame`() {
        assertEquals("no position", text())
    }

    @Test
    fun `it names the position it is shown`() {
        line.show(Recognition(Position.ON_THE_FLOOR))
        assertEquals("on the floor", text())
        line.show(Recognition(Position.ON_THE_BAR))
        assertEquals("on the bar", text())
        line.show(Recognition(Position.STANDING))
        assertEquals("standing", text())
        line.show(Recognition(Position.NONE))
        assertEquals("no position", text())
    }

    @Test
    fun `it names the recognised movement and its reps after the position`() {
        val tally = Recognition.NO_REPS + (Movement.PUSH_UPS to 3)
        line.show(Recognition(Position.ON_THE_FLOOR, Movement.PUSH_UPS, tally = tally))
        assertEquals("on the floor · PUSH-UPS · 3", text())
        // A rest keeps the movement, and the line still says it.
        line.show(Recognition(Position.STANDING, Movement.PUSH_UPS, tally = tally))
        assertEquals("standing · PUSH-UPS · 3", text())
        line.show(Recognition(Position.ON_THE_BAR, Movement.PULL_UPS, tally = Recognition.NO_REPS + (Movement.PULL_UPS to 12)))
        assertEquals("on the bar · PULL-UPS · 12", text())
    }

    @Test
    fun `a candidate is not shown, because nothing is recognised yet`() {
        line.show(Recognition(Position.STANDING, candidate = Movement.SQUATS, candidateReps = 1))
        assertEquals("standing", text())
    }

    @Test
    fun `fed the reps of a push-up set it says the movement and the tally, and a profile change starts fresh`() {
        var now = 0L
        var last = Recognition(Position.NONE)
        fun hold(pose: Array<Keypoint>, frames: Int = 10) = repeat(frames) {
            last = line.feed(pose, now, identityStable = true)
            now += 100
        }
        hold(PoseFixtures.pushup(175f))
        repeat(3) {
            hold(PoseFixtures.pushup(80f))
            hold(PoseFixtures.pushup(175f))
        }
        line.show(last)
        assertEquals("on the floor · PUSH-UPS · 3", text())

        line.useProfile(CindyProfile(push = PushVariant.KNEE_PUSH_UP))
        assertEquals("no position", text())
        assertEquals(Recognition(Position.NONE), line.feed(PoseFixtures.pushup(175f), now, identityStable = true))
    }

    @Test
    fun `the same profile again changes nothing`() {
        val line = RecognitionLine(context)
        line.show(Recognition(Position.STANDING))
        line.useProfile(CindyProfile.STANDARD)
        assertEquals("standing", line.view.text.toString())
    }

    @Test
    fun `fed the frames of a hang it says on the bar, and after a reset it says no position`() {
        var now = 0L
        var last = Recognition(Position.NONE)
        repeat(10) {
            last = line.feed(PoseFixtures.hangWithLegs(170f), now, identityStable = true)
            now += 100
        }
        line.show(last)
        assertEquals("on the bar", text())

        line.reset()
        assertEquals("no position", text())
        // And it starts from nothing: half a second of hang is needed again.
        assertEquals(Position.NONE, line.feed(PoseFixtures.hangWithLegs(170f), now, identityStable = true).position)
    }

    @Test
    fun `it sits on the picture above the bottom band and moves neither band`() {
        fun laidOut(withLine: Boolean): ActivityMainBinding {
            val binding = ActivityMainBinding.inflate(LayoutInflater.from(context))
            if (withLine) line.attachTo(binding.root, above = binding.bandBottom, marginPx = 8)
            binding.root.measure(
                View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(2400, View.MeasureSpec.EXACTLY)
            )
            binding.root.layout(0, 0, 1080, 2400)
            return binding
        }

        val without = laidOut(withLine = false)
        val with = laidOut(withLine = true)

        assertEquals("the top band moved", without.bandTop.height, with.bandTop.height)
        assertEquals("the bottom band moved", without.bandBottom.top, with.bandBottom.top)
        assertEquals("the preview moved", without.preview.height, with.preview.height)
        assertTrue("the line is not above the bottom band", line.view.bottom <= with.bandBottom.top)
        assertTrue("the line is off the left edge", line.view.left >= 0)
        assertTrue("the line is off the right edge", line.view.right <= 1080)
        assertTrue("the line has no size", line.view.width > 0 && line.view.height > 0)
        assertTrue("the line is over the top band", line.view.top >= with.bandTop.bottom)
    }
}
