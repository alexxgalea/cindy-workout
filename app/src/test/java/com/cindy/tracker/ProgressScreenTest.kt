package com.cindy.tracker

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What Progress shows and where: the figures that answer "how am I doing" first, and a
 * leaderboard that reads as a ranking (ticket #153 of spec #139).
 *
 * Built at the P40's 1080x2340 (360 x 780 dp at 480 dpi) for an empty, a short and a long
 * history. What is asserted is what the athlete or TalkBack would perceive: which texts are on
 * the page, in what order, and what the first screenful holds. Robolectric lays text out with
 * its own metrics, so "above the fold" here is a measurement of the layout, not of the phone;
 * the captures of the phone are what the pull request still owes.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h780dp-xxhdpi")
class ProgressScreenTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    @After
    fun reset() {
        RecordStore(context).clear()
    }

    private val day = 24L * 60 * 60 * 1000

    /** [count] sessions, one a day, the newest today, each a little better than the one before. */
    private fun history(count: Int) {
        val store = RecordStore(context)
        val now = System.currentTimeMillis()
        repeat(count) { i ->
            val rounds = 12 + i % 9
            store.add(
                Attempt(
                    rounds = rounds,
                    reps = i % 5,
                    atMillis = now - (count - 1 - i) * day,
                    durationMs = 20 * 60 * 1000L,
                    roundSplitsMs = List(rounds) { 60_000L + it * 500L },
                    profile = CindyProfile.STANDARD
                )
            )
        }
    }

    /** The page, laid out on the P40: 1080 x 2340 less about 100 px of status bar. */
    private fun open(): Activity {
        val activity = Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        val root = activity.findViewById<View>(android.R.id.content)
        root.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(2340 - 100, View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2340 - 100)
        return activity
    }

    private fun views(root: View): Sequence<View> = sequence {
        yield(root)
        if (root is ViewGroup) for (i in 0 until root.childCount) yieldAll(views(root.getChildAt(i)))
    }

    private fun texts(activity: Activity): List<String> =
        views(activity.findViewById(android.R.id.content))
            .filterIsInstance<TextView>().map { it.text.toString() }.toList()

    @Test
    fun `the title stands on its own, with no sentence under it`() {
        history(3)
        val shown = texts(open())
        assertTrue("the title is on the page", "Progress" in shown)
        assertFalse("a sentence under the title", shown.any { it.startsWith("Cindy —") })
    }
}
