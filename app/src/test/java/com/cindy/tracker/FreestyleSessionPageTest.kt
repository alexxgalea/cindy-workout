package com.cindy.tracker

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** A Freestyle's session page: its lead, its tiles, its sets and the gaps between them (spec #188). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FreestyleSessionPageTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @After
    fun clear() {
        RecordStore(context).clear()
    }

    private fun shown(root: View): List<String> {
        val out = mutableListOf<String>()
        fun walk(v: View) {
            if (v.visibility != View.VISIBLE) return
            if (v is TextView && v.text.isNotEmpty()) out += v.text.toString()
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(root)
        return out
    }

    private val sets = listOf(
        FreestyleSet(Exercise.SQUAT, 7, 10_000L, 40_000L),
        FreestyleSet(Exercise.SQUAT, 5, 66_000L, 80_000L),
        FreestyleSet(Exercise.PUSHUP, 4, 95_000L, 100_000L)
    )

    private fun filed() = Attempt(
        rounds = 0, reps = 0, atMillis = System.currentTimeMillis(), durationMs = 125_000L,
        countedReps = 16, workoutId = Workouts.FREESTYLE_ID,
        movementTotals = mapOf(Exercise.PUSHUP to 4, Exercise.SQUAT to 12), freestyleSets = sets
    ).also { attempt -> RecordStore(context).apply { clear(); add(attempt) } }

    private fun stopped(a: Attempt) = Robolectric.buildActivity(
        ResultsActivity::class.java, ResultsActivity.intent(context, a, stoppedEarly = true)
    ).setup().get()

    @Test
    fun `a Freestyle page leads with the date and Count up, the total reps and the time`() {
        val text = shown(stopped(filed()).window.decorView)
        assertTrue("no Count up: $text", text.any { it.startsWith("STOPPED · ") && it.endsWith("· Count up") })
        assertTrue("no total: $text", text.contains("16"))
        assertTrue("no reps line: $text", text.any { it.startsWith("16 reps") })
        assertTrue("no time: $text", text.contains("2:05"))
    }

    @Test
    fun `it shows one tile per movement and then every set with its Rest or Transition`() {
        val text = shown(stopped(filed()).window.decorView)
        for (want in listOf(
            "PUSH-UPS", "4", "0:05 in sets · 1 set",
            "SQUATS", "12", "0:44 in sets · 2 sets",
            "7 reps · 0:10–0:40", "0:30", "Rest", "0:26", "5 reps · 1:06–1:20", "0:14",
            "Transition", "0:15", "4 reps · 1:35–1:40", "0:05",
            FreestylePage.FOOTNOTE
        )) assertTrue("missing $want: $text", text.any { it.contains(want) })
        val order = listOf("SQUATS · 7 reps · 0:10–0:40", "Rest", "SQUATS · 5 reps · 1:06–1:20", "Transition", "PUSH-UPS · 4 reps · 1:35–1:40")
            .map { want -> text.indexOfFirst { it == want } }
        assertTrue("set list out of order: $order", order.all { it >= 0 })
        assertEquals(order.sorted(), order)
    }

    @Test
    fun `it says nothing of Cindy, rounds, levels or a first Cindy`() {
        val text = shown(stopped(filed()).window.decorView).joinToString("\n")
        for (not in listOf("Cindy", "round", "Movements this version", "rung", "Legend")) {
            assertFalse("$not on a Freestyle page: $text", text.contains(not))
        }
    }

    @Test
    fun `the sets survive reopening the page from the board`() {
        val a = filed()
        val page = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.review(context, a.atMillis)
        ).setup().get()
        val text = shown(page.window.decorView)
        assertTrue("no set: $text", text.contains("SQUATS · 7 reps · 0:10–0:40"))
        assertTrue("no tile: $text", text.contains("0:44 in sets · 2 sets"))
    }

    @Test
    fun `DISCARD takes the sets with the attempt`() {
        val a = filed()
        SessionDiscard.discard(context, a.atMillis)
        assertEquals(emptyList<Attempt>(), RecordStore(context).all())
    }
}
