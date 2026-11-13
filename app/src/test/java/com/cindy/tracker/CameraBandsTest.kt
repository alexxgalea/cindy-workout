package com.cindy.tracker

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.cindy.tracker.databinding.ActivityMainBinding
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The camera screen's two bands and the coaching line, measured in dp on the phone the owner
 * trains with (a 360 x 780 dp screen at 3 px per dp, so 1080 x 2340 px, with a 43 dp cutout).
 *
 * The camera screen itself binds CameraX, so this inflates its layout the way the HUD smoke test
 * does and applies the cutout the way [MainActivity.keepHudClearOfSystemBars] does. Every number
 * is from the #165 ticket or measured on the layout before the ticket, never recomputed from the
 * layout under test.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h780dp-xxhdpi")
class CameraBandsTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val density get() = context.resources.displayMetrics.density
    private val screenW = 360
    private val screenH = 780
    private val cutout = 43

    private fun px(dp: Int) = (dp * density).toInt()
    private fun dp(px: Int) = px / density

    /** The HUD laid out on the P40, with the cutout pushed in as padding on the top band. */
    private fun hud(): ActivityMainBinding {
        context.setTheme(R.style.Theme_Cindy)
        val hud = ActivityMainBinding.inflate(LayoutInflater.from(context))
        hud.bandTop.setPadding(
            hud.bandTop.paddingLeft, hud.bandTop.paddingTop + px(cutout),
            hud.bandTop.paddingRight, hud.bandTop.paddingBottom
        )
        layout(hud)
        return hud
    }

    private fun layout(hud: ActivityMainBinding) {
        hud.root.measure(
            View.MeasureSpec.makeMeasureSpec(px(screenW), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(px(screenH), View.MeasureSpec.EXACTLY)
        )
        hud.root.layout(0, 0, px(screenW), px(screenH))
    }

    // ── the bottom band: the height it may not outgrow ────────────────────────

    @Test
    fun `the bottom band is 219 dp while the clock runs`() {
        val hud = hud()
        // Origin/main (031dd48) drew it 215.33 dp tall. #167 needs 219: its names row and the
        // 12 dp under it are 3.67 dp more than the old band had, and the band may be no taller
        // when the athlete is at the phone than at the bar, so the bar's band is the 219 too.
        assertEquals(219f, dp(hud.bandBottom.height), 0.5f)
    }

    // ── the top band: one row ─────────────────────────────────────────────────

    @Test
    fun `the top band is the cutout and one 48 dp row, 91 dp on the P40`() {
        val hud = hud()
        assertEquals(cutout + 48f, dp(hud.bandTop.height), 0.5f)
        assertEquals(91f, dp(hud.bandTop.height), 0.5f)
    }

    // ── the coaching line: a pill on the picture ──────────────────────────────

    /** Where [view] is on the screen, in dp: its offsets up to the root, added together. */
    private fun boxIn(root: View, view: View): android.graphics.RectF {
        var x = 0f
        var y = 0f
        var current = view
        while (current !== root) {
            val above = current.parent as View
            x += current.left
            y += current.top
            current = above
        }
        return android.graphics.RectF(dp(x.toInt()), dp(y.toInt()), dp((x + view.width).toInt()), dp((y + view.height).toInt()))
    }

    private fun say(hud: ActivityMainBinding, line: String) {
        hud.status.text = line
        layout(hud)
    }

    @Test
    fun `the coaching line sits on the picture, 8 dp under the top band`() {
        val hud = hud()
        say(hud, "Counting…")
        val band = boxIn(hud.root, hud.bandTop)
        val pill = boxIn(hud.root, hud.statusRow)
        assertEquals("the pill is under the band, not in it", band.bottom + 8f, pill.top, 0.5f)
        assertTrue("the pill is not inside the picture", pill.bottom < boxIn(hud.root, hud.bandBottom).top)
        assertTrue("the pill is not a child of the top band", hud.statusRow.parent !== hud.bandTop)
    }

    @Test
    fun `the pill is centred`() {
        val hud = hud()
        say(hud, "Counting…")
        val pill = boxIn(hud.root, hud.statusRow)
        assertEquals(screenW / 2f, (pill.left + pill.right) / 2f, 0.5f)
    }

    @Test
    fun `the longest coaching line is shown whole, on two rows, 16 dp from each edge at most`() {
        val hud = hud()
        // The longest line the app prints while it counts or sets up (MainActivity.applySetup).
        val line = "Movement barely registers — raise the phone or step back"
        say(hud, line)
        val layout = hud.status.layout
        assertEquals("a line this long takes two rows", 2, layout.lineCount)
        for (row in 0 until layout.lineCount) {
            assertEquals("row $row is cut", 0, layout.getEllipsisCount(row))
        }
        val shown = (0 until layout.lineCount)
            .joinToString(" ") { line.substring(layout.getLineStart(it), layout.getLineEnd(it)).trim() }
        assertEquals(line, shown)
        val pill = boxIn(hud.root, hud.statusRow)
        assertTrue("the pill is closer than 16 dp to the start edge: $pill", pill.left >= 16f - 0.5f)
        assertTrue("the pill is closer than 16 dp to the end edge: $pill", screenW - pill.right >= 16f - 0.5f)
        assertEquals("the rows are centred", android.view.Gravity.CENTER_HORIZONTAL,
            hud.status.gravity and android.view.Gravity.HORIZONTAL_GRAVITY_MASK)
    }

    @Test
    fun `a short line stays on one row`() {
        val hud = hud()
        say(hud, "Counting…")
        assertEquals(1, hud.status.layout.lineCount)
    }

    // ── the three icons ───────────────────────────────────────────────────────

    @Test
    fun `the camera switch, REC and MENU are 48 dp targets at the end edge, each with a name`() {
        val hud = hud()
        val row = boxIn(hud.root, hud.btnFlip)
        for ((name, view) in listOf("camera switch" to hud.btnFlip, "REC" to hud.btnRec, "MENU" to hud.btnMenu)) {
            val box = boxIn(hud.root, view)
            assertTrue("$name is ${box.width()} x ${box.height()} dp", box.width() >= 48f - 0.5f && box.height() >= 48f - 0.5f)
            assertTrue("$name has no spoken name", !view.contentDescription.isNullOrBlank())
            assertTrue("$name is not in the row", box.top >= boxIn(hud.root, hud.bandTop).top + cutout - 0.5f)
        }
        assertTrue("the camera switch is left of REC", row.right <= boxIn(hud.root, hud.btnRec).left + 0.5f)
        assertTrue("REC is left of MENU", boxIn(hud.root, hud.btnRec).right <= boxIn(hud.root, hud.btnMenu).left + 0.5f)
        assertTrue("MENU is at the end edge", screenW - boxIn(hud.root, hud.btnMenu).right <= 8.5f)
        assertTrue("the clock is at the start edge", boxIn(hud.root, hud.timer).left <= 20.5f)
    }

    // ── the bottom band: a scoreboard read from the bar (#166) ────────────────

    /** The band's top edge, in dp: every part below is measured from it, as the ticket's table is. */
    private fun fromBand(hud: ActivityMainBinding, view: View): android.graphics.RectF {
        val band = boxIn(hud.root, hud.bandBottom)
        val box = boxIn(hud.root, view)
        return android.graphics.RectF(box.left, box.top - band.top, box.right, box.bottom - band.top)
    }

    @Test
    fun `from the band's top edge come the progress edge, a gap, the figure zone, the line, a gap and the row`() {
        val hud = hud()
        val edge = fromBand(hud, hud.repProgress)
        val figure = fromBand(hud, hud.reps)
        val line = fromBand(hud, hud.movementLine)
        val shutter = fromBand(hud, hud.btnStart)
        assertEquals("progress edge starts at the band's edge", 0f, edge.top, 0.5f)
        assertEquals("progress edge is 3 dp", 3f, edge.height(), 0.5f)
        assertEquals("a gap of 8 dp, then the figure zone", 3f + 8f, figure.top, 0.5f)
        assertEquals("the figure zone is 96 dp", 96f, figure.height(), 0.5f)
        assertEquals("the line follows the zone", figure.bottom, line.top, 0.5f)
        assertEquals("the line is 24 dp", 24f, line.height(), 0.5f)
        assertEquals("a gap of 16 dp, then the control row", line.bottom + 16f, shutter.top - (48f - shutter.height()) / 2f, 0.5f)
        assertEquals("the control row is 48 dp, 147 dp down", 147f, shutter.top - (48f - shutter.height()) / 2f, 0.5f)
        assertTrue("at least 12 dp is left under the row: ${dp(hud.bandBottom.height) - 195f}",
            dp(hud.bandBottom.height) - 195f >= 12f - 0.5f)
    }

    @Test
    fun `the figure zone runs from 8 dp at the start edge to 8 dp before the capsule, 280 dp on the P40`() {
        val hud = hud()
        val figure = boxIn(hud.root, hud.reps)
        val capsule = boxIn(hud.root, hud.stepper)
        assertEquals(8f, figure.left, 0.5f)
        assertEquals(280f, figure.width(), 0.5f)
        assertEquals("8 dp between the zone and the capsule", capsule.left - 8f, figure.right, 0.5f)
    }

    @Test
    fun `the figure is one line, centred, and set at 96 sp`() {
        val hud = hud()
        assertEquals(96f * density, hud.reps.textSize, 0.5f)
        assertEquals(1, hud.reps.maxLines)
        assertEquals(android.view.Gravity.CENTER, hud.reps.gravity)
        assertEquals("font padding is off, or the band grows by about 44 dp", false, hud.reps.includeFontPadding)
    }

    /** The height of what the figure draws, as the paint measures it. */
    private fun inkHeight(hud: ActivityMainBinding): Int {
        val bounds = android.graphics.Rect()
        hud.reps.paint.getTextBounds(hud.reps.text.toString(), 0, hud.reps.text.length, bounds)
        return bounds.height()
    }

    private fun show(hud: ActivityMainBinding, count: String, target: String) {
        hud.reps.text = Scoreboard.figure(count, target, 0xFF000001.toInt(), 0xFF000002.toInt())
        layout(hud)
    }

    @Test
    fun `12 over 15 fits at full size, whole, inside its zone`() {
        val hud = hud()
        show(hud, "12", "/15")
        assertEquals("it did not shrink", 96f * density, hud.reps.textSize, 0.5f)
        assertEquals(1, hud.reps.layout.lineCount)
        assertEquals("it is cut", 0, hud.reps.layout.getEllipsisCount(0))
        assertTrue("it is ${dp(hud.reps.layout.getLineWidth(0).toInt())} dp wide in a 280 dp zone",
            hud.reps.layout.getLineWidth(0) <= hud.reps.width)
        assertTrue("the zone grew to ${dp(hud.reps.height)} dp", dp(hud.reps.height) <= 96f + 0.5f)
    }

    @Test
    fun `a longer figure shrinks to fit rather than being cut`() {
        val hud = hud()
        show(hud, "124", "/150")
        assertTrue("it did not shrink", hud.reps.textSize < 96f * density)
        assertEquals("it is cut", 0, hud.reps.layout.getEllipsisCount(0))
        assertTrue(hud.reps.layout.getLineWidth(0) <= hud.reps.width)
    }

    @Test
    @Config(sdk = [34], qualifiers = "w360dp-h780dp-xxhdpi", fontScale = 2f)
    fun `at the largest system text the figure is never taller than its zone and the band does not grow`() {
        val hud = hud()
        show(hud, "12", "/15")
        assertTrue("the type setting reached the test", context.resources.configuration.fontScale > 1.9f)
        assertTrue("the figure's text is ${dp(hud.reps.textSize.toInt())} dp tall in a 96 dp zone",
            hud.reps.textSize <= 96f * density + 0.5f)
        assertTrue("the digits are ${dp(inkHeight(hud))} dp tall", inkHeight(hud) <= 96f * density + 0.5f)
        assertTrue("the band is ${dp(hud.bandBottom.height)} dp", dp(hud.bandBottom.height) <= 219f + 0.5f)
    }

    @Test
    fun `the line under the figure is 17 sp on the band's secondary colour, centred`() {
        val hud = hud()
        assertEquals(17f * density, hud.movementLine.textSize, 0.5f)
        assertEquals(context.getColor(R.color.label_secondary), hud.movementLine.currentTextColor)
        assertEquals(android.view.Gravity.CENTER, hud.movementLine.gravity)
        assertEquals("the line fits its 24 dp row on one line", 1, hud.movementLine.maxLines)
        hud.movementLine.text = Scoreboard.line("Push-ups", 12)
        layout(hud)
        assertTrue("it is ${dp(hud.movementLine.layout.height)} dp tall in 24",
            dp(hud.movementLine.layout.height) <= 24f + 0.5f)
    }

    @Test
    fun `the ROUND and movement eyebrows the line replaces are gone`() {
        for (name in listOf("roundsLabel", "rounds", "exercise", "repsTarget")) {
            assertEquals("$name is still in the layout", 0, context.resources.getIdentifier(name, "id", context.packageName))
        }
    }

    // ── the − and + capsule ───────────────────────────────────────────────────

    @Test
    fun `the capsule is 48 by 96 dp, 16 dp from the end edge, as tall as the figure zone`() {
        val hud = hud()
        val capsule = fromBand(hud, hud.stepper)
        val figure = fromBand(hud, hud.reps)
        assertEquals(48f, capsule.width(), 0.5f)
        assertEquals(96f, capsule.height(), 0.5f)
        assertEquals(screenW - 16f, capsule.right, 0.5f)
        assertEquals(figure.top, capsule.top, 0.5f)
        assertEquals(figure.bottom, capsule.bottom, 0.5f)
    }

    @Test
    fun `plus is the top half and minus the bottom half, each a 48 dp target`() {
        val hud = hud()
        val plus = boxIn(hud.root, hud.btnAddRep)
        val minus = boxIn(hud.root, hud.btnUndo)
        val capsule = boxIn(hud.root, hud.stepper)
        for ((name, box) in listOf("+" to plus, "-" to minus)) {
            assertTrue("$name is ${box.width()} x ${box.height()} dp", box.width() >= 47.5f && box.height() >= 47.5f)
            assertTrue("$name is outside the capsule", box.left >= capsule.left - 0.5f && box.right <= capsule.right + 0.5f &&
                box.top >= capsule.top - 0.5f && box.bottom <= capsule.bottom + 0.5f)
        }
        assertTrue("+ is not over -", plus.bottom <= minus.top + 0.5f)
    }

    @Test
    fun `each target of the capsule is at least 100 dp from the shutter's edge`() {
        val hud = hud()
        val shutter = boxIn(hud.root, hud.btnStart)
        for ((name, view) in listOf("+" to hud.btnAddRep, "-" to hud.btnUndo)) {
            val box = boxIn(hud.root, view)
            val dx = maxOf(shutter.left - box.right, box.left - shutter.right, 0f)
            val dy = maxOf(shutter.top - box.bottom, box.top - shutter.bottom, 0f)
            val gap = Math.hypot(dx.toDouble(), dy.toDouble())
            assertTrue("$name is $gap dp from the shutter", gap >= 100.0)
        }
    }

    // ── the control row ───────────────────────────────────────────────────────

    @Test
    fun `END is 40 dp from the start edge, the shutter is centred, SKIP is 40 dp from the end edge`() {
        val hud = hud()
        val end = boxIn(hud.root, hud.btnEnd)
        val shutter = boxIn(hud.root, hud.btnStart)
        val skip = boxIn(hud.root, hud.btnSkipExercise)
        assertEquals(40f, (end.left + end.right) / 2f, 0.5f)
        assertEquals(screenW / 2f, (shutter.left + shutter.right) / 2f, 0.5f)
        assertEquals(screenW - 40f, (skip.left + skip.right) / 2f, 0.5f)
        for ((name, box) in listOf("END" to end, "the shutter" to shutter, "SKIP" to skip)) {
            assertTrue("$name is ${box.width()} x ${box.height()} dp", box.width() >= 47.5f && box.height() >= 47.5f)
            assertEquals("$name is on the row's line", boxIn(hud.root, hud.btnStart).centerY(), box.centerY(), 0.5f)
        }
    }

    @Test
    fun `while the clock runs the row's controls show their icon only`() {
        val hud = hud()
        for (view in listOf(hud.btnEnd, hud.btnStart, hud.btnSkipExercise, hud.btnUndo, hud.btnAddRep)) {
            assertTrue("a control is not an icon", view is android.widget.ImageView)
        }
    }

    // ── the controls come forward when the athlete is at the phone (#167) ─────

    /** The HUD in [state], drawn the way the activity draws it, with the status line blank. */
    private fun at(state: WorkoutState, statusBlank: Boolean = true): ActivityMainBinding {
        val hud = hud()
        BottomBand.apply(hud, state, CameraControls.of(state, filming = false), statusBlank)
        layout(hud)
        show(hud, "3", "/5")
        return hud
    }

    private val atThePhone = listOf(WorkoutState.IDLE, WorkoutState.SETUP, WorkoutState.PAUSED)

    @Test
    fun `at the phone the shutter is a 72 dp disc, END and SKIP are 56 dp, and the figure is 56 sp`() {
        for (state in atThePhone) {
            val hud = at(state)
            val shutter = boxIn(hud.root, hud.btnStart)
            val skip = boxIn(hud.root, hud.btnSkipExercise)
            assertEquals("$state: shutter width", 72f, shutter.width(), 0.5f)
            assertEquals("$state: shutter height", 72f, shutter.height(), 0.5f)
            assertEquals("$state: SKIP width", 56f, skip.width(), 0.5f)
            assertEquals("$state: SKIP height", 56f, skip.height(), 0.5f)
            assertEquals("$state: the figure", 56f * density, hud.reps.textSize, 0.5f)
        }
        val paused = at(WorkoutState.PAUSED)
        val end = boxIn(paused.root, paused.btnEnd)
        assertEquals(56f, end.width(), 0.5f)
        assertEquals(56f, end.height(), 0.5f)
    }

    @Test
    fun `the controls keep their places, the shutter in the centre`() {
        for (state in atThePhone) {
            val hud = at(state)
            val shutter = boxIn(hud.root, hud.btnStart)
            val skip = boxIn(hud.root, hud.btnSkipExercise)
            assertEquals("$state: centred", screenW / 2f, shutter.centerX(), 0.5f)
            assertEquals("$state: SKIP is 40 dp from the end edge", screenW - 40f, skip.centerX(), 0.5f)
            assertEquals("$state: on the row's line", shutter.centerY(), skip.centerY(), 0.5f)
        }
        val paused = at(WorkoutState.PAUSED)
        assertEquals(40f, boxIn(paused.root, paused.btnEnd).centerX(), 0.5f)
    }

    @Test
    fun `the band's parts, from its top edge, are the ticket's table`() {
        for (state in atThePhone) {
            val hud = at(state)
            val edge = fromBand(hud, hud.repProgress)
            val zone = fromBand(hud, hud.repBlock)
            val figure = fromBand(hud, hud.reps)
            val line = fromBand(hud, hud.movementLine)
            val row = fromBand(hud, hud.controlRow)
            val names = fromBand(hud, hud.controlNames)
            assertEquals("$state: progress edge", 3f, edge.height(), 0.5f)
            assertEquals("$state: gap of 8", 3f + 8f, zone.top, 0.5f)
            assertEquals("$state: figure zone", 96f, zone.height(), 0.5f)
            assertTrue("$state: the figure is in the zone", figure.top >= zone.top - 0.5f && figure.bottom <= zone.bottom + 0.5f)
            assertTrue("$state: the line is in the zone, under the figure",
                line.top >= figure.bottom - 0.5f && line.bottom <= zone.bottom + 0.5f)
            assertEquals("$state: gap of 8", zone.bottom + 8f, row.top, 0.5f)
            assertEquals("$state: control row", 72f, row.height(), 0.5f)
            assertEquals("$state: gap of 4", row.bottom + 4f, names.top, 0.5f)
            assertEquals("$state: name row", 16f, names.height(), 0.5f)
            assertEquals("$state: where the name row ends, 207 dp down", 207f, names.bottom, 0.5f)
        }
    }

    @Test
    fun `the band is no taller at the phone than at the bar, with 12 dp or more under the name row`() {
        val running = dp(at(WorkoutState.RUNNING).bandBottom.height)
        for (state in atThePhone) {
            val hud = at(state)
            val band = dp(hud.bandBottom.height)
            assertTrue("$state: $band dp against $running running", band <= running + 0.5f)
            val under = band - fromBand(hud, hud.controlNames).bottom
            assertTrue("$state: $under dp under the name row", under >= 12f - 0.5f)
        }
    }

    @Test
    fun `the capsule keeps its place beside the figure zone at the phone`() {
        for (state in atThePhone) {
            val hud = at(state)
            val capsule = fromBand(hud, hud.stepper)
            val zone = fromBand(hud, hud.repBlock)
            assertEquals(48f, capsule.width(), 0.5f)
            assertEquals(zone.top, capsule.top, 0.5f)
            assertEquals(zone.bottom, capsule.bottom, 0.5f)
            assertEquals(screenW - 16f, capsule.right, 0.5f)
        }
    }

    @Test
    fun `12 over 15 still fits whole at 56 sp`() {
        val hud = at(WorkoutState.PAUSED)
        show(hud, "12", "/15")
        assertEquals(56f * density, hud.reps.textSize, 0.5f)
        assertEquals(0, hud.reps.layout.getEllipsisCount(0))
    }

    @Test
    @Config(sdk = [34], qualifiers = "w360dp-h780dp-xxhdpi", fontScale = 2f)
    fun `at the largest system text the band at the phone does not grow either`() {
        for (state in atThePhone) {
            val hud = at(state)
            assertTrue("$state: ${dp(hud.bandBottom.height)} dp", dp(hud.bandBottom.height) <= 219f + 0.5f)
            assertTrue("$state: the figure is taller than its box", hud.reps.textSize <= 72f * density + 0.5f)
        }
    }

    // ── the names under the controls ──────────────────────────────────────────

    private fun named(hud: ActivityMainBinding) =
        listOf(hud.nameEnd, hud.nameShutter, hud.nameSkip).filter { it.visibility == View.VISIBLE }

    @Test
    fun `a pause names END, RESUME and SKIP, each centred under its control`() {
        val hud = at(WorkoutState.PAUSED)
        assertEquals(listOf("END", "RESUME", "SKIP"), named(hud).map { it.text.toString() })
        val pairs = listOf(hud.nameEnd to hud.btnEnd, hud.nameShutter to hud.btnStart, hud.nameSkip to hud.btnSkipExercise)
        for ((name, control) in pairs) {
            assertEquals("${name.text} is centred under its control",
                boxIn(hud.root, control).centerX(), boxIn(hud.root, name).centerX(), 0.5f)
            assertTrue("${name.text} is under its control",
                boxIn(hud.root, name).top >= boxIn(hud.root, control).bottom - 0.5f)
        }
    }

    @Test
    fun `setup names SKIP alone and the dimmed shutter has no name`() {
        val hud = at(WorkoutState.SETUP)
        assertEquals(listOf("SKIP"), named(hud).map { it.text.toString() })
        assertEquals("the shutter is dimmed", 0.3f, hud.btnStart.alpha, 0.01f)
    }

    @Test
    fun `idle names nothing and says its one line under the shutter, centred`() {
        val hud = at(WorkoutState.IDLE)
        assertEquals(0, named(hud).size)
        assertEquals(View.VISIBLE, hud.idleLine.visibility)
        assertEquals("Press the shutter to start the setup check", hud.idleLine.text.toString())
        val line = boxIn(hud.root, hud.idleLine)
        val shutter = boxIn(hud.root, hud.btnStart)
        assertEquals(screenW / 2f, line.centerX(), 0.5f)
        assertTrue("under the shutter", line.top >= shutter.bottom - 0.5f)
        assertEquals("one row", 1, hud.idleLine.layout.lineCount)
        assertEquals("not cut", 0, hud.idleLine.layout.getEllipsisCount(0))
    }

    @Test
    fun `a label is no stop for a screen reader, and the shutter keeps the name the rules give it`() {
        val hud = at(WorkoutState.PAUSED)
        for (view in listOf(hud.nameEnd, hud.nameShutter, hud.nameSkip)) {
            assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, view.importantForAccessibility)
        }
        assertEquals("Resume", hud.btnStart.contentDescription.toString())
    }

    // ── the coaching pill ─────────────────────────────────────────────────────

    @Test
    fun `idle shows no coaching pill, setup and a pause show it`() {
        assertEquals(View.GONE, at(WorkoutState.IDLE).statusRow.visibility)
        assertEquals(View.VISIBLE, at(WorkoutState.SETUP, statusBlank = false).statusRow.visibility)
        assertEquals(View.VISIBLE, at(WorkoutState.PAUSED, statusBlank = false).statusRow.visibility)
    }

    @Test
    fun `a finished workout is drawn as idle`() {
        val finished = at(WorkoutState.FINISHED, statusBlank = false)
        val idle = at(WorkoutState.IDLE)
        assertEquals(View.GONE, finished.statusRow.visibility)
        assertEquals(View.VISIBLE, finished.idleLine.visibility)
        assertEquals(boxIn(idle.root, idle.btnStart), boxIn(finished.root, finished.btnStart))
        assertEquals(idle.bandBottom.height, finished.bandBottom.height)
    }

    // ── going between the two layouts ─────────────────────────────────────────

    @Test
    fun `while the clock runs there is no name row, and the row is as quiet as before`() {
        val hud = at(WorkoutState.RUNNING)
        assertEquals(View.GONE, hud.controlNames.visibility)
        assertEquals(48f, boxIn(hud.root, hud.btnStart).width(), 0.5f)
        assertEquals(48f, boxIn(hud.root, hud.btnEnd).width(), 0.5f)
        assertEquals(96f * density, hud.reps.textSize, 0.5f)
        assertEquals(View.VISIBLE, hud.statusRow.visibility)
    }

    @Test
    fun `starting, pausing and resuming switch between the two layouts, and running is the same each time`() {
        val hud = at(WorkoutState.RUNNING)
        fun boxes() = listOf(hud.btnStart, hud.btnEnd, hud.btnSkipExercise, hud.reps, hud.movementLine, hud.stepper)
            .map { boxIn(hud.root, it) }
        val first = boxes()
        val course = listOf(
            WorkoutState.SETUP, WorkoutState.RUNNING, WorkoutState.PAUSED,
            WorkoutState.RUNNING, WorkoutState.IDLE, WorkoutState.RUNNING
        )
        for (state in course) {
            BottomBand.apply(hud, state, CameraControls.of(state, filming = false), statusBlank = true)
            layout(hud)
            show(hud, "3", "/5")
            if (state == WorkoutState.RUNNING) {
                assertEquals("running after a change is not as it was", first, boxes())
                assertEquals(96f * density, hud.reps.textSize, 0.5f)
            } else {
                assertEquals("$state: 72 dp shutter", 72f, boxIn(hud.root, hud.btnStart).width(), 0.5f)
            }
            assertEquals("$state: band", 219f, dp(hud.bandBottom.height), 0.5f)
        }
    }
}
