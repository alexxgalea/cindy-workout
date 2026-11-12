package com.cindy.tracker

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.ViewGroup
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
 * How a navigation page is closed: from a back control at the top, and from the system back
 * gesture, with no DONE pill at the bottom (ADR 0007).
 *
 * The pages are the menu, Progress, You, Movements, Help and the session page, which is where Progress
 * pushes to. Each one is opened as an athlete would reach it and then closed both ways, because a
 * top control that only looks like a back button, or a gesture a page swallows, are the two ways
 * this goes wrong. What is asserted is what the athlete or TalkBack would perceive: a control
 * named "Back", 48dp to hit, a title in the middle of the bar, and no DONE.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TopBarScreenTest {

    @get:Rule
    val noStrava = NoStravaCredentials()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    @After
    fun reset() {
        RecordStore(context).clear()
    }

    private class Page(val name: String, val title: String?, val open: (Context) -> Activity)

    private fun session(): Attempt = Attempt(
        rounds = 12,
        reps = 3,
        atMillis = System.currentTimeMillis() - 2L * 24 * 60 * 60 * 1000,
        durationMs = 20 * 60 * 1000L,
        profile = CindyProfile.STANDARD
    )

    private val pages = listOf(
        Page("the menu", "Menu") {
            Robolectric.buildActivity(
                MenuActivity::class.java, MenuActivity.intent(it, workoutLive = false)
            ).setup().get()
        },
        Page("Progress", "Progress") {
            Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        },
        Page("You", "You") {
            Robolectric.buildActivity(AccountActivity::class.java).setup().get()
        },
        Page("Movements", "Movements") {
            Robolectric.buildActivity(MovementsActivity::class.java).setup().get()
        },
        Page("Help", "Cindy") {
            Robolectric.buildActivity(HelpActivity::class.java).setup().get()
        },
        Page("a session reopened from Progress", "Session") {
            val attempt = session()
            RecordStore(it).add(attempt)
            Robolectric.buildActivity(
                ResultsActivity::class.java, ResultsActivity.review(it, attempt.atMillis)
            ).setup().get()
        },
        Page("a session straight after a workout", "Session") {
            val attempt = session()
            RecordStore(it).add(attempt)
            Robolectric.buildActivity(
                ResultsActivity::class.java, ResultsActivity.intent(it, attempt, stoppedEarly = false)
            ).setup().get()
        }
    )

    private fun content(activity: Activity): View = activity.findViewById(android.R.id.content)

    private fun layOut(activity: Activity) {
        val root = content(activity)
        root.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(2400, View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2400)
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

    private fun textsIn(root: View): List<String> = buildList {
        if (root is TextView) add(root.text.toString())
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(textsIn(root.getChildAt(i)))
    }

    private fun findByText(root: View, text: String): TextView? {
        if (root is TextView && root.text.toString() == text) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findByText(root.getChildAt(i), text)?.let { return it }
            }
        }
        return null
    }

    private fun xInRoot(view: View, root: View): Int {
        var x = 0
        var v: View = view
        while (v !== root) {
            x += v.left
            v = v.parent as View
        }
        return x
    }

    @Test
    fun `every navigation page closes from its Back control`() {
        for (page in pages) {
            val activity = page.open(context)
            val back = findByDescription(content(activity), "Back")
            assertNotNull("${page.name} has no Back control", back)
            assertFalse("${page.name} closed before Back was pressed", activity.isFinishing)
            back!!.performClick()
            assertTrue("${page.name} did not close from Back", activity.isFinishing)
        }
    }

    @Test
    fun `every navigation page closes from the back gesture`() {
        for (page in pages) {
            val activity = page.open(context)
            (activity as androidx.activity.ComponentActivity).onBackPressedDispatcher.onBackPressed()
            assertTrue("${page.name} did not close from the back gesture", activity.isFinishing)
        }
    }

    @Test
    fun `no navigation page shows a DONE pill`() {
        for (page in pages) {
            val activity = page.open(context)
            assertFalse("${page.name} still shows DONE", textsIn(content(activity)).contains("DONE"))
        }
    }

    @Test
    fun `the Back control is at least 48dp to hit, and spoken as a button`() {
        for (page in pages) {
            val activity = page.open(context)
            layOut(activity)
            val back = findByDescription(content(activity), "Back")
            assertNotNull("${page.name} has no Back control", back)
            val min = (48 * activity.resources.displayMetrics.density).toInt()
            assertTrue("${page.name}: Back is ${back!!.width}x${back.height} px", back.width >= min && back.height >= min)
            assertTrue("${page.name}: Back is not clickable", back.isClickable)
        }
    }

    @Test
    fun `the title is centred in the bar`() {
        for (page in pages) {
            val activity = page.open(context)
            layOut(activity)
            val root = content(activity)
            val title = findByText(root, page.title!!)
            assertNotNull("${page.name} has no title ${page.title}", title)
            val centre = xInRoot(title!!, root) + title.width / 2
            assertEquals("${page.name}: the title is off centre", root.width / 2f, centre.toFloat(), 2f)
        }
    }

    @Test
    fun `a page with nothing to act on has no bottom bar`() {
        for (page in pages.take(4)) {
            val activity = page.open(context)
            val actions = activity.findViewById<ViewGroup>(R.id.actions)
            assertEquals("${page.name} keeps an empty action bar", 0, actions?.childCount ?: 0)
        }
    }
}
