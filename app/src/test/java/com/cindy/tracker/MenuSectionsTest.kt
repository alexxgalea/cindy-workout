package com.cindy.tracker

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The MENU page is grouped into named sections: Last session alone at the top, then Training,
 * You, Settings and Help. Read the way a person reads the screen: top to bottom, the section
 * titles and the rows between them.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MenuSectionsTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val sectionTitles = setOf("TRAINING", "YOU", "SETTINGS", "HELP")
    private val rowTitles = listOf(
        "Last session", "Workout", "Movements", "Progress", "Daily reminder", "Body weight",
        "Heart rate", "Strava", "Voice", "Music", "Help"
    )

    @Before
    fun reset() {
        RecordStore(context).clear()
        Profile(context).workout = Workouts.CINDY
    }

    private fun fileASession() {
        RecordStore(context).add(Attempt(rounds = 1, reps = 3, atMillis = 1_700_000_000_000L))
    }

    /** Section titles and row names in the order they appear on the screen. */
    private fun reading(workoutLive: Boolean = false): List<String> {
        val activity = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive)
        ).setup().get()
        val out = mutableListOf<String>()
        fun walk(v: View) {
            val description = v.contentDescription?.toString()
            if (v is TextView && v.text.toString() in sectionTitles) {
                out.add("section:${v.text}")
            } else if (v.isClickable && description != null) {
                rowTitles.firstOrNull { description == it || description.startsWith("$it, ") }
                    ?.let { out.add("row:$it") }
            }
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(activity.findViewById(android.R.id.content))
        return out
    }

    @Test
    fun `with a session filed, Last session leads, then Training, You, Settings and Help in order`() {
        fileASession()
        StravaConfig.availableForTest = true
        try {
            assertEquals(
                listOf(
                    "row:Last session",
                    "section:TRAINING", "row:Workout", "row:Movements", "row:Progress",
                    "section:YOU",
                    "section:SETTINGS", "row:Daily reminder", "row:Body weight", "row:Heart rate",
                    "row:Strava", "row:Voice", "row:Music",
                    "section:HELP", "row:Help"
                ),
                reading()
            )
        } finally {
            StravaConfig.availableForTest = null
        }
    }

    @Test
    fun `with no sessions, Training leads`() {
        assertEquals("section:TRAINING", reading().first())
        assertTrue(reading().none { it == "row:Last session" })
    }

    @Test
    fun `without Strava credentials, Settings closes up around the missing row`() {
        val texts = reading()
        assertTrue(texts.none { it == "row:Strava" })
        val settings = texts.indexOf("section:SETTINGS")
        assertEquals(
            listOf("row:Daily reminder", "row:Body weight", "row:Heart rate", "row:Voice", "row:Music"),
            texts.subList(settings + 1, texts.indexOf("section:HELP"))
        )
    }
}
