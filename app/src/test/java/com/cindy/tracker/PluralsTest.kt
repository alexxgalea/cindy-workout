package com.cindy.tracker

import com.cindy.tracker.Plural.FEW
import com.cindy.tracker.Plural.MANY
import com.cindy.tracker.Plural.ONE
import com.cindy.tracker.Plural.OTHER
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The plural rules, checked against the Unicode CLDR tables at the counts where languages change
 * their mind: 0, 1, 2, 4, 5, the teens, and the same run again after each hundred and each ten.
 */
class PluralsTest {

    private fun check(rule: (Int) -> Plural, expected: Map<Int, Plural>) {
        expected.forEach { (n, form) -> assertEquals("for $n", form, rule(n)) }
    }

    @Test
    fun `one or other`() = check(
        Plurals::oneOther,
        mapOf(0 to OTHER, 1 to ONE, 2 to OTHER, 5 to OTHER, 11 to OTHER, 21 to OTHER, 101 to OTHER)
    )

    @Test
    fun `nought and one are both singular in French and Portuguese`() = check(
        Plurals::zeroOrOne,
        mapOf(0 to ONE, 1 to ONE, 2 to OTHER, 5 to OTHER, 21 to OTHER, 101 to OTHER)
    )

    @Test
    fun `Polish`() = check(
        Plurals::polish,
        mapOf(
            0 to MANY, 1 to ONE, 2 to FEW, 3 to FEW, 4 to FEW, 5 to MANY,
            11 to MANY, 12 to MANY, 13 to MANY, 14 to MANY, 15 to MANY, 19 to MANY,
            20 to MANY, 21 to MANY, 22 to FEW, 23 to FEW, 24 to FEW, 25 to MANY,
            100 to MANY, 101 to MANY, 102 to FEW, 111 to MANY, 112 to MANY, 121 to MANY,
            122 to FEW
        )
    )

    @Test
    fun `Romanian`() = check(
        Plurals::romanian,
        mapOf(
            0 to FEW, 1 to ONE, 2 to FEW, 3 to FEW, 12 to FEW, 19 to FEW,
            20 to OTHER, 21 to OTHER, 22 to OTHER, 25 to OTHER, 100 to OTHER,
            101 to FEW, 102 to FEW, 111 to FEW, 119 to FEW, 120 to OTHER, 121 to OTHER
        )
    )

    @Test
    fun `Russian`() = check(
        Plurals::russian,
        mapOf(
            0 to MANY, 1 to ONE, 2 to FEW, 3 to FEW, 4 to FEW, 5 to MANY,
            11 to MANY, 12 to MANY, 13 to MANY, 14 to MANY, 15 to MANY, 19 to MANY,
            20 to MANY, 21 to ONE, 22 to FEW, 23 to FEW, 24 to FEW, 25 to MANY,
            100 to MANY, 101 to ONE, 102 to FEW, 111 to MANY, 112 to MANY, 121 to ONE,
            122 to FEW
        )
    )

    @Test
    fun `every count up to a thousand has a form in every rule`() {
        // Total functions: no count falls through, and the rules that never produce OTHER for a
        // whole number really never do.
        (0..1000).forEach { n ->
            listOf(Plurals::oneOther, Plurals::zeroOrOne, Plurals::polish, Plurals::romanian, Plurals::russian)
                .forEach { rule -> rule(n) }
            assertTrue("Polish has no 'other' for whole numbers ($n)", Plurals.polish(n) != OTHER)
            assertTrue("Russian has no 'other' for whole numbers ($n)", Plurals.russian(n) != OTHER)
        }
    }
}
