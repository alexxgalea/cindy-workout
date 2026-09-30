package com.cindy.tracker

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.cindy.tracker.databinding.ActivityMainBinding
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The tour of the camera screen, laid against the real HUD.
 *
 * The camera screen cannot be built here, because it binds CameraX, so this inflates its layout
 * the way the HUD smoke test does and runs the same step list over it. That is the part that
 * breaks when a control is renamed or moved: a caption pointing at nothing, or a hole cut where
 * the control used to be. Where the caption goes is [SpotlightMathTest].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HudTourTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val width = 1080
    private val height = 2400

    private fun layout(hud: ActivityMainBinding) {
        hud.root.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY)
        )
        hud.root.layout(0, 0, width, height)
    }

    private fun hud(): ActivityMainBinding {
        context.setTheme(R.style.Theme_Cindy)
        return ActivityMainBinding.inflate(LayoutInflater.from(context)).also { layout(it) }
    }

    /** Starts the tour and lays the screen out again, as the window would on the next frame. */
    private fun start(hud: ActivityMainBinding, done: () -> Unit = {}) {
        hud.spotlight.start(HudTour.steps(hud), done)
        layout(hud)
    }

    private fun findByText(root: View, text: String): View? {
        if (root is TextView && root.text.toString() == text) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) findByText(root.getChildAt(i), text)?.let { return it }
        }
        return null
    }

    private fun press(hud: ActivityMainBinding, label: String) {
        val button = findByText(hud.spotlight, label)
        assertNotNull("no $label button", button)
        button!!.performClick()
        layout(hud)
    }

    /** Where [view] is inside [root]: the offsets between them, added up. */
    private fun boxIn(root: View, view: View): android.graphics.RectF {
        var x = 0f
        var y = 0f
        var current = view
        while (current !== root) {
            val above = current.parent as View
            x += current.left + current.translationX - above.scrollX
            y += current.top + current.translationY - above.scrollY
            current = above
        }
        return android.graphics.RectF(x, y, x + view.width, y + view.height)
    }

    // ── the steps against the real layout ─────────────────────────────────────

    @Test
    fun `the tour has a step for each of the seven controls it names`() {
        val hud = hud()
        start(hud)

        assertTrue(hud.spotlight.isShowing)
        assertEquals(7, hud.spotlight.stepCount)
        assertEquals(0, hud.spotlight.stepIndex)
        assertEquals(View.VISIBLE, hud.spotlight.visibility)
    }

    @Test
    fun `every step lights a real window on the screen`() {
        val hud = hud()
        start(hud)

        repeat(hud.spotlight.stepCount) { step ->
            val hole = hud.spotlight.holeBounds
            assertTrue("step $step: empty hole $hole", hole.width() > 0f && hole.height() > 0f)
            assertTrue(
                "step $step: hole $hole runs off the screen",
                hole.left >= 0f && hole.top >= 0f && hole.right <= width && hole.bottom <= height
            )
            if (step < hud.spotlight.stepCount - 1) press(hud, "NEXT")
        }
    }

    @Test
    fun `the hole sits on the control the step is about`() {
        val hud = hud()
        val targets = HudTour.steps(hud).map { it.target }
        start(hud)

        targets.forEachIndexed { step, target ->
            assertEquals(step, hud.spotlight.stepIndex)
            val box = boxIn(hud.root, target)
            val hole = hud.spotlight.holeBounds
            assertTrue(
                "step $step: $hole does not hold $box",
                hole.left <= box.left && hole.top <= box.top &&
                    hole.right >= box.right && hole.bottom >= box.bottom
            )
            // Around it, not a screenful: a hole that swallowed the HUD would point at nothing.
            assertTrue("step $step: $hole is far bigger than $box", hole.width() < box.width() + 100f)
            assertTrue("step $step: $hole is far bigger than $box", hole.height() < box.height() + 100f)
            if (step < targets.lastIndex) press(hud, "NEXT")
        }
    }

    @Test
    fun `the caption fits on the screen and stays off the control it is about`() {
        val hud = hud()
        start(hud)

        repeat(hud.spotlight.stepCount) { step ->
            val card = hud.spotlight.captionBounds
            val hole = hud.spotlight.holeBounds
            assertTrue("step $step: card $card is empty", card.width() > 0 && card.height() > 0)
            assertTrue(
                "step $step: card $card runs off the screen",
                card.left >= 0 && card.top >= 0 && card.right <= width && card.bottom <= height
            )
            val overlaps = card.top < hole.bottom && card.bottom > hole.top
            assertFalse("step $step: card $card covers the hole $hole", overlaps)
            if (step < hud.spotlight.stepCount - 1) press(hud, "NEXT")
        }
    }

    @Test
    fun `each step says its title and what it is for`() {
        val hud = hud()
        val steps = HudTour.steps(hud)
        start(hud)

        steps.forEachIndexed { index, step ->
            assertNotNull("no title for step $index", findByText(hud.spotlight, step.title))
            assertNotNull("no body for step $index", findByText(hud.spotlight, step.body))
            if (index < steps.lastIndex) press(hud, "NEXT")
        }
    }

    // ── the flow ──────────────────────────────────────────────────────────────

    @Test
    fun `the last step says DONE, and finishing calls back once and puts the tour away`() {
        val hud = hud()
        var done = 0
        start(hud) { done++ }

        repeat(hud.spotlight.stepCount - 1) { press(hud, "NEXT") }
        assertNotNull(findByText(hud.spotlight, "DONE"))
        assertEquals(0, done)

        press(hud, "DONE")

        assertEquals(1, done)
        assertFalse(hud.spotlight.isShowing)
        assertEquals(View.GONE, hud.spotlight.visibility)
    }

    @Test
    fun `skipping at any step calls back once`() {
        val hud = hud()
        var done = 0
        start(hud) { done++ }
        repeat(3) { press(hud, "NEXT") }

        press(hud, "SKIP TOUR")

        assertEquals(1, done)
        assertFalse(hud.spotlight.isShowing)
    }

    @Test
    fun `it calls back once however many times it is ended`() {
        val hud = hud()
        var done = 0
        start(hud) { done++ }

        hud.spotlight.skip()
        hud.spotlight.skip()
        hud.spotlight.skip()

        assertEquals(1, done)
    }

    @Test
    fun `a tap anywhere on the dimmed screen moves on`() {
        val hud = hud()
        start(hud)

        hud.spotlight.performClick()
        assertEquals(1, hud.spotlight.stepIndex)
        hud.spotlight.performClick()
        assertEquals(2, hud.spotlight.stepIndex)
    }

    @Test
    fun `it takes every touch while it is showing`() {
        val hud = hud()
        start(hud)
        assertTrue(hud.spotlight.isClickable)
    }

    // ── the screen beneath ────────────────────────────────────────────────────

    @Test
    fun `while the tour shows, the screen under it is hidden from a screen reader, and back after`() {
        val hud = hud()
        val under = listOf(hud.bandTop, hud.bandBottom, hud.preview)
        val before = under.map { it.importantForAccessibility }

        start(hud)

        for (view in under) {
            assertEquals(
                View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, view.importantForAccessibility
            )
        }
        // The tour is not hidden from itself.
        assertTrue(
            hud.spotlight.importantForAccessibility !=
                View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        )

        hud.spotlight.skip()
        assertEquals(before, under.map { it.importantForAccessibility })
    }

    @Test
    fun `the hole follows a control that has moved`() {
        val hud = hud()
        start(hud)
        press(hud, "NEXT") // the status line
        val before = hud.spotlight.holeBounds

        // The status line grows, as it does when its text wraps. Laying the screen out again does
        // not lay the tour out again, so the light stays where the control was.
        hud.statusRow.layoutParams.height = 300
        hud.statusRow.requestLayout()
        layout(hud)
        assertEquals(before, hud.spotlight.holeBounds)

        hud.spotlight.refresh()
        layout(hud)

        assertTrue(
            "the hole did not grow with the control: $before, then ${hud.spotlight.holeBounds}",
            hud.spotlight.holeBounds.height() > before.height()
        )
    }

    @Test
    fun `looking again at a control that has not moved changes nothing`() {
        val hud = hud()
        start(hud)
        val before = hud.spotlight.holeBounds

        hud.spotlight.refresh()
        layout(hud)

        assertEquals(before, hud.spotlight.holeBounds)
    }

    // ── what is left out ──────────────────────────────────────────────────────

    @Test
    fun `a control that is not showing is left out of the tour`() {
        val hud = hud()
        hud.btnSkipExercise.visibility = View.GONE
        layout(hud)

        start(hud)

        assertEquals(6, hud.spotlight.stepCount)
        val titles = mutableListOf<String>()
        repeat(6) {
            val step = HudTour.steps(hud).first { s -> findByText(hud.spotlight, s.title) != null }
            titles += step.title
            if (it < 5) press(hud, "NEXT")
        }
        assertFalse("Skip was lit though its control is gone", titles.contains("Skip"))
    }

    @Test
    fun `with nothing to point at it is done at once and never shown`() {
        val hud = hud()
        var done = 0

        hud.spotlight.start(listOf(SpotlightView.Step(View(context), "Nothing", "Not laid out"))) {
            done++
        }

        assertEquals(1, done)
        assertFalse(hud.spotlight.isShowing)
        assertEquals(View.GONE, hud.spotlight.visibility)
    }

    @Test
    fun `a control whose parent is hidden is left out too`() {
        val hud = hud()
        hud.bandBottom.visibility = View.GONE
        layout(hud)

        start(hud)

        // Everything in the bottom band goes with it: start, reps, skip, flip.
        assertEquals(3, hud.spotlight.stepCount)
    }

    @Test
    fun `the camera HUD still inflates with the tour in it`() {
        val hud = hud()
        assertEquals(width, hud.bandTop.width)
        assertEquals(width, hud.bandBottom.width)
        assertEquals("the tour starts hidden", View.GONE, hud.spotlight.visibility)
        assertFalse(hud.spotlight.isShowing)
    }
}
