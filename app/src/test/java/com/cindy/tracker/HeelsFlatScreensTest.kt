package com.cindy.tracker

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

/**
 * The screens behind heels-flat squats: the setting that lets a session switch itself, and the
 * results row that says it did.
 *
 * The counting is tested without a view in [HeelsFlatSquatTest] and [SmartSquatTest]. What is
 * tested here is the part an athlete meets: a setting that is off until they turn it on, that is
 * kept the moment they do, that the menu reports honestly, and a results screen that says
 * why a standard Cindy came back as an Adaptive one and offers to make it permanent.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HeelsFlatScreensTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun findByDescriptionPrefix(root: View, prefix: String): View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescriptionPrefix(root.getChildAt(i), prefix)?.let { return it }
            }
        }
        return null
    }

    private fun findByText(root: View, text: String): View? {
        if (root is TextView && root.text.toString() == text) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findByText(root.getChildAt(i), text)?.let { return it }
            }
        }
        return null
    }

    private fun openMenu(): android.app.Activity =
        Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()

    private fun content(activity: android.app.Activity): View =
        activity.findViewById(android.R.id.content)

    /** The Movements page, opened from the menu's row. */
    private fun openMovementsPage(): android.app.Activity {
        val menu = openMenu()
        val row = findByDescriptionPrefix(content(menu), "Movements")
        assertNotNull("no Movements row", row)
        row!!.performClick()
        val started = org.robolectric.Shadows.shadowOf(menu).nextStartedActivity
        assertEquals(MovementsActivity::class.java.name, started?.component?.className)
        return Robolectric.buildActivity(MovementsActivity::class.java).setup().get()
    }

    private fun movementsRow(activity: android.app.Activity): String =
        findByDescriptionPrefix(content(activity), "Movements")!!.contentDescription.toString()

    private fun reset() {
        Profile(context).apply {
            smartSquats = false
            movements = CindyProfile.STANDARD
        }
    }

    // ── the setting ───────────────────────────────────────────────────────────

    @Test
    fun `smart squats are off on a fresh install`() {
        reset()
        assertFalse(Profile(context).smartSquats)
    }

    @Test
    fun `the Movements page offers the setting, off`() {
        reset()
        val page = openMovementsPage()
        val toggle = findByDescriptionPrefix(content(page), "Spot heels-flat squats")
        assertNotNull("the page has no setting", toggle)
        assertEquals("Spot heels-flat squats, off", toggle!!.contentDescription.toString())
    }

    @Test
    fun `switching it on keeps it at once, and the Movements row says so`() {
        reset()
        val page = openMovementsPage()

        findByDescriptionPrefix(content(page), "Spot heels-flat squats")!!.performClick()
        assertEquals(
            "the switch moves",
            "Spot heels-flat squats, on",
            findByDescriptionPrefix(content(page), "Spot heels-flat squats")!!.contentDescription.toString()
        )
        assertTrue("and nothing waits for a SAVE", Profile(context).smartSquats)
        assertNull("there is none to press", findByText(content(page), "SAVE"))

        assertEquals("Movements, Cindy · spots heels flat", movementsRow(openMenu()))
        reset()
    }

    @Test
    fun `the Movements row says it spots heels flat only where that can happen`() {
        reset()
        Profile(context).smartSquats = true
        assertEquals("Movements, Cindy · spots heels flat", movementsRow(openMenu()))

        // A box squat has a depth of its own, so the setting does nothing there and is not claimed.
        Profile(context).movements = CindyProfile(squat = SquatVariant.BOX_SQUAT)
        assertEquals("Movements, Adaptive Cindy · box squats", movementsRow(openMenu()))

        Profile(context).smartSquats = false
        Profile(context).movements = CindyProfile.STANDARD
        assertEquals("Movements, Cindy", movementsRow(openMenu()))
        reset()
    }

    // ── the results screen ────────────────────────────────────────────────────

    private val heelsFlat = CindyProfile(squat = SquatVariant.HEELS_FLAT)

    private fun attempt() = Attempt(
        rounds = 9,
        reps = 4,
        atMillis = System.currentTimeMillis(),
        durationMs = 20 * 60 * 1000L,
        profile = heelsFlat
    )

    private fun openResults(spotted: Boolean): android.app.Activity {
        val a = attempt()
        return Robolectric.buildActivity(
            ResultsActivity::class.java,
            ResultsActivity.intent(context, a, stoppedEarly = false, heelsFlatSpotted = spotted)
        ).setup().get()
    }

    @Test
    fun `the results screen explains an automatic switch`() {
        reset()
        val activity = openResults(spotted = true)

        assertNotNull("no row says why", findByDescriptionPrefix(content(activity), "Squats"))
        assertEquals("Adaptive Cindy", activity.findViewById<TextView>(R.id.levelTitle).text.toString())
        assertEquals("heels-flat squats", activity.findViewById<TextView>(R.id.levelBlurb).text.toString())
        activity.finish()
    }

    @Test
    fun `the results screen says nothing about it when the choice was the athlete's own`() {
        reset()
        val activity = openResults(spotted = false)

        assertNull("there is nothing to explain", findByDescriptionPrefix(content(activity), "Squats"))
        activity.finish()
    }

    @Test
    fun `the row opens a sheet, and SET HEELS FLAT makes the choice permanent`() {
        reset()
        val activity = openResults(spotted = true)

        findByDescriptionPrefix(content(activity), "Squats")!!.performClick()
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        val root = dialog.window!!.decorView
        assertNotNull(findByText(root, "Adaptive Cindy activated"))

        findByText(root, "SET HEELS FLAT")!!.performClick()

        assertEquals(SquatVariant.HEELS_FLAT, Profile(context).movements.squat)
        activity.finish()
        reset()
    }

    @Test
    fun `NOT NOW leaves the choice as it was`() {
        reset()
        val activity = openResults(spotted = true)

        findByDescriptionPrefix(content(activity), "Squats")!!.performClick()
        findByText(ShadowDialog.getLatestDialog().window!!.decorView, "NOT NOW")!!.performClick()

        assertEquals(SquatVariant.AIR_SQUAT, Profile(context).movements.squat)
        activity.finish()
    }
}
