package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EquivalentsTest {

    private val everything: (String) -> Boolean = { true }

    @Test
    fun `the table is ordered heaviest first`() {
        assertEquals(Equivalents.animals.sortedByDescending { it.kg }, Equivalents.animals)
        assertEquals(10, Equivalents.animals.size)
    }

    @Test
    fun `the count is always between one and twelve, and preferably two to nine`() {
        var kg = 80.0
        while (kg < 90_000.0) {
            for (rotation in 0L..9L) {
                val match = Equivalents.animalFor(kg, rotation, everything) ?: continue
                assertTrue("$kg kg: ${match.count}", match.count in 1.0..12.0)
            }
            // Wherever any animal gives a count in [2, 9], that is the one picked.
            val preferredExists = Equivalents.animals.any { kg / it.kg in 2.0..9.0 }
            if (preferredExists) {
                for (rotation in 0L..9L) {
                    val match = Equivalents.animalFor(kg, rotation, everything)!!
                    assertTrue("$kg kg: ${match.count}", match.count in 2.0..9.0)
                }
            }
            kg *= 1.07
        }
    }

    @Test
    fun `under one panda or over twelve T rexes there is no animal`() {
        assertNull(Equivalents.animalFor(99.0, 0L, everything))
        assertNull(Equivalents.animalFor(8000.0 * 12.5, 0L, everything))
        assertNull(Equivalents.animalFor(0.0, 0L, everything))
    }

    @Test
    fun `consecutive days meet different animals`() {
        // 12,940 kg: T. rex 1.6 and giraffe 10.8 fit but are not preferred; the elephant 2.2, rhino
        // 5.6 and hippo 8.6 are, and rotation walks through those.
        val seen = (0L..2L).map { Equivalents.animalFor(12_940.0, 19_000L + it, everything)!!.animal.name }

        assertEquals(setOf("African elephant", "white rhino", "hippo"), seen.toSet())
    }

    @Test
    fun `the same day always gives the same animal`() {
        val a = Equivalents.animalFor(12_940.0, 19_000L, everything)
        val b = Equivalents.animalFor(12_940.0, 19_000L, everything)
        assertEquals(a, b)
    }

    @Test
    fun `negative rotations are fine`() {
        assertNotNull(Equivalents.animalFor(12_940.0, -3L, everything))
    }

    @Test
    fun `an animal the phone cannot draw is never picked`() {
        val noHippo: (String) -> Boolean = { it != "🦛" }
        for (rotation in 0L..20L) {
            val match = Equivalents.animalFor(13_500.0, rotation, noHippo)!!
            assertNotEquals("hippo", match.animal.name)
        }
    }

    @Test
    fun `when only an unpreferred animal can be drawn it is still used`() {
        // 1,600 kg: the hippo (1.1) and the giraffe (1.3) are the only fits and neither is in
        // [2, 9]; the cow is 2.3 but the phone cannot draw it.
        val onlyHippo: (String) -> Boolean = { it == "🦛" }
        val match = Equivalents.animalFor(1_600.0, 0L, onlyHippo)!!

        assertEquals("hippo", match.animal.name)
        assertEquals("1.1 hippos", match.text)
    }

    @Test
    fun `when nothing can be drawn there is no animal`() {
        assertNull(Equivalents.animalFor(12_940.0, 0L) { false })
        assertNull(Equivalents.energyFor(312.0, 0L) { false })
    }

    @Test
    fun `counts read with one decimal below three and whole from three up`() {
        val hippo = Equivalents.animals.first { it.name == "hippo" }
        assertEquals("1.4 hippos", Equivalents.countText(1.4, hippo))
        assertEquals("2.5 hippos", Equivalents.countText(2.54, hippo))
        assertEquals("9 hippos", Equivalents.countText(8.6, hippo))
        assertEquals("3 hippos", Equivalents.countText(3.0, hippo))
        assertEquals("12 hippos", Equivalents.countText(11.5, hippo))
    }

    @Test
    fun `rounding never produces a decimal three or a plural one`() {
        val hippo = Equivalents.animals.first { it.name == "hippo" }
        assertEquals("3 hippos", Equivalents.countText(2.97, hippo))
        assertEquals("1 hippo", Equivalents.countText(1.02, hippo))
    }

    @Test
    fun `the sentence says at least for a lower bound`() {
        val match = Equivalents.animalFor(12_940.0, 0L, everything)!!
        assertEquals("As heavy as ${match.text}.", Equivalents.heavySentence(match, atLeast = false))
        assertEquals("At least as heavy as ${match.text}.", Equivalents.heavySentence(match, atLeast = true))
    }

    @Test
    fun `no more than five emoji are drawn`() {
        assertEquals(1, Equivalents.emojiCount(1.2))
        assertEquals(2, Equivalents.emojiCount(2.4))
        assertEquals(3, Equivalents.emojiCount(2.6))
        assertEquals(5, Equivalents.emojiCount(5.2))
        assertEquals(5, Equivalents.emojiCount(9.0))
    }

    @Test
    fun `energy counts are whole numbers from one to sixty`() {
        var kcal = 1.0
        while (kcal < 2_000.0) {
            for (rotation in 0L..5L) {
                val match = Equivalents.energyFor(kcal, rotation, everything) ?: continue
                assertTrue("$kcal kcal: ${match.count}", match.count in 1..60)
            }
            kcal *= 1.1
        }
        assertNull(Equivalents.energyFor(3.0, 0L, everything))
        assertNull(Equivalents.energyFor(0.0, 0L, everything))
    }

    @Test
    fun `energy is compared with tea, a phone and a lamp, never with food`() {
        val names = Equivalents.energyReferences.map { it.emoji }
        assertEquals(listOf("☕", "🔋", "💡"), names)
        assertEquals(20.0, Equivalents.energyReferences[0].kcal, 0.0)
        assertEquals(13.0, Equivalents.energyReferences[1].kcal, 0.0)
        assertEquals(7.7, Equivalents.energyReferences[2].kcal, 0.0)
    }

    @Test
    fun `the tea sentence reads as the card promises`() {
        val tea = Equivalents.energyFor(312.0, 0L) { it == "☕" }!!
        assertEquals(16, tea.count)
        assertEquals(
            "Enough to boil water for 16 cups of tea.", tea.reference.sentence(tea.count, atLeast = false)
        )
        assertEquals(
            "At least enough to boil water for 16 cups of tea.",
            tea.reference.sentence(tea.count, atLeast = true)
        )
    }

    @Test
    fun `energy sentences handle one`() {
        val tea = Equivalents.energyReferences[0]
        val phone = Equivalents.energyReferences[1]
        val bulb = Equivalents.energyReferences[2]
        assertEquals("Enough to boil water for 1 cup of tea.", tea.sentence(1, false))
        assertEquals("Enough to charge a phone fully once.", phone.sentence(1, false))
        assertEquals("Enough to charge a phone fully 24 times.", phone.sentence(24, false))
        assertEquals("Enough to run a 9 W LED bulb for 41 hours.", bulb.sentence(41, false))
        assertEquals("Enough to run a 9 W LED bulb for 1 hour.", bulb.sentence(1, false))
    }

    @Test
    fun `energy rotates among the references that fit`() {
        val seen = (0L..2L).map { Equivalents.energyFor(312.0, it, everything)!!.reference.emoji }
        assertEquals(3, seen.distinct().size)
    }

    @Test
    fun `an energy reference the phone cannot draw is skipped`() {
        for (rotation in 0L..5L) {
            val match = Equivalents.energyFor(312.0, rotation) { it != "🔋" }!!
            assertNotEquals("🔋", match.reference.emoji)
        }
    }
}
