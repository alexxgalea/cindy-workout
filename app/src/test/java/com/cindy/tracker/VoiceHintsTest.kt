package com.cindy.tracker

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps the voice's hint catalogue honest against the engine that produces the hints.
 *
 * The engine words its hints as English string literals and the voice translates them by that
 * text, so the failure this guards against is quiet: someone adds a hint to [WorkoutEngine], the
 * voice has no entry for it, and a Spanish-speaking athlete hears English in the middle of a
 * set — or hears the generic fallback where a specific instruction was meant. Nothing else would
 * notice, because the hint still shows on screen and still counts.
 *
 * So the engine's own sources are read and every string literal in them has to be accounted for,
 * either as a [Hint] or as something known never to be spoken. Adding a literal to either file
 * fails this test until someone has said which.
 */
class VoiceHintsTest {

    /** Where the hints are worded. */
    private val engineFiles = listOf("WorkoutEngine.kt", "TrackingHealth.kt")

    /**
     * Literals in those files that are not hints: names and labels that have their own voice
     * lines or are only ever shown, phase names in the debug readout, and failure text.
     */
    private val notSpoken = setOf(
        "PULL-UPS", "pull ups", "PUSH-UPS", "push ups", "SQUATS", "squats",
        "idle", "down", "up",
        "Frame dimensions must be positive",
        "Missing \${missing.joinToString()}"
    )

    private fun sourceOf(name: String): String {
        val relative = "app/src/main/java/com/cindy/tracker/$name"
        val explicit = System.getProperty("cindy.repo")?.let { File(it, relative) }
        if (explicit != null && explicit.isFile) return explicit.readText()
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, relative).isFile) dir = dir.parentFile
        return (dir ?: error("Could not find $relative from ${System.getProperty("user.dir")}"))
            .let { File(it, relative).readText() }
    }

    private fun literalsIn(name: String): Set<String> = stringLiterals(sourceOf(name)).toSet()

    @Test
    fun `every string in the engine is a catalogued hint or known not to be spoken`() {
        val known = Hint.entries.map { it.english }.toSet() + notSpoken
        engineFiles.forEach { file ->
            val unaccounted = literalsIn(file) - known
            assertTrue(
                "$file has string(s) the voice does not know about: $unaccounted. If a hint, " +
                    "add it to Hint and to every phrasebook; if it is never spoken, add it to " +
                    "notSpoken in this test.",
                unaccounted.isEmpty()
            )
        }
    }

    @Test
    fun `every catalogued hint is still in the engine`() {
        val inEngine = engineFiles.flatMap { literalsIn(it) }.toSet()
        val stale = Hint.entries.filter { it.english !in inEngine }
        assertTrue("catalogued but no longer in the engine: $stale", stale.isEmpty())
    }

    @Test
    fun `the start cues are catalogued`() {
        Exercise.entries.forEach { assertNotNull(it.startCue, Hint.of(it.startCue)) }
    }

    @Test
    fun `a hint is found by the engine's text`() {
        assertEquals(Hint.GET_ON_BAR, Hint.of("Get on the bar"))
        assertEquals(Hint.CANT_SEE_YOU, Hint.of("Can't see you — tap +1"))
        assertNull(Hint.of("Something nobody catalogued"))
    }

    @Test
    fun `no two hints share their text`() {
        assertEquals(Hint.entries.size, Hint.entries.map { it.english }.toSet().size)
    }

    // ── the reader the checks above depend on ─────────────────────────────────

    @Test
    fun `the reader finds the engine's strings, so an empty result cannot pass`() {
        assertTrue(literalsIn("WorkoutEngine.kt").size >= 15)
        assertTrue(literalsIn("TrackingHealth.kt").size >= 3)
    }

    @Test
    fun `the reader takes strings and skips comments and characters`() {
        val source = listOf(
            "// \"in a line comment\"",
            "/* \"in a /* nested \"block\" */ comment\" */",
            "val a = \"one\"",
            "val b = \"say \\\"hi\\\"\"",
            "val c = \"n=\${items.joinToString(\"; \")} end\"",
            "val d = '\"'",
            "val e = \"\"\"raw \"quoted\" text\"\"\"",
            "fun `a name with \"quotes\"`() = \"last\""
        ).joinToString("\n")

        assertEquals(
            listOf(
                "one",
                "say \\\"hi\\\"",
                "n=\${items.joinToString(\"; \")} end",
                "raw \"quoted\" text",
                "last"
            ),
            stringLiterals(source)
        )
    }

    /** Every string literal in Kotlin [source], comments and characters excluded. */
    private fun stringLiterals(source: String): List<String> {
        val found = mutableListOf<String>()
        var i = 0
        while (i < source.length) {
            when {
                source.startsWith("//", i) ->
                    i = source.indexOf('\n', i).let { if (it < 0) source.length else it }
                source.startsWith("/*", i) -> i = endOfBlockComment(source, i)
                source.startsWith("\"\"\"", i) -> {
                    val end = source.indexOf("\"\"\"", i + 3)
                    check(end >= 0) { "unterminated raw string" }
                    found += source.substring(i + 3, end)
                    i = end + 3
                }
                source[i] == '"' -> {
                    val (text, next) = readString(source, i)
                    found += text
                    i = next
                }
                source[i] == '\'' -> i = endOfChar(source, i)
                source[i] == '`' -> i = source.indexOf('`', i + 1) + 1
                else -> i++
            }
        }
        return found
    }

    /** Block comments nest in Kotlin. */
    private fun endOfBlockComment(source: String, start: Int): Int {
        var depth = 1
        var i = start + 2
        while (i < source.length && depth > 0) {
            when {
                source.startsWith("/*", i) -> { depth++; i += 2 }
                source.startsWith("*/", i) -> { depth--; i += 2 }
                else -> i++
            }
        }
        return i
    }

    private fun endOfChar(source: String, start: Int): Int {
        var i = start + 1
        i += if (source[i] == '\\') 2 else 1
        while (source[i] != '\'') i++
        return i + 1
    }

    /** The text of the string opening at [start], and where it ends. */
    private fun readString(source: String, start: Int): Pair<String, Int> {
        val text = StringBuilder()
        var i = start + 1
        while (source[i] != '"') {
            when {
                source[i] == '\\' -> { text.append(source, i, i + 2); i += 2 }
                source.startsWith("\${", i) -> {
                    // A template expression can hold braces, and strings of its own. Taking the
                    // dollar first leaves the loop on the opening brace, so depth is already 1
                    // by the time it asks whether the expression has ended.
                    text.append('$')
                    i++
                    var depth = 0
                    do {
                        val c = source[i]
                        if (c == '"') {
                            val (nested, after) = readString(source, i)
                            text.append('"').append(nested).append('"')
                            i = after
                            continue
                        }
                        if (c == '{') depth++
                        if (c == '}') depth--
                        text.append(c)
                        i++
                    } while (depth > 0)
                }
                else -> { text.append(source[i]); i++ }
            }
        }
        return text.toString() to (i + 1)
    }
}
