package com.cindy.tracker

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Workouts: the catalog with the chosen one checked, a tap saved at once, and the menu's Workout
 * row that opens it and names the choice. Asserted as an athlete or TalkBack would perceive it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WorkoutsScreenTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    fun reset() {
        Profile(context).workout = Workouts.CINDY
        FirstRun(context).workoutsSeen = emptySet()
    }

    private fun open(): ComponentActivity =
        Robolectric.buildActivity(WorkoutsActivity::class.java).setup().get()

    private fun content(activity: ComponentActivity): View = activity.findViewById(android.R.id.content)

    private fun findByPrefix(root: View, prefix: String): View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) findByPrefix(root.getChildAt(i), prefix)?.let { return it }
        }
        return null
    }

    private fun textsIn(root: View): List<String> = buildList {
        if (root is TextView) add(root.text.toString())
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(textsIn(root.getChildAt(i)))
    }

    @Test
    fun `every workout in the catalog has a row with its name, format and line`() {
        val activity = open()
        for (workout in Workouts.catalog) {
            val row = findByPrefix(content(activity), workout.name)
            assertNotNull("no row for ${workout.name}", row)
            assertEquals(
                "${workout.name}, ${WorkoutsActivity.detail(workout)}",
                row!!.contentDescription.toString()
            )
        }
        assertTrue(textsIn(content(activity)).contains("20-minute AMRAP · " + Workouts.CINDY.description))
    }

    @Test
    fun `a tap is saved at once, with no SAVE to press`() {
        val activity = open()
        findByPrefix(content(activity), Workouts.CINDY.name)!!.performClick()
        assertEquals(Workouts.CINDY, Profile(context).workout)
        val texts = textsIn(content(activity))
        assertTrue(texts.none { it == "SAVE" || it == "CANCEL" })
    }

    @Test
    fun `opening the page is seeing the whole catalog`() {
        open()
        assertEquals(Workouts.catalog.map { it.id }.toSet(), FirstRun(context).workoutsSeen)
    }

    @Test
    fun `the menu's Workout row names the choice and opens the page`() {
        val menu = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        val row = findByPrefix(menu.findViewById(android.R.id.content), "Workout,")
        assertEquals("Workout, Cindy", row?.contentDescription?.toString())

        row!!.performClick()

        val started = shadowOf(menu).nextStartedActivity
        assertEquals(WorkoutsActivity::class.java.name, started?.component?.className)
    }

    @Test
    fun `a live workout refuses the row`() {
        val menu = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = true)
        ).setup().get()

        findByPrefix(menu.findViewById(android.R.id.content), "Workout,")!!.performClick()

        assertNull(shadowOf(menu).nextStartedActivity)
    }
}
