package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * Every icon in the app is Phosphor's, on Phosphor's grid and at Phosphor's weight (ADR 0008).
 *
 * The checks read the drawables the way a screen resolves them, by resource id, so they hold for
 * any icon a future screen adds under the `ic_` name: a set drawn on another grid, or at another
 * stroke, cannot slip in beside the others.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class IconSetTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    /** Every `ic_` drawable of the app, but the launcher's, which is the app's mark and not a glyph. */
    private val icons: Map<String, Int> =
        R.drawable::class.java.fields
            .filter { it.name.startsWith("ic_") && it.name != "ic_launcher_foreground" }
            .associate { it.name to it.getInt(null) }

    private val root: File = run {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        checkNotNull(dir) { "Cannot find the repository root" }
    }

    private fun attributes(resId: Int): List<Map<String, String>> {
        val xml = context.resources.getXml(resId)
        val found = mutableListOf<Map<String, String>>()
        while (xml.next() != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
            if (xml.eventType != org.xmlpull.v1.XmlPullParser.START_TAG) continue
            found += (0 until xml.attributeCount).associate { xml.getAttributeName(it) to xml.getAttributeValue(it) }
        }
        return found
    }

    @Test
    fun `there are icons to check`() {
        assertTrue("the app has ${icons.size} icons", icons.size >= 15)
    }

    @Test
    fun `every icon resolves to a drawable with a size`() {
        for ((name, id) in icons) {
            val drawable = context.getDrawable(id)
            assertNotNull("$name does not resolve", drawable)
            assertTrue("$name has no size", drawable!!.intrinsicWidth > 0 && drawable.intrinsicHeight > 0)
        }
    }

    @Test
    fun `every icon is drawn on Phosphor's 256 grid and shown at 24 dp`() {
        for ((name, id) in icons) {
            val vector = attributes(id).first()
            assertEquals("$name: viewport width", "256.0", vector["viewportWidth"])
            assertEquals("$name: viewport height", "256.0", vector["viewportHeight"])
            assertEquals("$name: width", "24.0dip", vector["width"])
            assertEquals("$name: height", "24.0dip", vector["height"])
        }
    }

    /** Phosphor's regular weight is 16 units of its 256. Its glyphs are outlines already; the one drawn here is stroked. */
    @Test
    fun `an icon that is stroked is stroked at Phosphor's weight`() {
        for ((name, id) in icons) {
            for (path in attributes(id)) {
                val width = path["strokeWidth"] ?: continue
                assertEquals("$name: stroke width", "16.0", width)
            }
        }
    }

    @Test
    fun `every icon is used by a screen, so the old set leaves nothing behind`() {
        val sources = listOf("app/src/main/java", "app/src/main/res/layout", "app/src/main/res/drawable", "app/src/main/res/values", "app/src/main/AndroidManifest.xml")
            .map { File(root, it) }
            .flatMap { if (it.isDirectory) it.walkTopDown().filter { f -> f.isFile }.toList() else listOf(it) }
            .joinToString("\n") { it.readText() }
        for (name in icons.keys) {
            val used = sources.contains("R.drawable.$name") || sources.contains("@drawable/$name")
            assertTrue("$name is not used anywhere", used)
        }
    }
}
