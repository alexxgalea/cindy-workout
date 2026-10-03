package com.cindy.tracker

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The store listing, held to Google Play's limits and to what the app actually does.
 *
 * The text lives in `play/listing/en-US/`, outside the app, so nothing else would notice it going
 * over a limit, naming something the app does not do, or growing a claim Play's metadata policy
 * rejects. A listing is written once for two builds: the Strava sentences sit between
 * `{{#strava}}` and `{{/strava}}`, and `tools/play/render.py` keeps or drops them. This reads the
 * same markers, so both builds' text is checked, not only the one a reader happens to render.
 */
class PlayListingTest {

    private val root: File = run {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        checkNotNull(dir) { "Cannot find the repository root from ${System.getProperty("user.dir")}" }
    }

    private fun listing(name: String): String {
        val file = File(root, "play/listing/en-US/$name")
        check(file.isFile) { "Missing listing file ${file.absolutePath}" }
        return file.readText()
    }

    /** The same rule `render.py` applies: drop the Strava blocks, or keep their contents. */
    private fun render(raw: String, withStrava: Boolean): String {
        val block = Regex("""\{\{#strava\}\}(.*?)\{\{/strava\}\}\n?""", RegexOption.DOT_MATCHES_ALL)
        val out = block.replace(raw) { if (withStrava) it.groupValues[1].trimStart('\n') else "" }
        return out.trim()
    }

    /** One file per version code, named for it, so each upload has notes of its own. */
    private val releaseNotes: List<String> =
        File(root, "play/listing/en-US/release-notes").listFiles { f -> f.extension == "txt" }
            .orEmpty().map { "release-notes/${it.name}" }.sorted()

    private val files = listOf("title.txt", "short-description.txt", "full-description.txt") + releaseNotes
    private val variants = listOf(false, true)

    @Test
    fun `every Strava block is closed, and none is left after rendering`() {
        for (name in files) {
            val raw = listing(name)
            assertEquals("$name has an unbalanced Strava block",
                Regex("""\{\{#strava\}\}""").findAll(raw).count(),
                Regex("""\{\{/strava\}\}""").findAll(raw).count())
            for (withStrava in variants) {
                assertFalse("$name still has a marker (strava=$withStrava)",
                    render(raw, withStrava).contains("{{"))
            }
        }
    }

    @Test
    fun `the title, the short description and the full description fit Google Play's limits`() {
        for (withStrava in variants) {
            val title = render(listing("title.txt"), withStrava)
            val short = render(listing("short-description.txt"), withStrava)
            val full = render(listing("full-description.txt"), withStrava)
            assertTrue("title is ${title.length} characters, the limit is 30", title.length in 1..30)
            assertTrue("short description is ${short.length}, the limit is 80", short.length in 1..80)
            assertTrue("full description is ${full.length}, the limit is 4000", full.length in 1..4000)
        }
    }

    @Test
    fun `every release note fits Google Play's 500 characters`() {
        assertTrue("there are no release notes", releaseNotes.isNotEmpty())
        for (name in releaseNotes) for (withStrava in variants) {
            val note = render(listing(name), withStrava)
            assertTrue("$name is ${note.length} characters, the limit is 500 (strava=$withStrava)",
                note.length in 1..500)
        }
    }

    @Test
    fun `there are release notes for the version this build is`() {
        val file = File(root, "play/listing/en-US/release-notes/${BuildConfig.VERSION_CODE}.txt")
        assertTrue(
            "versionCode is ${BuildConfig.VERSION_CODE}; write ${file.relativeTo(root)} before an upload",
            file.isFile
        )
    }

    @Test
    fun `a language count anywhere in the listing is the number the app has`() {
        for (name in files) {
            Regex("""(\d+) languages""").findAll(listing(name)).forEach {
                assertEquals("$name says ${it.value}", VoicePacks.all.size, it.groupValues[1].toInt())
            }
        }
    }

    @Test
    fun `no listing text names Strava in a build that has none`() {
        for (name in files) {
            assertFalse("$name still names Strava without it",
                render(listing(name), withStrava = false).contains("strava", ignoreCase = true))
        }
    }

    @Test
    fun `the title and short description name neither CrossFit nor Strava`() {
        for (name in listOf("title.txt", "short-description.txt")) {
            val text = listing(name)
            assertFalse("$name mentions CrossFit", text.contains("crossfit", ignoreCase = true))
            assertFalse("$name mentions Strava", text.contains("strava", ignoreCase = true))
        }
    }

    @Test
    fun `CrossFit appears only in the sentences that say Cindy is not CrossFit's`() {
        val full = render(listing("full-description.txt"), withStrava = true)
        val sentence = "Cindy Tracker is an independent app. It is not affiliated with or endorsed " +
            "by CrossFit, LLC. CrossFit is a registered trademark of CrossFit, LLC."
        assertTrue("the non-affiliation sentence is missing or has changed", full.contains(sentence))
        assertEquals("CrossFit is named outside the disclaimer",
            0, full.replace(sentence, "").split(Regex("(?i)crossfit")).size - 1)
    }

    @Test
    fun `Strava is named only in a build that has it, and never as an endorsement`() {
        val without = render(listing("full-description.txt"), withStrava = false)
        val with = render(listing("full-description.txt"), withStrava = true)
        assertFalse("a build without Strava still talks about it", without.contains("strava", ignoreCase = true))
        assertTrue(with.contains("Strava"))
        for (word in listOf("official", "partner", "endorsed by strava", "powered by strava")) {
            assertFalse("the Strava text says '$word'", with.contains(word, ignoreCase = true))
        }
    }

    @Test
    fun `nothing in the listing is what Google Play's metadata policy turns away`() {
        for (name in files) for (withStrava in variants) {
            val text = render(listing(name), withStrava)
            val where = "$name (strava=$withStrava)"
            for (word in listOf("best", "free", "new", "top", "sale", "discount")) {
                assertFalse("$where says '$word'", Regex("""(?i)\b$word\b""").containsMatchIn(text))
            }
            assertFalse("$where says #1", text.contains("#1"))
            assertFalse("$where has an emoji", text.codePoints().anyMatch { cp ->
                cp in 0x1F000..0x1FAFF || cp in 0x2600..0x27BF || cp == 0xFE0F || cp == 0x2B50
            })
            // Shouting: three capitalised words in a row. Acronyms like AMRAP, REC and LLC stand alone.
            assertFalse("$where has a run of capitals",
                Regex("""\b[A-Z]{2,}\b[ ,]+\b[A-Z]{2,}\b[ ,]+\b[A-Z]{2,}\b""").containsMatchIn(text))
        }
    }

    @Test
    fun `the description counts the voice languages the app has`() {
        val full = render(listing("full-description.txt"), withStrava = true)
        assertTrue(
            "the listing should say ${VoicePacks.all.size} languages",
            full.contains("in ${VoicePacks.all.size} languages")
        )
    }
}
