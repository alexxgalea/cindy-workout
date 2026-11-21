package com.cindy.tracker

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** STOP opens the session page with whatever it can show today for a Freestyle: it opens, and shows what it can. */
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

    @Test
    fun `a filed Freestyle opens its session page with its time and reps`() {
        val filed = Attempt(
            rounds = 0, reps = 0, atMillis = System.currentTimeMillis(), durationMs = 95_000L,
            countedReps = 12, workoutId = Workouts.FREESTYLE_ID,
            movementTotals = mapOf(Exercise.PUSHUP to 5, Exercise.SQUAT to 7)
        )
        RecordStore(context).apply { clear(); add(filed) }
        val page = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.intent(context, filed, stoppedEarly = true)
        ).setup().get()
        val text = shown(page.window.decorView)
        // Cindy's tiles still stand in for the rest until the session page ticket gives Freestyle its own.
        assertTrue("no time: $text", text.contains("1:35"))
        assertTrue("no reps: $text", text.any { it.startsWith("12 reps") })
    }
}
