package com.cindy.tracker

import android.content.Context
import android.graphics.Color
import android.view.ViewGroup
import android.widget.ImageView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * Orange is the colour of achievement and of nothing else: a streak flame, a trained day, a
 * badge, a rank disc, a personal record. Green is the affirmative, red is blocked or stopping,
 * and a caution is not coloured at all.
 *
 * The rule is held where the tokens are defined, `res/values/colors.xml`, so that a second
 * orange cannot arrive as a new token without a test noticing.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AchievementColourTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun colorsXml(): String {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        return File(dir, "app/src/main/res/values/colors.xml").readText()
    }

    /** name to ARGB, from the `<color name="x">#AARRGGBB</color>` lines. */
    private fun tokens(): Map<String, Int> =
        Regex("""<color name="(\w+)">(#[0-9A-Fa-f]{6,8})</color>""")
            .findAll(colorsXml())
            .associate { it.groupValues[1] to Color.parseColor(it.groupValues[2]) }

    private fun isOrange(argb: Int): Boolean {
        val hsv = FloatArray(3)
        Color.colorToHSV(argb, hsv)
        return hsv[0] in 10f..50f && hsv[1] >= 0.5f && hsv[2] >= 0.6f
    }

    @Test
    fun `the palette has one orange and it is the achievement token`() {
        val oranges = tokens().filterValues { isOrange(it) }.keys
        assertEquals(setOf("achievement"), oranges)
    }

    @Test
    fun `there is no caution token to colour anything with`() {
        assertFalse(tokens().containsKey("state_caution"))
    }

    @Test
    fun `the colour rule is written beside the tokens`() {
        val header = colorsXml().substringBefore("<resources>")
        assertTrue(header.contains("Orange is achievement"))
        assertFalse(header.contains("Orange cautions"))
    }

    @Test
    fun `the placement facts carry no orange, the warning fact included`() {
        val facts = context.placementFacts()
        val tints = (0 until facts.childCount).map { row ->
            val line = facts.getChildAt(row) as ViewGroup
            (0 until line.childCount).map { line.getChildAt(it) }
                .filterIsInstance<ImageView>().single().imageTintList!!.defaultColor
        }
        assertEquals(3, tints.size)
        assertTrue("an orange icon in the placement facts", tints.none { isOrange(it) })
        // The last fact is the one that warns; it reads brighter than its neighbours, not redder.
        assertEquals(context.getColor(R.color.label), tints[2])
        assertEquals(context.getColor(R.color.label_tertiary), tints[0])
    }
}
