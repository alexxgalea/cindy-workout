package com.cindy.tracker

import java.io.File
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What is bundled as the app's typeface, checked from the files the build packages: the family
 * is Inter at the five weights the type scale asks for, each file still has the `tnum` feature
 * (the subsetter drops features it is not told to keep, and a clock without it shifts sideways),
 * and each covers every character the app prints. Plus the rule that keeps the choice in one
 * place: no layout and no view names a font of its own, so replacing the family is replacing
 * the files and one accessor.
 */
class BundledTypeTest {

    private val weights = listOf("regular", "medium", "semibold", "bold", "extrabold")

    private val moduleDir: File = run {
        val start = File(System.getProperty("user.dir") ?: ".").absoluteFile
        listOf(start, File(start, "app")).first { File(it, "src/main/res/font").isDirectory }
    }
    private val fontDir = File(moduleDir, "src/main/res/font")

    /** Every character the app prints in its own typeface, apart from the emoji it hands the system. */
    private val printed: List<Int> = buildList {
        addAll(0x20..0x7E)
        // Latin-1, less the soft hyphen (U+00AD): invisible, so nothing prints it.
        addAll((0xA0..0xFF).filter { it != 0xAD })
        // Interpunct, dashes, quotes, ellipsis, minus, the floor sign on a round, ≈ in the Strava text.
        addAll(listOf(0x2013, 0x2014, 0x201C, 0x201D, 0x2026, 0x2212, 0x2265, 0x2248))
        // Romanian, which the language list spells "Română", and the letters a name starts with.
        addAll(listOf(0x102, 0x103, 0x218, 0x219, 0x21A, 0x21B, 0x15E, 0x15F))
    }

    @Test
    fun `the five weights are Inter, and no Manrope file is left`() {
        for (w in weights) {
            val file = File(fontDir, "inter_$w.ttf")
            assertTrue("${file.name} is not bundled", file.isFile)
            val family = TrueType(file.readBytes()).family()
            assertTrue("${file.name} is the family '$family'", family == "Inter")
        }
        assertEquals(
            "Manrope files are still bundled",
            emptyList<String>(),
            fontDir.list().orEmpty().filter { it.contains("manrope", ignoreCase = true) }
        )
    }

    @Test
    fun `every weight still has tabular figures`() {
        for (w in weights) {
            val features = TrueType(File(fontDir, "inter_$w.ttf").readBytes()).gsubFeatures()
            assertTrue("inter_$w has no tnum, only $features", "tnum" in features)
        }
    }

    @Test
    fun `every weight covers what the app prints`() {
        for (w in weights) {
            val font = TrueType(File(fontDir, "inter_$w.ttf").readBytes())
            val missing = printed.filterNot { font.covers(it) }
            assertEquals(
                "inter_$w lacks ${missing.joinToString { "U+%04X".format(it) }}",
                emptyList<Int>(), missing
            )
        }
    }

    @Test
    fun `no layout names a font of its own`() {
        val offenders = File(moduleDir, "src/main/res/layout").walkTopDown()
            .filter { it.extension == "xml" }
            .filter { Regex("""android:(fontFamily|textFontWeight|typeface)""").containsMatchIn(it.readText()) }
            .map { it.name }.toList()
        assertEquals("these layouts choose a typeface themselves", emptyList<String>(), offenders)
    }

    @Test
    fun `only the type accessor names a font resource in code`() {
        val offenders = File(moduleDir, "src/main/java").walkTopDown()
            .filter { it.extension == "kt" && it.name != "CindyType.kt" }
            .filter { it.readText().contains("R.font.") }
            .map { it.name }.toList()
        assertEquals("these views reach for a font file directly", emptyList<String>(), offenders)
        assertTrue("CindyType.kt is missing", File(moduleDir, "src/main/java/com/cindy/tracker/CindyType.kt").isFile)
    }

    @Test
    fun `nothing in the app still refers to Manrope as its typeface`() {
        val offenders = File(moduleDir, "src/main").walkTopDown()
            .filter { it.isFile && (it.extension == "kt" || it.extension == "xml") }
            .filter { it.readText().contains("manrope", ignoreCase = true) }
            .map { it.name }.toList()
        assertFalse("still mentions Manrope: $offenders", offenders.isNotEmpty())
    }

    /** Just enough of an OpenType file to ask it three questions. */
    private class TrueType(bytes: ByteArray) {
        private val buf = ByteBuffer.wrap(bytes)
        private val tables = HashMap<String, Int>()

        init {
            val n = buf.getShort(4).toInt() and 0xFFFF
            for (i in 0 until n) {
                val rec = 12 + i * 16
                val tag = String(bytes, rec, 4, Charsets.ISO_8859_1)
                tables[tag] = buf.getInt(rec + 8)
            }
        }

        private fun u16(at: Int) = buf.getShort(at).toInt() and 0xFFFF

        fun family(): String {
            val t = tables.getValue("name")
            val count = u16(t + 2)
            val strings = t + u16(t + 4)
            var found: String? = null
            for (i in 0 until count) {
                val r = t + 6 + i * 12
                val platform = u16(r)
                val id = u16(r + 6)
                if (platform != 3 || (id != 1 && id != 16)) continue
                val len = u16(r + 8)
                val off = strings + u16(r + 10)
                val raw = ByteArray(len).also { buf.position(off); buf.get(it) }
                val name = String(raw, Charsets.UTF_16BE)
                // The typographic family (16) wins over the weight-qualified one (1).
                if (id == 16 || found == null) found = name
            }
            return found ?: error("no family name")
        }

        fun gsubFeatures(): Set<String> {
            val t = tables["GSUB"] ?: return emptySet()
            val list = t + u16(t + 6)
            val n = u16(list)
            return (0 until n).map {
                val at = list + 2 + it * 6
                ByteArray(4).also { b -> buf.position(at); buf.get(b) }.toString(Charsets.ISO_8859_1)
            }.toSet()
        }

        fun covers(cp: Int): Boolean {
            val cmap = tables.getValue("cmap")
            val n = u16(cmap + 2)
            for (i in 0 until n) {
                val rec = cmap + 4 + i * 8
                if (u16(rec) != 3 || u16(rec + 2) != 1) continue
                val sub = cmap + buf.getInt(rec + 4)
                check(u16(sub) == 4) { "cmap subtable is format ${u16(sub)}, expected 4" }
                val segs = u16(sub + 6) / 2
                val ends = sub + 14
                val starts = ends + segs * 2 + 2
                val deltas = starts + segs * 2
                val ranges = deltas + segs * 2
                for (s in 0 until segs) {
                    if (cp > u16(ends + s * 2)) continue
                    if (cp < u16(starts + s * 2)) return false
                    val ro = u16(ranges + s * 2)
                    val glyph = if (ro == 0) {
                        (cp + u16(deltas + s * 2)) and 0xFFFF
                    } else {
                        val g = u16(ranges + s * 2 + ro + (cp - u16(starts + s * 2)) * 2)
                        if (g == 0) 0 else (g + u16(deltas + s * 2)) and 0xFFFF
                    }
                    return glyph != 0
                }
                return false
            }
            error("no Unicode BMP cmap")
        }
    }
}
