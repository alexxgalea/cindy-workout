package com.cindy.tracker

import android.content.Context
import android.graphics.RectF
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.test.core.app.ApplicationProvider
import com.cindy.tracker.databinding.ActivityMainBinding
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The camera screen at the largest system text (2x), in every state the workout can be in, on
 * the phone the owner trains with (360 x 780 dp). Ticket #150: every control keeps a spoken name
 * and a 48 dp touch target, and the text on the screen is shown whole, in the room it has.
 *
 * Like [CameraBandsTest] this inflates the HUD without the activity and draws it the way the
 * activity does ([BottomBand.apply], and [BottomBand.show] for the camera switch).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h780dp-xxhdpi", fontScale = 2f)
class CameraLargeTextTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val density get() = context.resources.displayMetrics.density
    private val screenW = 360
    private val screenH = 780
    private val cutout = 43

    private fun px(dp: Int) = (dp * density).toInt()
    private fun dp(px: Int) = px / density

    /** The longest line the app prints while it counts or sets up (MainActivity.applySetup). */
    private val longestLine = "Movement barely registers — raise the phone or step back"

    /** The HUD in [state] at 2x text, with the longest coaching line and a two-digit round. */
    private fun at(state: WorkoutState, line: CharSequence = Scoreboard.line("Push-ups", 12)): ActivityMainBinding {
        // An AppCompat activity's inflater, because the clock's autosize is an `app:` attribute
        // that only AppCompatTextView reads; a bare inflater would leave the clock unsized.
        val activity = Robolectric.buildActivity(AppCompatActivity::class.java)
        activity.get().setTheme(R.style.Theme_Cindy)
        activity.create()
        val hud = ActivityMainBinding.inflate(activity.get().layoutInflater)
        assertTrue("the type setting did not reach the test",
            hud.root.context.resources.configuration.fontScale > 1.9f)
        hud.bandTop.setPadding(
            hud.bandTop.paddingLeft, hud.bandTop.paddingTop + px(cutout),
            hud.bandTop.paddingRight, hud.bandTop.paddingBottom
        )
        hud.status.text = longestLine
        hud.movementLine.text = line
        hud.reps.text = Scoreboard.figure("12", "/15", 0xFF000001.toInt(), 0xFF000002.toInt())
        val panel = CameraControls.of(state, filming = false)
        BottomBand.show(hud.btnFlip, panel[CameraControl.SWITCH_CAMERA])
        BottomBand.apply(hud, state, panel, statusBlank = false)
        hud.root.measure(
            View.MeasureSpec.makeMeasureSpec(px(screenW), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(px(screenH), View.MeasureSpec.EXACTLY)
        )
        hud.root.layout(0, 0, px(screenW), px(screenH))
        return hud
    }

    /** Where [view] is on the screen, in dp. */
    private fun boxIn(root: View, view: View): RectF {
        var x = 0
        var y = 0
        var current = view
        while (current !== root) {
            x += current.left
            y += current.top
            current = current.parent as View
        }
        return RectF(dp(x), dp(y), dp(x + view.width), dp(y + view.height))
    }

    private fun controls(hud: ActivityMainBinding) = listOf(
        "camera switch" to hud.btnFlip, "REC" to hud.btnRec, "MENU" to hud.btnMenu,
        "END" to hud.btnEnd, "the shutter" to hud.btnStart, "SKIP" to hud.btnSkipExercise,
        "minus" to hud.btnUndo, "plus" to hud.btnAddRep
    )

    @Test
    fun `every control on the screen has a spoken name in every state`() {
        for (state in WorkoutState.entries) {
            val hud = at(state)
            for ((name, view) in controls(hud)) {
                if (view.visibility != View.VISIBLE) continue
                assertTrue("$state: $name has no spoken name", !view.contentDescription.isNullOrBlank())
            }
        }
    }

    @Test
    fun `every control on the screen is a 48 dp target, dimmed or not, inside its parent and the screen`() {
        for (state in WorkoutState.entries) {
            val hud = at(state)
            for ((name, view) in controls(hud)) {
                if (view.visibility != View.VISIBLE) continue
                val box = boxIn(hud.root, view)
                assertTrue("$state: $name is ${box.width()} x ${box.height()} dp",
                    box.width() >= 48f - 0.5f && box.height() >= 48f - 0.5f)
                val parent = view.parent as View
                assertTrue("$state: $name is clipped by its parent",
                    view.left >= 0 && view.top >= 0 && view.right <= parent.width && view.bottom <= parent.height)
                assertTrue("$state: $name is off the screen: $box",
                    box.left >= 0f && box.top >= 0f && box.right <= screenW + 0.5f && box.bottom <= screenH + 0.5f)
            }
        }
    }

    /** Every line of [view] is shown whole: not cut by an ellipsis, not past its maximum. */
    private fun assertShownWhole(label: String, view: TextView) {
        val layout = view.layout
        assertTrue("$label: has no layout", layout != null)
        assertTrue("$label: ${layout.lineCount} lines of at most ${view.maxLines}", layout.lineCount <= view.maxLines)
        for (row in 0 until layout.lineCount) {
            assertEquals("$label: row $row is cut", 0, layout.getEllipsisCount(row))
        }
        // A view held to its maximum drops what does not fit without an ellipsis: the last row
        // must end where the text does.
        assertEquals("$label: the text is cut short", view.text.length, layout.getLineEnd(layout.lineCount - 1))
    }

    /** The text is no taller than the view it sits in, so a fixed-height row does not clip it. */
    private fun assertFitsItsHeight(label: String, view: TextView) {
        val room = view.height - view.compoundPaddingTop - view.compoundPaddingBottom
        assertTrue("$label: ${dp(view.layout.height)} dp of text in ${dp(room)} dp",
            view.layout.height <= room)
    }

    @Test
    fun `the text of the top band and the pill is shown whole in every state`() {
        for (state in WorkoutState.entries) {
            val hud = at(state)
            assertShownWhole("$state: the clock", hud.timer)
            assertFitsItsHeight("$state: the clock (${dp(hud.timer.textSize.toInt())} dp type)", hud.timer)
            val row = boxIn(hud.root, hud.timer)
            assertTrue("$state: the clock is ${row.width()} dp wide, past its row", hud.timer.layout.getLineWidth(0) <= hud.timer.width)
            if (hud.statusRow.visibility == View.VISIBLE) {
                assertShownWhole("$state: the coaching line", hud.status)
                val pill = boxIn(hud.root, hud.statusRow)
                assertTrue("$state: the pill is under the band", pill.top >= boxIn(hud.root, hud.bandTop).bottom - 0.5f)
                assertTrue("$state: the pill reaches into the scoreboard: $pill",
                    pill.bottom <= boxIn(hud.root, hud.bandBottom).top + 0.5f)
                assertTrue("$state: the pill is closer than 16 dp to an edge: $pill",
                    pill.left >= 16f - 0.5f && screenW - pill.right >= 16f - 0.5f)
            }
        }
    }

    @Test
    fun `the text of the scoreboard is shown whole, in its zone, in every state`() {
        for (state in WorkoutState.entries) {
            val hud = at(state)
            assertShownWhole("$state: the figure", hud.reps)
            assertTrue("$state: the figure is wider than its zone",
                hud.reps.layout.getLineWidth(0) <= hud.reps.width)
            assertShownWhole("$state: the movement line", hud.movementLine)
            assertFitsItsHeight("$state: the movement line", hud.movementLine)
            assertTrue("$state: the movement line is wider than its row",
                hud.movementLine.layout.getLineWidth(0) <= hud.movementLine.width)
            assertTrue("$state: the band grew to ${dp(hud.bandBottom.height)} dp", dp(hud.bandBottom.height) <= 219f + 0.5f)
        }
    }

    @Test
    fun `the longest line, a movement and a three-digit round, is one row in the figure's zone at 2x, in every state`() {
        for (state in WorkoutState.entries) {
            for (movement in Exercise.entries) {
                val hud = at(state, Scoreboard.line(movement.label, 100))
                val label = "$state ${movement.label}"
                assertShownWhole("$label: the line", hud.movementLine)
                assertEquals("$label: one row", 1, hud.movementLine.layout.lineCount)
                assertFitsItsHeight("$label: the line", hud.movementLine)
                assertTrue("$label: the line is ${dp(hud.movementLine.layout.getLineWidth(0).toInt())} dp, wider than its zone",
                    hud.movementLine.layout.getLineWidth(0) <= hud.movementLine.width)
                val line = boxIn(hud.root, hud.movementLine)
                val figure = boxIn(hud.root, hud.reps)
                assertTrue("$label: the line is ${line.width()} dp wide, past the 280 dp zone", line.width() <= 280f + 0.5f)
                assertEquals("$label: the line shares the figure's centre", figure.centerX(), line.centerX(), 0.5f)
                assertTrue("$label: the band grew to ${dp(hud.bandBottom.height)} dp", dp(hud.bandBottom.height) <= 219f + 0.5f)
            }
        }
    }

    @Test
    fun `the names under the controls and the idle line are shown whole in every state`() {
        for (state in WorkoutState.entries) {
            val hud = at(state)
            for ((name, view) in listOf(
                "END" to hud.nameEnd, "the shutter's name" to hud.nameShutter,
                "SKIP" to hud.nameSkip, "the idle line" to hud.idleLine
            )) {
                if (view.visibility != View.VISIBLE) continue
                assertShownWhole("$state: $name", view)
                assertFitsItsHeight("$state: $name", view)
                assertTrue("$state: $name is wider than its box", view.layout.getLineWidth(0) <= view.width)
            }
        }
    }
}
