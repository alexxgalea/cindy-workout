package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AvatarTest {

    // ── cleanName ─────────────────────────────────────────────────────────────

    @Test
    fun `a name is kept as it was typed`() {
        assertEquals("Alexandru Galea", Avatar.cleanName("Alexandru Galea"))
    }

    @Test
    fun `nothing, or only space, is no name`() {
        assertNull(Avatar.cleanName(null))
        assertNull(Avatar.cleanName(""))
        assertNull(Avatar.cleanName("   "))
        assertNull(Avatar.cleanName(" \t\n "))
        assertNull("a no-break space is still only space", Avatar.cleanName("   "))
    }

    @Test
    fun `the ends are trimmed and runs of space become one`() {
        assertEquals("Ana Maria Popescu", Avatar.cleanName("  Ana   Maria \t Popescu \n"))
        assertEquals("Ana Popescu", Avatar.cleanName("Ana  Popescu"))
    }

    @Test
    fun `a long name is cut to thirty characters`() {
        val long = "A".repeat(45)
        assertEquals(30, Avatar.cleanName(long)!!.length)
        assertEquals("A".repeat(30), Avatar.cleanName(long))
        assertEquals("B".repeat(30), Avatar.cleanName("B".repeat(30)))
        assertEquals(30, Avatar.MAX_NAME)
    }

    @Test
    fun `a cut never leaves a trailing space`() {
        // The 30th character is the space between the words.
        val name = "A".repeat(29) + " " + "B".repeat(10)
        assertEquals("A".repeat(29), Avatar.cleanName(name))
    }

    @Test
    fun `a cut never leaves half of an emoji`() {
        val face = "😀" // one character, two UTF-16 units
        val name = "A".repeat(29) + face
        val cleaned = Avatar.cleanName(name)!!
        assertEquals("A".repeat(29), cleaned)
        assertFalse(cleaned.any { Character.isHighSurrogate(it) })

        // Whole emoji that fit are kept.
        assertEquals("A".repeat(28) + face, Avatar.cleanName("A".repeat(28) + face))
    }

    @Test
    fun `cleaning a clean name changes nothing`() {
        for (raw in listOf("Ana", "Ana Popescu", "  x  ", "Élise  Ångström", "A".repeat(99))) {
            val once = Avatar.cleanName(raw)
            assertEquals(once, Avatar.cleanName(once))
        }
    }

    // ── initials ──────────────────────────────────────────────────────────────

    @Test
    fun `two words give the first letter of each`() {
        assertEquals("AG", Avatar.initials("Alexandru Galea"))
    }

    @Test
    fun `one word gives one letter`() {
        assertEquals("A", Avatar.initials("alex"))
    }

    @Test
    fun `three words give the first and the last`() {
        assertEquals("MW", Avatar.initials("Mary Jane Watson"))
        assertEquals("LB", Avatar.initials("Ludwig van Beethoven"))
    }

    @Test
    fun `initials are capitals whatever was typed`() {
        assertEquals("AG", Avatar.initials("alexandru galea"))
    }

    @Test
    fun `no name, no initials`() {
        assertEquals("", Avatar.initials(null))
        assertEquals("", Avatar.initials(""))
        assertEquals("", Avatar.initials("  "))
    }

    @Test
    fun `space around a name does not matter`() {
        assertEquals("AG", Avatar.initials("  alexandru    galea  "))
    }

    @Test
    fun `a hyphen or apostrophe inside a word is not its start`() {
        assertEquals("JP", Avatar.initials("Jean-Luc Picard"))
        assertEquals("OB", Avatar.initials("O'Connor Brien"))
    }

    @Test
    fun `accented letters keep their accents`() {
        assertEquals("ÉÅ", Avatar.initials("élise ångström"))
        // An accent written as a letter and a combining mark stays with its letter.
        assertEquals("É", Avatar.initials("élise"))
    }

    @Test
    fun `letters of other scripts are letters`() {
        assertEquals("АБ", Avatar.initials("алекс борис"))
        assertEquals("山", Avatar.initials("山田"))
    }

    @Test
    fun `a word with no letter in it is skipped, not shown`() {
        assertEquals("A", Avatar.initials("Alex -"))
        assertEquals("A", Avatar.initials("🏋 Alex"))
        assertEquals("", Avatar.initials("- -"))
    }

    @Test
    fun `a digit will do for a letter`() {
        assertEquals("7", Avatar.initials("7"))
    }

    // ── squareCrop ────────────────────────────────────────────────────────────

    @Test
    fun `a portrait photo is cut from the middle of its height`() {
        assertEquals(Square(0, 100, 600), Avatar.squareCrop(600, 800))
    }

    @Test
    fun `a landscape photo is cut from the middle of its width`() {
        assertEquals(Square(200, 0, 600), Avatar.squareCrop(1000, 600))
    }

    @Test
    fun `a square photo is taken whole`() {
        assertEquals(Square(0, 0, 500), Avatar.squareCrop(500, 500))
    }

    @Test
    fun `an odd margin rounds towards the top and the left`() {
        assertEquals(Square(0, 0, 3), Avatar.squareCrop(3, 4))
        assertEquals(Square(1, 0, 3), Avatar.squareCrop(6, 3))
    }

    @Test
    fun `the crop always fits inside the picture`() {
        for (w in listOf(1, 2, 319, 320, 321, 1080, 4000)) {
            for (h in listOf(1, 2, 319, 320, 321, 1920, 3000)) {
                val s = Avatar.squareCrop(w, h)
                assertTrue("$w x $h", s.left >= 0 && s.top >= 0 && s.size > 0)
                assertTrue("$w x $h", s.left + s.size <= w && s.top + s.size <= h)
                assertEquals("$w x $h", minOf(w, h), s.size)
            }
        }
    }

    @Test
    fun `an empty picture has no square`() {
        assertEquals(Square(0, 0, 0), Avatar.squareCrop(0, 100))
        assertEquals(Square(0, 0, 0), Avatar.squareCrop(100, -1))
    }

    // ── sampleSize ────────────────────────────────────────────────────────────

    @Test
    fun `a photo no bigger than the target is not shrunk while decoding`() {
        assertEquals(1, Avatar.sampleSize(200, 300))
        assertEquals(1, Avatar.sampleSize(320, 320))
    }

    @Test
    fun `the sample is the biggest power of two that leaves the short side at the target`() {
        // 639 / 2 = 319, below 320, so it has to stay whole; 640 / 2 is exactly 320.
        assertEquals(1, Avatar.sampleSize(639, 4000))
        assertEquals(2, Avatar.sampleSize(640, 4000))
        assertEquals(2, Avatar.sampleSize(1279, 4000))
        assertEquals(4, Avatar.sampleSize(1280, 4000))
    }

    @Test
    fun `a twelve megapixel photo is decoded at an eighth`() {
        // 3024 x 4032: 3024 / 8 = 378, still over 320; 3024 / 16 = 189 is not.
        assertEquals(8, Avatar.sampleSize(3024, 4032))
    }

    @Test
    fun `it is the short side that decides, in either orientation`() {
        assertEquals(Avatar.sampleSize(3024, 4032), Avatar.sampleSize(4032, 3024))
        // A panorama is thin, so it may not be shrunk at all.
        assertEquals(1, Avatar.sampleSize(12000, 500))
    }

    @Test
    fun `the sample is always a power of two and never takes the short side under the target`() {
        for (short in listOf(100, 320, 321, 500, 640, 641, 1080, 2160, 3024, 6000)) {
            val sample = Avatar.sampleSize(short, short * 2)
            assertEquals("$short", 0, sample and (sample - 1))
            assertTrue("$short", short / sample >= minOf(short, Avatar.SIZE_PX))
        }
    }

    @Test
    fun `a different target is respected`() {
        assertEquals(4, Avatar.sampleSize(1000, 1000, target = 200))
        assertEquals(8, Avatar.sampleSize(1000, 1000, target = 100))
    }

    @Test
    fun `a photo with no size is not shrunk`() {
        assertEquals(1, Avatar.sampleSize(0, 0))
    }

    // ── upright ───────────────────────────────────────────────────────────────

    @Test
    fun `an ordinary photo is left alone`() {
        assertEquals(Upright(0, false), Avatar.upright(1))
    }

    @Test
    fun `no tag, and a tag the standard does not define, leave the photo alone`() {
        for (tag in listOf(0, -1, 9, 99)) assertEquals("$tag", Upright(0, false), Avatar.upright(tag))
    }

    @Test
    fun `a portrait photo taken on a phone is turned a quarter`() {
        assertEquals(Upright(90, false), Avatar.upright(6))
        assertEquals(Upright(270, false), Avatar.upright(8))
        assertEquals(Upright(180, false), Avatar.upright(3))
    }

    @Test
    fun `the mirrored tags mirror after turning`() {
        assertEquals(Upright(0, true), Avatar.upright(2))
        assertEquals(Upright(180, true), Avatar.upright(4))
        assertEquals(Upright(90, true), Avatar.upright(5))
        assertEquals(Upright(270, true), Avatar.upright(7))
    }

    @Test
    fun `the eight tags are eight different orientations`() {
        assertEquals(8, (1..8).map { Avatar.upright(it) }.toSet().size)
    }

    /**
     * A 2 x 3 picture, marked at its top-left pixel, put through [Upright] the way a Matrix does
     * it: turn clockwise, then mirror. Where the mark ends up is the test of which tag is which.
     */
    private fun markAfter(tag: Int): Triple<Int, Int, Pair<Int, Int>> {
        val u = Avatar.upright(tag)
        var w = 2
        var h = 3
        var x = 0
        var y = 0
        repeat(u.degrees / 90) {
            // A clockwise quarter turn: the top-left pixel goes to the top-right.
            val nx = h - 1 - y
            val ny = x
            x = nx; y = ny
            val t = w; w = h; h = t
        }
        if (u.mirrored) x = w - 1 - x
        return Triple(w, h, x to y)
    }

    @Test
    fun `the tags put the marked corner where the standard says it belongs`() {
        // The standard names each tag by where the stored picture's first row and column sit.
        // Turned upright, the stored top-left pixel of a 2 x 3 picture must land here:
        //   1 top-left; 2 top-right; 3 bottom-right; 4 bottom-left;
        //   5 top-left of the transposed picture; 6 top-right of it; 7 bottom-right; 8 bottom-left.
        assertEquals(Triple(2, 3, 0 to 0), markAfter(1))
        assertEquals(Triple(2, 3, 1 to 0), markAfter(2))
        assertEquals(Triple(2, 3, 1 to 2), markAfter(3))
        assertEquals(Triple(2, 3, 0 to 2), markAfter(4))
        assertEquals(Triple(3, 2, 0 to 0), markAfter(5))
        assertEquals(Triple(3, 2, 2 to 0), markAfter(6))
        assertEquals(Triple(3, 2, 2 to 1), markAfter(7))
        assertEquals(Triple(3, 2, 0 to 1), markAfter(8))
    }
}
