package com.cindy.tracker

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
 * Movements: a choice is saved the moment it is tapped, and the page is left from the top bar or
 * with back (spec #139, ticket #152).
 *
 * What is asserted is what an athlete or TalkBack would perceive: which row carries the check
 * after a tap, whether the choice is there when the page is left and opened again, and that no
 * SAVE or CANCEL is offered. The page's own layout is not asserted.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MovementsScreenTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    fun reset() {
        Profile(context).apply {
            movements = CindyProfile.STANDARD
            smartSquats = false
        }
    }

    private fun open(): ComponentActivity =
        Robolectric.buildActivity(MovementsActivity::class.java).setup().get()

    private fun content(activity: ComponentActivity): View = activity.findViewById(android.R.id.content)

    private fun findByDescription(root: View, description: String): View? {
        if (root.contentDescription?.toString() == description) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescription(root.getChildAt(i), description)?.let { return it }
            }
        }
        return null
    }

    private fun textsIn(root: View): List<String> = buildList {
        if (root is TextView) add(root.text.toString())
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(textsIn(root.getChildAt(i)))
    }

    /** The row for [label], which must exist. */
    private fun row(activity: ComponentActivity, label: String): View {
        val found = findByDescription(content(activity), label)
        assertNotNull("no row says $label", found)
        return found!!
    }

    /** Whether [row] shows its check: the tick is the only ImageView in it and is hidden, not gone. */
    private fun isChecked(row: View): Boolean {
        fun tick(v: View): View? {
            if (v is android.widget.ImageView) return v
            if (v is ViewGroup) for (i in 0 until v.childCount) tick(v.getChildAt(i))?.let { return it }
            return null
        }
        return tick(row)!!.visibility == View.VISIBLE
    }

    @Test
    fun `it opens with the current choices checked`() {
        Profile(context).movements = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        val activity = open()

        assertTrue(isChecked(row(activity, "Strict pull-up")))
        assertTrue(isChecked(row(activity, "From knees")))
        assertFalse(isChecked(row(activity, "Standard")))
        assertTrue(isChecked(row(activity, "Air squat")))
    }

    @Test
    fun `tapping a variation checks it and saves it with no SAVE pressed`() {
        val activity = open()

        row(activity, "From knees").performClick()

        assertTrue("the tapped row takes the check", isChecked(row(activity, "From knees")))
        assertFalse("the one it replaces loses it", isChecked(row(activity, "Standard")))
        assertEquals(PushVariant.KNEE_PUSH_UP, Profile(context).movements.push)
    }

    @Test
    fun `the page offers neither SAVE nor CANCEL`() {
        val texts = textsIn(content(open()))

        assertFalse(texts.toString(), texts.contains("SAVE"))
        assertFalse(texts.toString(), texts.contains("CANCEL"))
    }

    @Test
    fun `a variation other than the standard three still saves the workout as an Adaptive Cindy`() {
        val activity = open()

        row(activity, "Band-assisted").performClick()

        val saved = Profile(context).movements
        assertEquals(PullVariant.BAND_ASSISTED_PULL_UP, saved.pull)
        assertEquals(CindyMode.ADAPTIVE, saved.mode)
        assertEquals("Adaptive Cindy · band-assisted pull-ups", saved.label())
    }

    @Test
    fun `tapping the standard choice back returns to the standard Cindy`() {
        val activity = open()
        row(activity, "From knees").performClick()

        row(activity, "Standard").performClick()

        assertEquals(CindyProfile.STANDARD, Profile(context).movements)
    }

    @Test
    fun `choices from different movements add up`() {
        val activity = open()

        row(activity, "From knees").performClick()
        row(activity, "Negatives, you tap plus one").performClick()

        val saved = Profile(context).movements
        assertEquals(PullVariant.NEGATIVE_PULL_UP, saved.pull)
        assertEquals(PushVariant.KNEE_PUSH_UP, saved.push)
    }

    @Test
    fun `leaving by back keeps the choices made`() {
        val activity = open()
        row(activity, "From knees").performClick()

        activity.onBackPressedDispatcher.onBackPressed()

        assertTrue(activity.isFinishing)
        assertEquals(PushVariant.KNEE_PUSH_UP, Profile(context).movements.push)
        assertTrue("and the page shows it when opened again", isChecked(row(open(), "From knees")))
    }

    @Test
    fun `leaving from the top bar keeps the choices made`() {
        val activity = open()
        row(activity, "From knees").performClick()

        findByDescription(content(activity), "Back")!!.performClick()

        assertTrue(activity.isFinishing)
        assertEquals(PushVariant.KNEE_PUSH_UP, Profile(context).movements.push)
    }

    @Test
    fun `the heels-flat setting is saved the moment it is switched`() {
        val activity = open()
        assertEquals("Spot heels-flat squats, off", row(activity, "Spot heels-flat squats, off").contentDescription)

        row(activity, "Spot heels-flat squats, off").performClick()

        assertTrue(Profile(context).smartSquats)
        assertNotNull("it now says on", findByDescription(content(activity), "Spot heels-flat squats, on"))
    }

    @Test
    fun `the menu's Movements row opens the page`() {
        val menu = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        val movements = findByPrefix(menu.findViewById(android.R.id.content), "Movements")
        assertNotNull(movements)

        movements!!.performClick()

        val started = shadowOf(menu).nextStartedActivity
        assertEquals(MovementsActivity::class.java.name, started?.component?.className)
    }

    @Test
    fun `the menu says what was chosen when it comes back`() {
        val menuController = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup()
        val menu = menuController.get()
        assertEquals("Movements, Cindy", findByPrefix(menu.findViewById(android.R.id.content), "Movements")!!.contentDescription)

        menuController.pause().stop()
        Profile(context).movements = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        menuController.restart().start().resume()

        assertEquals(
            "Movements, Adaptive Cindy · knee push-ups",
            findByPrefix(menu.findViewById(android.R.id.content), "Movements")!!.contentDescription
        )
    }

    @Test
    fun `a live workout still refuses the row`() {
        val menu = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = true)
        ).setup().get()

        findByPrefix(menu.findViewById(android.R.id.content), "Movements")!!.performClick()

        assertNull(shadowOf(menu).nextStartedActivity)
    }

    private fun findByPrefix(root: View, prefix: String): View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) findByPrefix(root.getChildAt(i), prefix)?.let { return it }
        }
        return null
    }
}
