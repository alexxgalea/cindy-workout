package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What must hold for every language at once.
 *
 * The compiler already refuses a phrasebook that lacks a line or a hint. What it cannot refuse is
 * a line that compiles and is wrong in a way that only a voice reveals: a blank, a template that
 * leaked into the sentence, English left in the middle of Spanish, or a number followed by a full
 * stop, which some engines read as an ordinal ("12." as "twelfth") in the middle of a score.
 *
 * Language-specific grammar is pinned in each language's own test; this is the floor under all of
 * them, and the first place a new language is checked.
 */
class PhrasebooksTest {

    private val others = VoicePacks.all.filter { it.tag != "en" }

    /** Counts where languages change their mind, run through every line that carries one. */
    private val counts = listOf(0, 1, 2, 3, 4, 5, 11, 12, 14, 19, 20, 21, 22, 25, 101, 111, 112, 121)

    /** Every line that takes a number, at every one of those numbers, plus the fixed samples. */
    private val lines: List<VoiceLine> = VoiceLineSamples.all + counts.flatMap { n ->
        listOf(
            VoiceLine.Score(n, n * 30),
            VoiceLine.Score(0, n),
            VoiceLine.RoundDone(n, n * 7_000L),
            VoiceLine.RoundDone(n, n * 61_000L),
            VoiceLine.Averaging(n * 9_000L),
            VoiceLine.RecordingSoon(n)
        ) + ClockMark.entries.flatMap { mark ->
            listOf(
                VoiceLine.Clock(mark, n, n * 30, n + 1),
                VoiceLine.Clock(mark, n, n * 30, null)
            )
        }
    }

    private fun forEveryLine(check: (VoicePack, VoiceLine, String) -> Unit) {
        VoicePacks.all.forEach { pack ->
            lines.forEach { line -> check(pack, line, pack.phrasebook.say(line)) }
        }
    }

    @Test
    fun `nothing is blank or padded`() = forEveryLine { pack, line, said ->
        assertTrue("${pack.tag}: $line was blank", said.isNotBlank())
        assertEquals("${pack.tag}: $line has stray space in \"$said\"", said.trim(), said)
        assertFalse("${pack.tag}: $line has a double space in \"$said\"", "  " in said)
    }

    @Test
    fun `no template or null leaks into a sentence`() = forEveryLine { pack, line, said ->
        listOf("null", "$", "{", "}", "@").forEach {
            assertFalse("${pack.tag}: $line said \"$said\"", it in said)
        }
    }

    @Test
    fun `no sentence ends a number with a full stop`() {
        // English is exempt: its lines are pinned byte for byte and "on for 12." is one of them.
        val digitThenStop = Regex("""\d\.""")
        others.forEach { pack ->
            lines.forEach { line ->
                val said = pack.phrasebook.say(line)
                assertFalse(
                    "${pack.tag}: \"$said\" has a number before a full stop",
                    digitThenStop.containsMatchIn(said)
                )
            }
        }
    }

    @Test
    fun `no line is long enough to lose the athlete`() = forEveryLine { pack, line, said ->
        assertTrue("${pack.tag}: \"$said\" is ${said.length} characters", said.length <= 160)
    }

    @Test
    fun `a count is the bare number in every language`() {
        VoicePacks.all.forEach { pack ->
            counts.forEach { n -> assertEquals("${pack.tag}", "$n", pack.phrasebook.say(VoiceLine.Count(n))) }
        }
    }

    @Test
    fun `no language answers in English`() {
        val english = PhrasebookEn
        others.forEach { pack ->
            // Counts are numerals and some movements are borrowed words ("squats"), so both are
            // allowed to match; everything else in another language is not English.
            VoiceLineSamples.all
                .filter { it !is VoiceLine.Count && it !is VoiceLine.Movement }
                .forEach { line ->
                    assertNotEquals(
                        "${pack.tag} speaks English for $line",
                        english.say(line),
                        pack.phrasebook.say(line)
                    )
                }
        }
    }

    @Test
    fun `every hint has words, and none of them is the English`() {
        others.forEach { pack ->
            Hint.entries.forEach { hint ->
                val said = pack.phrasebook.say(VoiceLine.Fault(hint.english))
                assertTrue("${pack.tag}: $hint was blank", said.isNotBlank())
                assertNotEquals("${pack.tag} leaves $hint in English", hint.english, said)
            }
        }
    }

    @Test
    fun `hints are each said their own way`() {
        others.forEach { pack ->
            val said = Hint.entries.map { pack.phrasebook.say(VoiceLine.Fault(it.english)) }
            // "Hang from the bar" is both a hint and a start cue, and is one entry; the rest are
            // different instructions and must not collapse into the same sentence.
            assertEquals("${pack.tag} says two hints the same", said.size, said.toSet().size)
        }
    }

    @Test
    fun `an uncatalogued hint is a generic prompt in the language, never the English`() {
        others.forEach { pack ->
            val said = pack.phrasebook.say(VoiceLine.Fault("Something nobody catalogued"))
            assertTrue("${pack.tag} was blank", said.isNotBlank())
            assertNotEquals("${pack.tag} echoed the English", "Something nobody catalogued", said)
        }
    }

    @Test
    fun `the lines that differ in meaning differ in words`() {
        VoicePacks.all.forEach { pack ->
            val book = pack.phrasebook
            fun distinct(what: String, vararg lines: VoiceLine) {
                val said = lines.map { book.say(it) }
                assertEquals("${pack.tag}: $what collapsed into one sentence", said.size, said.toSet().size)
            }
            distinct("movements", *Exercise.entries.map { VoiceLine.Movement(it) }.toTypedArray())
            distinct("the recording announcements", VoiceLine.RecordingSoon(3), VoiceLine.RecordingStarted, VoiceLine.RecordingFailed)
            distinct("the start", VoiceLine.Go(true), VoiceLine.Go(false))
            distinct("the end", VoiceLine.Finished(true), VoiceLine.Finished(false))
            distinct(
                "the clock marks",
                *ClockMark.entries.map { VoiceLine.Clock(it, 6, 185, 12) }.toTypedArray()
            )
        }
    }

    @Test
    fun `a round's number and its seconds are both in the sentence`() {
        // 95 seconds is a minute and 35. The minute is written out in most languages, but the 35
        // is a digit in all of them.
        VoicePacks.all.forEach { pack ->
            val said = pack.phrasebook.say(VoiceLine.RoundDone(7, 95_000L))
            assertTrue("${pack.tag}: \"$said\" lost the round number", "7" in said)
            assertTrue("${pack.tag}: \"$said\" lost the seconds", "35" in said)
        }
    }

    @Test
    fun `the benchmark's name arrives untouched`() {
        VoicePacks.all.forEach { pack ->
            val said = pack.phrasebook.say(VoiceLine.BeatBenchmark("Tom Holland"))
            assertTrue("${pack.tag}: \"$said\"", "Tom Holland" in said)
        }
    }
}
