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

/**
 * The session page opens on the score and the time, and a short session collapses what it has
 * nothing to show for instead of printing dashes.
 *
 * Built at three sizes: one rep, one round, and a full session. The short ones are held to "no
 * placeholder grid": no dash in place of a figure, and none of the "no full round" or "no complete
 * rounds" lines that stood in for a section the session was too short to have. Like
 * [ScreenSmokeTest] this says what the athlete would be shown, not how the views are assembled.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SessionPageLeadsTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val day = 24 * 60 * 60 * 1000L

    @After
    fun clear() {
        RecordStore(context).clear()
    }

    private val timedRound = listOf(
        SetSplit(Exercise.PULLUP, 14_000L, 5, 0),
        SetSplit(Exercise.PUSHUP, 17_000L, 10, 0),
        SetSplit(Exercise.SQUAT, 21_000L, 15, 0)
    )

    /** One rep banked, eleven seconds on the clock and one paused: what a first try looks like. */
    private fun oneRep(at: Long = System.currentTimeMillis()) = Attempt(
        rounds = 0, reps = 1, atMillis = at, durationMs = 11_000L, pausedMs = 1_000L,
        countedReps = 1, profile = CindyProfile.STANDARD
    )

    /** One whole round, timed set by set, and nothing after it. */
    private fun oneRound(at: Long = System.currentTimeMillis()) = Attempt(
        rounds = 1, reps = 0, atMillis = at, durationMs = 3 * 60_000L,
        roundSplitsMs = listOf(52_000L), countedReps = 30, setSplits = timedRound,
        profile = CindyProfile.STANDARD
    )

    private fun fullSession(at: Long = System.currentTimeMillis()) = Attempt(
        rounds = 18, reps = 7, atMillis = at, durationMs = 20 * 60_000L,
        roundSplitsMs = List(18) { 55_000L + it * 1_200L }, countedReps = 547,
        profile = CindyProfile.STANDARD
    )

    private fun open(a: Attempt, reviewing: Boolean = false): ResultsActivity {
        RecordStore(context).apply { clear(); add(a) }
        return Robolectric.buildActivity(
            ResultsActivity::class.java,
            if (reviewing) ResultsActivity.review(context, a.atMillis)
            else ResultsActivity.intent(context, a, stoppedEarly = false)
        ).setup().get()
    }

    /** Every text on the page that the athlete could see: a hidden view says nothing. */
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

    private fun text(activity: android.app.Activity, id: Int) =
        activity.findViewById<TextView>(id).text.toString()

    private fun visibility(activity: android.app.Activity, id: Int) =
        activity.findViewById<View>(id).visibility

    private fun assertNoPlaceholders(page: List<String>) {
        assertTrue("a dash stands in for a figure: $page", page.none { it == "—" })
        assertTrue("says there is no full round: $page", page.none { it.contains("no full round") })
        assertTrue("says there are no complete rounds: $page", page.none { it.contains("No complete round") })
    }

    @Test
    fun `a one-rep session leads with its score and time and shows no placeholder grid`() {
        // The record does have an unfinished first round, so the track is hidden by the page and
        // not merely absent for want of sets.
        val unfinished = SessionStats.from(oneRep())?.rounds.orEmpty()
        assertTrue("no unfinished round to hide: $unfinished", unfinished.size == 1 && !unfinished[0].finished)

        val activity = open(oneRep())
        val page = shown(activity.findViewById(android.R.id.content))

        assertEquals("0", text(activity, R.id.score))
        assertEquals("+1", text(activity, R.id.scoreReps))
        assertEquals("0:11", text(activity, R.id.leadTime))
        assertEquals("plus 0:01 paused", text(activity, R.id.leadTimeNote))
        assertTrue(page.toString(), page.contains("1 rep · 5.5 reps/min"))

        assertNoPlaceholders(page)
        assertEquals(View.GONE, visibility(activity, R.id.tiles))
        assertEquals(View.GONE, visibility(activity, R.id.trackTitle))
        assertEquals(View.GONE, visibility(activity, R.id.track))
        assertEquals(View.GONE, visibility(activity, R.id.splitsTitle))
        assertEquals(View.GONE, visibility(activity, R.id.splitsCard))
        assertEquals(View.GONE, visibility(activity, R.id.splitsNote))
        assertEquals(View.GONE, visibility(activity, R.id.timelineTitle))
        activity.finish()
    }

    @Test
    fun `a one-round session keeps the round it finished and the figures that round gives`() {
        val activity = open(oneRound())
        val page = shown(activity.findViewById(android.R.id.content))

        assertEquals("1", text(activity, R.id.score))
        assertEquals("3:00", text(activity, R.id.leadTime))
        assertNoPlaceholders(page)
        assertEquals(View.VISIBLE, visibility(activity, R.id.tiles))
        assertTrue(page.toString(), page.containsAll(listOf("AVG", "FASTEST", "SLOWEST")))
        assertEquals(View.VISIBLE, visibility(activity, R.id.trackTitle))
        assertEquals(View.VISIBLE, visibility(activity, R.id.splitsCard))
        activity.finish()
    }

    @Test
    fun `a full session shows everything under its lead`() {
        val activity = open(fullSession())
        val page = shown(activity.findViewById(android.R.id.content))

        assertEquals("18", text(activity, R.id.score))
        assertEquals("+7", text(activity, R.id.scoreReps))
        assertEquals("20:00", text(activity, R.id.leadTime))
        assertEquals(View.GONE, visibility(activity, R.id.leadTimeNote))
        assertNoPlaceholders(page)
        assertTrue(page.toString(), page.containsAll(listOf("AVG", "FASTEST", "SLOWEST")))
        assertEquals(View.VISIBLE, visibility(activity, R.id.splitsCard))
        activity.finish()
    }

    @Test
    fun `the score and the time come before every other section`() {
        val activity = open(fullSession())
        val order = mutableListOf<Int>()
        fun walk(v: View) {
            if (v.id != View.NO_ID) order += v.id
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(activity.findViewById(android.R.id.content))

        val lead = listOf(R.id.score, R.id.leadTime).map(order::indexOf)
        val rest = listOf(R.id.celebration, R.id.tiles, R.id.splitsTitle, R.id.statsTitle).map(order::indexOf)
        assertTrue("a lead view is missing: $lead", lead.all { it >= 0 })
        assertTrue("the lead is not first: $lead before $rest", lead.max() < rest.min())
        activity.finish()
    }

    @Test
    fun `reopening a past session shows its date, its time and DISCARD`() {
        val at = System.currentTimeMillis() - 3 * day
        val activity = open(oneRep(at), reviewing = true)
        val page = shown(activity.findViewById(android.R.id.content))

        val headline = text(activity, R.id.headline)
        assertTrue("no date in $headline", Regex("""\d{4} · \d{1,2}:\d{2}""").containsMatchIn(headline))
        assertEquals("0:11", text(activity, R.id.leadTime))
        assertTrue(page.toString(), page.contains("DISCARD"))
        assertFalse("the session page closes from its top bar", page.contains("DONE"))
        activity.finish()
    }

    @Test
    fun `a session that has just ended shows its date and DISCARD too`() {
        val activity = open(oneRep())
        val page = shown(activity.findViewById(android.R.id.content))

        assertTrue(text(activity, R.id.headline), text(activity, R.id.headline).contains("·"))
        assertTrue(page.toString(), page.contains("DISCARD"))
        activity.finish()
    }
}
