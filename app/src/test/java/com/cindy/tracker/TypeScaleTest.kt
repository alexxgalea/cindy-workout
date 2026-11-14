package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The type scale, read the way a TextView reads it: through the style, not through the file that
 * declares it. What these hold is the chosen typeface (Inter) across every text style, and tabular
 * figures on every style whose text is a number that can change, so a running clock or a rep
 * count does not shift sideways as it counts.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TypeScaleTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val numeric = mapOf(
        "MetricXL" to R.style.Cindy_MetricXL,
        "MetricL" to R.style.Cindy_MetricL,
        "MetricM" to R.style.Cindy_MetricM,
        "MetricS" to R.style.Cindy_MetricS,
        "MetricXL.Quiet" to R.style.Cindy_MetricXL_Quiet,
        "Scoreboard" to R.style.Cindy_Scoreboard
    )

    private val prose = mapOf(
        "Title" to R.style.Cindy_Title,
        "Title2" to R.style.Cindy_Title2,
        "Headline" to R.style.Cindy_Headline,
        "Body" to R.style.Cindy_Body,
        "Callout" to R.style.Cindy_Callout,
        "Footnote" to R.style.Cindy_Footnote,
        "Eyebrow" to R.style.Cindy_Eyebrow,
        "Button" to R.style.Cindy_Button,
        "Button.Small" to R.style.Cindy_Button_Small,
        "ScoreLine" to R.style.Cindy_ScoreLine
    )

    private fun fontOf(style: Int): String {
        val ta = context.obtainStyledAttributes(style, intArrayOf(android.R.attr.fontFamily))
        try {
            val id = ta.getResourceId(0, 0)
            assertNotEquals("style sets no font", 0, id)
            return context.resources.getResourceEntryName(id)
        } finally {
            ta.recycle()
        }
    }

    private fun featuresOf(style: Int): String? {
        val ta = context.obtainStyledAttributes(style, intArrayOf(android.R.attr.fontFeatureSettings))
        try {
            return ta.getString(0)
        } finally {
            ta.recycle()
        }
    }

    @Test
    fun `every text style is set in Inter`() {
        for ((name, style) in numeric + prose) {
            val font = fontOf(style)
            assertTrue("Cindy.$name is set in $font, not Inter", font.startsWith("inter_"))
        }
    }

    @Test
    fun `the theme's default family is Inter too, so an unstyled TextView is not left behind`() {
        for (theme in listOf(R.style.Theme_Cindy, R.style.Theme_Cindy_Sheet)) {
            val ta = context.obtainStyledAttributes(theme, intArrayOf(android.R.attr.fontFamily))
            val font = context.resources.getResourceEntryName(ta.getResourceId(0, 0))
            ta.recycle()
            assertEquals("inter", font)
        }
    }

    @Test
    fun `every numeric style has tabular figures`() {
        for ((name, style) in numeric) {
            val features = featuresOf(style).orEmpty()
            assertTrue("Cindy.$name has no tabular figures", "tnum" in features.split(',').map { it.trim() })
        }
    }

    @Test
    fun `prose styles keep proportional figures, because tabular ones in a sentence read as a spreadsheet`() {
        for ((name, style) in prose) {
            assertTrue("Cindy.$name sets tnum", "tnum" !in featuresOf(style).orEmpty())
        }
    }
}
