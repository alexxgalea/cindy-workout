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

    // ── the bottom band, which this work leaves alone ─────────────────────────

    @Test
    fun `the bottom band measures what it measured before the top band became one row`() {
        val hud = hud()
        // Read off this layout on origin/main (031dd48) before the ticket touched it, with native
        // graphics so the text has the real fonts' metrics. About 5 dp under the phone's 220.
        assertEquals(215.33f, dp(hud.bandBottom.height), 0.5f)
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
}
