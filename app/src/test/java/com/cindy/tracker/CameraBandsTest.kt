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
        // Read off this layout on origin/main (031dd48) before the ticket touched it. Robolectric
        // sets text with its own font metrics, so this is not the phone's 220 dp; it is the same
        // layout measured the same way, which is what "did not change" needs.
        assertEquals(182.67f, dp(hud.bandBottom.height), 0.5f)
    }
}
