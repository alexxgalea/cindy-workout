package com.cindy.tracker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog
import org.robolectric.shadows.ShadowToast

/**
 * The first-launch pages: that they build on every page, that they lead where they should, and
 * that the two flags move only when the pages end.
 *
 * Whether to show them at all is [OnboardingTest]; the camera screen's half of the flow cannot be
 * built here, because it binds CameraX. What is tested is the part the athlete reads and taps.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TutorialScreenTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    @After
    fun reset() {
        context.getSharedPreferences("cindy", Context.MODE_PRIVATE).edit().clear().commit()
    }

    // ── finding things ────────────────────────────────────────────────────────

    private fun findByText(root: View, text: String): View? {
        if (root is TextView && root.text.toString() == text) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) findByText(root.getChildAt(i), text)?.let { return it }
        }
        return null
    }

    private fun findByDescription(root: View, description: String): View? {
        if (root.contentDescription?.toString() == description) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescription(root.getChildAt(i), description)?.let { return it }
            }
        }
        return null
    }

    private fun findByDescriptionPrefix(root: View, prefix: String): View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescriptionPrefix(root.getChildAt(i), prefix)?.let { return it }
            }
        }
        return null
    }

    private fun texts(root: View): List<String> = buildList {
        if (root is TextView) add(root.text.toString())
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(texts(root.getChildAt(i)))
    }

    private fun contains(root: View, part: String): Boolean = texts(root).any { it.contains(part) }

    private fun hasViewOfType(root: View, type: Class<*>): Boolean {
        if (type.isInstance(root)) return true
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) if (hasViewOfType(root.getChildAt(i), type)) return true
        }
        return false
    }

    private fun content(activity: Activity): View = activity.findViewById(android.R.id.content)

    private fun open(replay: Boolean = false): TutorialActivity = Robolectric.buildActivity(
        TutorialActivity::class.java, TutorialActivity.intent(context, replay)
    ).setup().get()

    private fun press(activity: Activity, label: String) {
        val button = findByText(content(activity), label)
        assertNotNull("no $label button", button)
        button!!.performClick()
    }

    /** Presses NEXT until the page the pages end on. */
    private fun toLastPage(activity: Activity) =
        repeat(TutorialActivity.PAGE_COUNT - 1) { press(activity, "NEXT") }

    private fun swipe(activity: Activity, fromX: Float, fromY: Float, toX: Float, toY: Float) {
        val down = SystemClock.uptimeMillis()
        activity.dispatchTouchEvent(
            MotionEvent.obtain(down, down, MotionEvent.ACTION_DOWN, fromX, fromY, 0)
        )
        activity.dispatchTouchEvent(
            MotionEvent.obtain(down, down + 80, MotionEvent.ACTION_UP, toX, toY, 0)
        )
    }

    // ── the pages ─────────────────────────────────────────────────────────────

    @Test
    fun `the first page welcomes, with no way back and the way on`() {
        val activity = open()
        val root = content(activity)

        assertNotNull(findByText(root, "Cindy, counted for you"))
        assertEquals(View.GONE, findByText(root, "BACK")!!.visibility)
        assertNotNull(findByText(root, "NEXT"))
        assertNotNull(findByDescription(root, "Page 1 of 5"))
        activity.finish()
    }

    @Test
    fun `each page builds and lays out at phone size`() {
        val controller = Robolectric.buildActivity(
            TutorialActivity::class.java, TutorialActivity.intent(context, replay = false)
        )
        val activity = controller.setup().get()
        repeat(TutorialActivity.PAGE_COUNT) { page ->
            val root = content(activity)
            root.measure(
                View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(2400, View.MeasureSpec.EXACTLY)
            )
            root.layout(0, 0, 1080, 2400)
            assertTrue("page ${page + 1} was not laid out", root.width > 0 && root.height > 0)
            if (page < TutorialActivity.PAGE_COUNT - 1) press(activity, "NEXT")
        }
        controller.destroy()
    }

    @Test
    fun `NEXT four times reaches the last page, where the button says LET'S GO`() {
        val activity = open()

        toLastPage(activity)

        val root = content(activity)
        assertNotNull(findByText(root, "Nothing leaves your phone"))
        assertNotNull(findByText(root, "LET'S GO"))
        assertNull("NEXT is gone on the last page", findByText(root, "NEXT"))
        assertEquals(View.VISIBLE, findByText(root, "BACK")!!.visibility)
        assertNotNull(findByDescription(root, "Page 5 of 5"))
        activity.finish()
    }

    @Test
    fun `the dots say which page this is`() {
        val activity = open()
        press(activity, "NEXT")
        assertNotNull(findByDescription(content(activity), "Page 2 of 5"))
        press(activity, "BACK")
        assertNotNull(findByDescription(content(activity), "Page 1 of 5"))
        activity.finish()
    }

    // ── the pages ending ──────────────────────────────────────────────────────

    @Test
    fun `nothing is marked until the pages end`() {
        val activity = open()
        toLastPage(activity)

        val firstRun = FirstRun(context)
        assertFalse(firstRun.tutorialSeen)
        assertFalse(firstRun.hudTourPending)
        activity.finish()
    }

    @Test
    fun `LET'S GO ends the pages, marks them seen, queues the tour and says OK`() {
        val activity = open()
        toLastPage(activity)

        press(activity, "LET'S GO")

        assertTrue(activity.isFinishing)
        assertEquals(Activity.RESULT_OK, shadowOf(activity).resultCode)
        val firstRun = FirstRun(context)
        assertTrue(firstRun.tutorialSeen)
        assertTrue(firstRun.hudTourPending)
        // The first run returns to the camera screen that opened it; it does not start another.
        assertNull(shadowOf(activity).nextStartedActivity)
    }

    @Test
    fun `SKIP does the same from any page`() {
        val activity = open()
        press(activity, "NEXT")

        findByDescription(content(activity), "Skip the introduction")!!.performClick()

        assertTrue(activity.isFinishing)
        assertEquals(Activity.RESULT_OK, shadowOf(activity).resultCode)
        assertTrue(FirstRun(context).tutorialSeen)
        assertTrue(FirstRun(context).hudTourPending)
    }

    @Test
    fun `once the pages have ended they are not shown to that install again`() {
        assertTrue(FirstRun(context).shouldShowTutorial(hasHistory = false))

        val activity = open()
        findByDescription(content(activity), "Skip the introduction")!!.performClick()

        assertFalse(FirstRun(context).shouldShowTutorial(hasHistory = false))
    }

    @Test
    fun `back steps back a page, and out of the first page ends the pages`() {
        val activity = open()
        press(activity, "NEXT")
        assertNotNull(findByText(content(activity), "Your Cindy, your movements"))

        activity.onBackPressedDispatcher.onBackPressed()
        assertNotNull(findByText(content(activity), "Cindy, counted for you"))
        assertFalse(activity.isFinishing)

        activity.onBackPressedDispatcher.onBackPressed()
        assertTrue(activity.isFinishing)
        assertTrue(FirstRun(context).tutorialSeen)
    }

    @Test
    fun `BACK goes back a page`() {
        val activity = open()
        press(activity, "NEXT")
        press(activity, "NEXT")

        press(activity, "BACK")

        assertNotNull(findByText(content(activity), "Your Cindy, your movements"))
        activity.finish()
    }

    // ── swiping ───────────────────────────────────────────────────────────────

    @Test
    fun `a swipe to the left turns to the next page and one to the right comes back`() {
        val activity = open()

        swipe(activity, 800f, 500f, 300f, 520f)
        assertNotNull(findByText(content(activity), "Your Cindy, your movements"))

        swipe(activity, 300f, 500f, 800f, 480f)
        assertNotNull(findByText(content(activity), "Cindy, counted for you"))
        activity.finish()
    }

    @Test
    fun `a scroll up or down is not a swipe, and neither is a tap`() {
        val activity = open()

        swipe(activity, 500f, 1200f, 480f, 300f)
        swipe(activity, 500f, 500f, 500f, 500f)
        // Mostly up, a little across: a scroll that wandered.
        swipe(activity, 600f, 1200f, 300f, 300f)

        assertNotNull(findByText(content(activity), "Cindy, counted for you"))
        activity.finish()
    }

    @Test
    fun `swiping past either end stays where it is`() {
        val activity = open()
        swipe(activity, 300f, 500f, 800f, 500f)
        assertNotNull(findByText(content(activity), "Cindy, counted for you"))

        toLastPage(activity)
        swipe(activity, 800f, 500f, 300f, 500f)
        assertNotNull(findByText(content(activity), "Nothing leaves your phone"))
        assertFalse(activity.isFinishing)
        activity.finish()
    }

    // ── what each page says ───────────────────────────────────────────────────

    @Test
    fun `the second page says what counts, what is tapped in, and how to choose`() {
        val activity = open()
        press(activity, "NEXT")
        val root = content(activity)

        assertNotNull(findByDescription(root, "Band-assisted pull-ups, counted"))
        assertNotNull(findByDescription(root, "Push-ups from the knees, counted"))
        assertNotNull(findByDescription(root, "Heels-flat, on-toes or box squats, counted"))
        // "+1" is said as words, as the movement sheet says it.
        assertNotNull(
            findByDescription(root, "Inverted rows, incline push-ups and more, you tap plus one")
        )
        assertTrue(contains(root, "Spot heels-flat squats"))
        assertTrue(contains(root, "Sessions with other movements are saved as an Adaptive Cindy"))
        assertNotNull(findByText(root, "CHOOSE MY MOVEMENTS"))
        activity.finish()
    }

    @Test
    fun `CHOOSE MY MOVEMENTS opens the movement sheet, and saving reports the choice`() {
        val activity = open()
        press(activity, "NEXT")

        press(activity, "CHOOSE MY MOVEMENTS")
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        val sheet = dialog.window!!.decorView
        assertNotNull(findByText(sheet, "Make Cindy yours"))

        findByText(sheet, "SAVE")!!.performClick()

        // Nothing was changed in the sheet, so what is saved and said is the standard Cindy.
        assertEquals("Cindy", ShadowToast.getTextOfLatestToast())
        assertEquals(CindyProfile.STANDARD, Profile(context).movements)
        activity.finish()
    }

    @Test
    fun `the third page shows where to stand, in a picture and in three facts`() {
        val activity = open()
        press(activity, "NEXT")
        press(activity, "NEXT")
        val root = content(activity)

        assertNotNull(findByText(root, "Where to stand"))
        assertTrue("no placement diagram", hasViewOfType(root, PlacementGuideView::class.java))
        assertNotNull(findByText(root, "Stand the phone up rather than laying it flat."))
        assertNotNull(findByText(root, "Keep your head and your feet both in shot."))
        assertTrue(contains(root, "moving it mid-workout resets what it has learned"))
        activity.finish()
    }

    @Test
    fun `the fourth page says what happens before the clock starts`() {
        val activity = open()
        repeat(3) { press(activity, "NEXT") }
        val root = content(activity)

        assertNotNull(findByText(root, "Before the clock starts"))
        assertTrue(contains(root, "START checks your framing"))
        assertTrue(contains(root, "The dot on the status line turns green"))
        assertTrue(contains(root, "fix a miscount any time"))
        activity.finish()
    }

    @Test
    fun `the last page says nothing leaves the phone, and on a first run that the camera is next`() {
        val activity = open()
        toLastPage(activity)
        val root = content(activity)

        assertTrue(contains(root, "The picture is never uploaded"))
        assertTrue(contains(root, "REC films only when you tap it"))
        assertTrue(contains(root, "Strava stays off until you connect it in the menu"))
        assertNotNull(findByText(root, "Next, Android asks to use the camera."))
        activity.finish()
    }

    // ── a replay ──────────────────────────────────────────────────────────────

    @Test
    fun `a replay ends on DONE, without the camera footnote`() {
        val activity = open(replay = true)
        toLastPage(activity)
        val root = content(activity)

        assertNotNull(findByText(root, "DONE"))
        assertNull(findByText(root, "LET'S GO"))
        assertNull(findByText(root, "Next, Android asks to use the camera."))
        activity.finish()
    }

    @Test
    fun `finishing a replay brings the camera screen back to the front`() {
        val activity = open(replay = true)
        toLastPage(activity)

        press(activity, "DONE")

        val started = shadowOf(activity).nextStartedActivity
        assertNotNull("the camera screen was not started", started)
        assertEquals(MainActivity::class.java.name, started.component?.className)
        // To the existing camera screen, closing the menu and help above it, not a second one.
        assertTrue(started.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
        assertTrue(started.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
        assertTrue(activity.isFinishing)
        assertTrue(FirstRun(context).hudTourPending)
    }

    // ── Help ──────────────────────────────────────────────────────────────────

    @Test
    fun `Help offers the tour first, and opens the pages as a replay`() {
        val help = Robolectric.buildActivity(HelpActivity::class.java).setup().get()

        val row = findByDescriptionPrefix(content(help), "Take the tour")
        assertNotNull("Help has no way to take the tour again", row)
        row!!.performClick()

        val started = shadowOf(help).nextStartedActivity
        assertEquals(TutorialActivity::class.java.name, started.component?.className)
        assertTrue("it is not a replay", started.getBooleanExtra("replay", false))
        help.finish()
    }

    @Test
    fun `the tour row comes before the first heading`() {
        val help = Robolectric.buildActivity(HelpActivity::class.java).setup().get()
        val all = texts(content(help))
        assertTrue(all.indexOf("Take the tour") in 0 until all.indexOf("THE WORKOUT"))
        help.finish()
    }

    @Test
    fun `Help still builds and lays out with the row in it`() {
        val controller = Robolectric.buildActivity(HelpActivity::class.java)
        val activity = controller.setup().get()
        val root = content(activity)
        root.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(2400, View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2400)
        assertTrue(root.width > 0 && root.height > 0)
        controller.destroy()
    }

    // ── the pieces ────────────────────────────────────────────────────────────

    @Test
    fun `the placement facts are three rows`() {
        val activity = open()
        val facts = activity.placementFacts()
        assertEquals(3, facts.childCount)
        assertEquals(
            listOf(
                "Stand the phone up rather than laying it flat.",
                "Keep your head and your feet both in shot.",
                "Then leave it there — moving it mid-workout resets what it has learned."
            ),
            texts(facts)
        )
        activity.finish()
    }

    @Test
    fun `the flags start off and move one at a time`() {
        val firstRun = FirstRun(context)
        assertFalse(firstRun.tutorialSeen)
        assertFalse(firstRun.hudTourPending)
        assertFalse(firstRun.placementDismissed)

        firstRun.tutorialSeen = true
        assertTrue(FirstRun(context).tutorialSeen)
        assertFalse(FirstRun(context).hudTourPending)

        firstRun.hudTourPending = true
        firstRun.hudTourPending = false
        assertFalse(FirstRun(context).hudTourPending)
    }

    @Test
    fun `dismissing the placement guide is enough to be treated as a returning athlete`() {
        context.getSharedPreferences("cindy", Context.MODE_PRIVATE)
            .edit().putBoolean(Onboarding.KEY_PLACEMENT_SEEN, true).commit()

        val firstRun = FirstRun(context)
        assertTrue(firstRun.placementDismissed)
        assertFalse(firstRun.shouldShowTutorial(hasHistory = false))
    }

    @Test
    fun `a session on record is enough too`() {
        assertFalse(FirstRun(context).shouldShowTutorial(hasHistory = true))
    }
}
