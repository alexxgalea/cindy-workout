package com.cindy.tracker

import android.content.Context
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.cindy.tracker.databinding.ActivityMainBinding
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowChoreographer
import java.time.Duration

/**
 * The scoreboard when the movement changes while the clock runs: the last rep's roll and pulse,
 * then the next set over the figure for about 1.5 s, then the new set's figure and line.
 *
 * Read the way the athlete reads the band: which of the figure, its line and the next set are on
 * the screen, and what they say. The camera screen binds CameraX, so this inflates its layout the
 * way the HUD tests do, on the owner's phone (360 x 780 dp), and drives the band with the frames
 * the engine would hand it. Robolectric's paused looper lets the time pass.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h780dp-xxhdpi")
class ScoreboardReadoutTest {

    init {
        ShadowChoreographer.setPaused(true)
        ShadowChoreographer.setFrameDelay(Duration.ofMillis(FRAME_MS))
    }

    private val context: Context = ApplicationProvider.getApplicationContext<Context>().apply {
        setTheme(R.style.Theme_Cindy)
    }
    private val density = context.resources.displayMetrics.density

    private val hud: ActivityMainBinding = ActivityMainBinding.inflate(LayoutInflater.from(context)).also {
        BottomBand.apply(it, WorkoutState.RUNNING, CameraControls.of(WorkoutState.RUNNING, filming = false), statusBlank = true)
        layout(it)
    }

    private val readout = ScoreboardReadout(hud)

    private fun layout(hud: ActivityMainBinding) {
        hud.root.measure(
            View.MeasureSpec.makeMeasureSpec((360 * density).toInt(), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec((780 * density).toInt(), View.MeasureSpec.EXACTLY)
        )
        hud.root.layout(0, 0, (360 * density).toInt(), (780 * density).toInt())
    }

    /** One frame from the engine, as [MainActivity.apply] hands it over. */
    private fun frame(
        movement: Exercise,
        reps: Int,
        total: Int,
        rounds: Int = 0,
        event: RepEvent = RepEvent.NONE,
        eventReps: Int = reps,
        running: Boolean = true
    ) = readout.workout(movement, reps, rounds, event, eventReps, total, running)

    /** Lets [ms] pass a frame at a time, at a 60 Hz screen's pace, with a state frame on each. */
    private fun advance(ms: Long, each: () -> Unit = {}) {
        var left = ms
        while (left > 0) {
            val step = minOf(FRAME_MS, left)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(step))
            each()
            left -= step
        }
        layout(hud)
    }

    /** Whether [view] is drawn: it and every view above it in the band are visible. */
    private fun drawn(view: View): Boolean {
        var current: View? = view
        while (current != null && current !== hud.root) {
            if (current.visibility != View.VISIBLE) return false
            current = current.parent as? View
        }
        return true
    }

    private fun figure(): String? = hud.reps.takeIf(::drawn)?.text?.toString()
    private fun line(): String? = hud.movementLine.takeIf(::drawn)?.text?.toString()

    /** The next set's two rows, top to bottom, or null while it is not on the band. */
    private fun nextSet(): List<String>? =
        if (!drawn(hud.nextSet)) null else listOf(hud.nextSetTarget, hud.nextSetMovement).map { (it as TextView).text.toString() }

    /** Four pull-ups banked of five, the clock running. */
    private fun fourOfFivePullUps() = frame(Exercise.PULLUP, reps = 4, total = 4)

    @Test
    fun `finishing a set shows the last rep, then the next set over the figure, then 0 of its target`() {
        fourOfFivePullUps()

        // The fifth pull-up: the engine has moved on to push-ups and holds the five as the event's.
        frame(Exercise.PUSHUP, reps = 0, total = 5, event = RepEvent.EXERCISE_DONE, eventReps = 5)
        val stateFrame = { frame(Exercise.PUSHUP, reps = 0, total = 5) }
        assertEquals("the last rep was not shown", "5/5", figure())
        assertEquals("Pull-ups · Round 1", line())

        advance(400, stateFrame)
        assertEquals("the next set came before the last rep's pulse was over", "5/5", figure())
        assertEquals(null, nextSet())

        advance(100, stateFrame)
        assertEquals("the next set is not over the figure", listOf("10", "PUSH-UPS"), nextSet())
        assertEquals("the figure shows through the next set", null, figure())
        assertEquals("the line shows through the next set", null, line())

        advance(1_350, stateFrame)
        assertEquals("the next set left early", listOf("10", "PUSH-UPS"), nextSet())

        advance(200, stateFrame)
        assertEquals(null, nextSet())
        assertEquals("0/10", figure())
        assertEquals("Push-ups · Round 1", line())
    }

    @Test
    fun `SKIP while the clock runs shows the next set over the figure at once, then 0 of its target`() {
        frame(Exercise.PUSHUP, reps = 3, total = 8)

        // SKIP banks nothing: the total stays, and the three push-ups are the event's.
        frame(Exercise.SQUAT, reps = 0, total = 8, event = RepEvent.EXERCISE_DONE, eventReps = 3)
        val stateFrame = { frame(Exercise.SQUAT, reps = 0, total = 8) }
        assertEquals("a skip has no rep to wait for", listOf("15", "SQUATS"), nextSet())
        assertEquals(null, figure())

        advance(1_400, stateFrame)
        assertEquals("the next set left early", listOf("15", "SQUATS"), nextSet())

        advance(200, stateFrame)
        assertEquals(null, nextSet())
        assertEquals("0/15", figure())
        assertEquals("Squats · Round 1", line())
    }

    @Test
    fun `a rep banked while the next set is shown ends it at once and shows the count, rolling`() {
        fourOfFivePullUps()
        frame(Exercise.PUSHUP, reps = 0, total = 5, event = RepEvent.EXERCISE_DONE, eventReps = 5)
        advance(600) { frame(Exercise.PUSHUP, reps = 0, total = 5) }
        assertEquals(listOf("10", "PUSH-UPS"), nextSet())

        frame(Exercise.PUSHUP, reps = 1, total = 6, event = RepEvent.REP)
        assertEquals("the next set stayed over the rep", null, nextSet())
        assertEquals("the rep waited for the next set", "1/10", figure())
        assertEquals("Push-ups · Round 1", line())
        assertEquals("the rep did not roll", FitFigureView.Roll.UP, hud.reps.rolling)

        advance(2_000) { frame(Exercise.PUSHUP, reps = 1, total = 6) }
        assertEquals("the next set came back", null, nextSet())
        assertEquals("1/10", figure())
    }

    @Test
    fun `a rep banked before the next set appears shows at once, and the next set never comes`() {
        fourOfFivePullUps()
        frame(Exercise.PUSHUP, reps = 0, total = 5, event = RepEvent.EXERCISE_DONE, eventReps = 5)
        advance(200) { frame(Exercise.PUSHUP, reps = 0, total = 5) }

        frame(Exercise.PUSHUP, reps = 1, total = 6, event = RepEvent.REP)
        assertEquals("1/10", figure())
        assertEquals("Push-ups · Round 1", line())

        advance(2_000) { frame(Exercise.PUSHUP, reps = 1, total = 6) }
        assertEquals("the next set came after the rep", null, nextSet())
        assertEquals("1/10", figure())
    }

    @Test
    fun `minus while the next set is shown takes the last rep back into the set that was left`() {
        fourOfFivePullUps()
        frame(Exercise.PUSHUP, reps = 0, total = 5, event = RepEvent.EXERCISE_DONE, eventReps = 5)
        advance(600) { frame(Exercise.PUSHUP, reps = 0, total = 5) }

        frame(Exercise.PULLUP, reps = 4, total = 4, event = RepEvent.UNDO)
        assertEquals(null, nextSet())
        assertEquals("4/5", figure())
        assertEquals("Pull-ups · Round 1", line())
    }

    private companion object {
        const val FRAME_MS = 16L
    }
}
