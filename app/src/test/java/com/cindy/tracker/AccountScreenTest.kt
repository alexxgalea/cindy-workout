package com.cindy.tracker

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
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
import org.robolectric.shadows.ShadowLooper
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * The profile screen and the places that point at it: the menu's profile card and the avatar view.
 *
 * What a badge is, and when it is earned, is tested without a view in [BadgesTest]; the name and
 * the photo's arithmetic in [AvatarTest]. What is tested here is the part an athlete meets: a
 * screen that builds empty and with a history, tiles that read as earned or locked, sheets that
 * open, a name that is kept only when they say SAVE, and a menu that leads here.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AccountScreenTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val zone: ZoneId get() = ZoneId.systemDefault()

    @Before
    @After
    fun reset() {
        RecordStore(context).clear()
        Profile(context).displayName = null
        AvatarStore.clear(context)
    }

    // ── finding things ────────────────────────────────────────────────────────

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

    private fun findEditText(root: View): EditText? {
        if (root is EditText) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findEditText(root.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun content(activity: Activity): View = activity.findViewById(android.R.id.content)

    private fun sheetRoot(): View {
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        return dialog.window!!.decorView
    }

    private fun openAccount(): Activity =
        Robolectric.buildActivity(AccountActivity::class.java).setup().get()

    private fun openMenu(): Activity = Robolectric.buildActivity(
        MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
    ).setup().get()

    // ── what is recorded ──────────────────────────────────────────────────────

    private val day = LocalDate.of(2026, 3, 2)

    private fun session(on: LocalDate = day, rounds: Int = 10) = Attempt(
        rounds = rounds,
        reps = 0,
        atMillis = on.atTime(12, 0).atZone(zone).toInstant().toEpochMilli(),
        durationMs = 10 * 60_000L
    )

    private fun record(vararg sessions: Attempt) {
        sessions.forEach { assertTrue(RecordStore(context).add(it)) }
    }

    // ── the screen, empty ─────────────────────────────────────────────────────

    @Test
    fun `the screen builds with nothing recorded, and every badge is locked`() {
        val activity = openAccount()
        val root = content(activity)

        assertNotNull("no prompt for a name", findByDescriptionPrefix(root, "Add your name"))
        assertNotNull("no prompt for a photo", findByDescriptionPrefix(root, "Add a photo"))
        assertNotNull(findByText(root, "Finish a session and your badges start here."))
        assertNotNull(findByText(root, "BADGES · 0 OF 26"))
        for (badge in Badge.entries) {
            assertNotNull(
                "no tile for ${badge.title}",
                findByDescriptionPrefix(root, "${badge.title}, locked")
            )
        }
        activity.finish()
    }

    @Test
    fun `the screen measures and lays out`() {
        record(session())
        val controller = Robolectric.buildActivity(AccountActivity::class.java)
        val activity = controller.setup().get()
        val root = content(activity)
        root.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(2400, View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2400)
        assertTrue("nothing was laid out", root.width > 0 && root.height > 0)
        controller.destroy()
    }

    @Test
    fun `every family has its heading`() {
        val root = content(openAccount())
        for (family in BadgeFamily.entries) {
            assertNotNull(family.label, findByText(root, family.label.uppercase()))
        }
    }

    // ── the screen, with a history ────────────────────────────────────────────

    @Test
    fun `earned badges read as earned and the others say how far along they are`() {
        record(session(rounds = 10))
        val root = content(openAccount())

        assertNotNull(findByText(root, "BADGES · 4 OF 26"))
        assertNotNull(findByText(root, "Training since 2 Mar 2026 · 1 session"))
        for (earned in listOf("First Cindy", "First round", "Novice", "Intermediate")) {
            assertNotNull(
                "$earned is not earned",
                findByDescriptionPrefix(root, "$earned, earned 2 Mar 2026")
            )
        }
        // Ten rounds is ten of the sixteen Advanced asks for, and one of the ten sessions.
        assertNotNull(findByDescriptionPrefix(root, "Advanced, locked, 10 of 16 rounds"))
        assertNotNull(findByDescriptionPrefix(root, "10 sessions, locked, 1 of 10 sessions"))
        // A badge with nothing to count says only that it is locked.
        assertNotNull(findByDescriptionPrefix(root, "Past Tom Holland, locked"))
        assertNull(findByDescriptionPrefix(root, "Past Tom Holland, locked, "))
    }

    @Test
    fun `a session the camera lost the athlete in earns nothing but the first session`() {
        record(session(rounds = 27).copy(untrackedMs = Records.UNTRACKED_TOLERANCE_MS))
        val root = content(openAccount())

        assertNotNull(findByText(root, "BADGES · 1 OF 26"))
        assertNotNull(findByDescriptionPrefix(root, "First Cindy, earned"))
        assertNotNull(findByDescriptionPrefix(root, "Legend, locked"))
    }

    // ── sheets ────────────────────────────────────────────────────────────────

    @Test
    fun `a locked tile opens a sheet with what it asks for and how far along it is`() {
        record(session(rounds = 10))
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Advanced, locked")!!.performClick()
        val sheet = sheetRoot()
        assertNotNull(findByText(sheet, "Advanced"))
        assertNotNull(findByText(sheet, "16 rounds in a standard Cindy."))
        assertNotNull(findByText(sheet, "10 of 16 rounds"))

        findByText(sheet, "DONE")!!.performClick()
        activity.finish()
    }

    @Test
    fun `an earned tile opens a sheet with the day it was earned`() {
        record(session(rounds = 10))
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Intermediate, earned")!!.performClick()
        val sheet = sheetRoot()
        assertNotNull(findByText(sheet, "Intermediate"))
        assertNotNull(findByText(sheet, "Earned 2 Mar 2026"))
        activity.finish()
    }

    @Test
    fun `a badge with nothing to count says it is not earned yet`() {
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Made it yours, locked")!!.performClick()
        val sheet = sheetRoot()
        assertNotNull(findByText(sheet, "Finish an Adaptive Cindy."))
        assertNotNull(findByText(sheet, "Not earned yet"))
        activity.finish()
    }

    // ── the name ──────────────────────────────────────────────────────────────

    @Test
    fun `saving a name keeps it, and the screen says it`() {
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Add your name")!!.performClick()
        val sheet = sheetRoot()
        findEditText(sheet)!!.setText("  Alex   Galea ")
        findByText(sheet, "SAVE")!!.performClick()

        assertEquals("Alex Galea", Profile(context).displayName)
        assertNotNull(findByDescriptionPrefix(content(activity), "Your name, Alex Galea, tap to change"))
        assertNotNull(findByText(content(activity), "Alex Galea"))
        activity.finish()
    }

    @Test
    fun `the name sheet starts with the name already there`() {
        Profile(context).displayName = "Alex"
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Your name, Alex")!!.performClick()
        assertEquals("Alex", findEditText(sheetRoot())!!.text.toString())
        activity.finish()
    }

    @Test
    fun `an emptied name is taken back`() {
        Profile(context).displayName = "Alex"
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Your name, Alex")!!.performClick()
        val sheet = sheetRoot()
        findEditText(sheet)!!.setText("   ")
        findByText(sheet, "SAVE")!!.performClick()

        assertNull(Profile(context).displayName)
        assertNotNull(findByDescriptionPrefix(content(activity), "Add your name"))
        activity.finish()
    }

    @Test
    fun `cancelling leaves the name alone`() {
        Profile(context).displayName = "Alex"
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Your name, Alex")!!.performClick()
        val sheet = sheetRoot()
        findEditText(sheet)!!.setText("Someone else")
        findByText(sheet, "CANCEL")!!.performClick()

        assertEquals("Alex", Profile(context).displayName)
        activity.finish()
    }

    @Test
    fun `a name is never longer than the limit, however it got there`() {
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Add your name")!!.performClick()
        val field = findEditText(sheetRoot())!!
        field.setText("A".repeat(60))
        assertEquals(Avatar.MAX_NAME, field.text.length)
        activity.finish()
    }

    // ── the photo ─────────────────────────────────────────────────────────────

    private fun storeAPhoto() {
        // Any bytes do: whether there is a photo is whether there is a file.
        File(context.filesDir, "avatar.jpg").writeBytes(ByteArray(16) { it.toByte() })
    }

    @Test
    fun `without a photo the sheet offers to choose one or to cancel, and never to remove`() {
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Add a photo")!!.performClick()
        val sheet = sheetRoot()
        assertNotNull(findByText(sheet, "CHOOSE PHOTO"))
        assertNotNull(findByText(sheet, "CANCEL"))
        assertNull(findByText(sheet, "REMOVE"))
        activity.finish()
    }

    @Test
    fun `with a photo the sheet offers to remove it, and removing it does`() {
        storeAPhoto()
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Your photo, tap to change")!!.performClick()
        val sheet = sheetRoot()
        assertNotNull(findByText(sheet, "CHOOSE PHOTO"))
        findByText(sheet, "REMOVE")!!.performClick()

        assertFalse(AvatarStore.exists(context))
        assertNotNull(findByDescriptionPrefix(content(activity), "Add a photo"))
        activity.finish()
    }

    @Test
    fun `choosing a photo opens the system picker`() {
        val activity = openAccount()

        findByDescriptionPrefix(content(activity), "Add a photo")!!.performClick()
        findByText(sheetRoot(), "CHOOSE PHOTO")!!.performClick()

        val started = shadowOf(activity).nextStartedActivityForResult
        assertNotNull("the picker was not started", started)
        activity.finish()
    }

    @Test
    fun `DONE closes the screen`() {
        val activity = openAccount()
        findByText(content(activity), "DONE")!!.performClick()
        assertTrue(activity.isFinishing)
    }

    // ── the menu ──────────────────────────────────────────────────────────────

    @Test
    fun `the menu leads with a profile card that invites a name and a photo`() {
        val activity = openMenu()
        assertNotNull(findByDescriptionPrefix(content(activity), "You, Add your name and photo"))
        activity.finish()
    }

    @Test
    fun `the profile card names the athlete, their badges and their level`() {
        Profile(context).displayName = "Alex"
        record(session(rounds = 10))
        val activity = openMenu()

        assertNotNull(
            findByDescriptionPrefix(content(activity), "Alex, 4 badges · Intermediate")
        )
        activity.finish()
    }

    @Test
    fun `a name with no sessions yet points at the first badge`() {
        Profile(context).displayName = "Alex"
        val activity = openMenu()

        assertNotNull(
            findByDescriptionPrefix(content(activity), "Alex, Finish a session to earn your first badge")
        )
        activity.finish()
    }

    @Test
    fun `the profile card opens the profile screen`() {
        val activity = openMenu()

        findByDescriptionPrefix(content(activity), "You, ")!!.performClick()

        val next = shadowOf(activity).nextStartedActivity
        assertEquals(AccountActivity::class.java.name, next.component?.className)
        activity.finish()
    }

    @Test
    fun `the menu still deals in every row, the settings under the profile card too`() {
        val activity = openMenu()
        // The last row of the settings card, a long way down the stagger. Before the profile card
        // was added only the first card was dealt, so this row would never have been hidden.
        val help = findByDescriptionPrefix(content(activity), "Help, ")!!
        assertEquals("the row is waiting its turn", 0f, help.alpha, 0f)

        ShadowLooper.idleMainLooper(3, TimeUnit.SECONDS)
        assertEquals("the row never arrived", 1f, help.alpha, 0f)
        activity.finish()
    }

    // ── the avatar view ───────────────────────────────────────────────────────

    private fun draw(view: AvatarView, size: Int) {
        view.measure(
            View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
        )
        view.layout(0, 0, size, size)
        view.draw(Canvas(Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)))
    }

    @Test
    fun `the avatar draws a photo, initials and a neutral figure`() {
        val view = AvatarView(context)
        val photo = Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888)

        view.show(photo, "Alex Galea")
        draw(view, 120)
        view.show(null, "Alex Galea")
        draw(view, 120)
        view.show(null, "Alex")
        draw(view, 120)
        view.show(null, null)
        draw(view, 120)
        view.show(null, "- -")
        draw(view, 120)
    }

    @Test
    fun `an avatar with no size asked of it is the size of a row`() {
        val view = AvatarView(context)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.AT_MOST)
        )
        val expected = (44 * context.resources.displayMetrics.density).toInt()
        assertEquals(expected, view.measuredWidth)
        assertEquals(expected, view.measuredHeight)
    }

    @Test
    fun `an avatar is a square whichever side it was told`() {
        val view = AvatarView(context)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(88, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.AT_MOST)
        )
        assertEquals(88, view.measuredWidth)
        assertEquals(88, view.measuredHeight)
    }

    @Test
    fun `an avatar is decoration until a screen makes it a button`() {
        val view = AvatarView(context)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, view.importantForAccessibility)
    }
}
