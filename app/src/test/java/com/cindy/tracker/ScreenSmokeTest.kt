package com.cindy.tracker

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

/**
 * Builds every screen that does not need a camera, and lays it out.
 *
 * These exist because of a crash that reached a device: `HelpActivity` reached for
 * `(layoutParams as LinearLayout.LayoutParams).marginStart` inside an `apply {}`, and a view
 * built in code has no layoutParams until a parent adds it. Nothing could have caught it — the
 * suite was two hundred tests of pure engine logic and not one of a single view, lint does not
 * model null layoutParams, and there is no emulator on the machine this is developed on.
 *
 * They are deliberately shallow. They assert that a screen *constructs, inflates, styles and
 * measures* without throwing, which is the failure mode hand-built view hierarchies actually
 * have. They are not a claim about how anything looks.
 *
 * [MainActivity] is absent on purpose: it binds CameraX and loads a TFLite interpreter in
 * `onCreate`, neither of which Robolectric can stand in for honestly. Its *layout* is not
 * absent, though — see the last test, which is the closest this suite can get to the screen the
 * app actually opens on.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ScreenSmokeTest {

    /** Through to RESUMED, then measured and laid out — styles resolve during measure. */
    private inline fun <reified T : android.app.Activity> smoke(intent: Intent? = null) {
        val controller = if (intent == null) {
            Robolectric.buildActivity(T::class.java)
        } else {
            Robolectric.buildActivity(T::class.java, intent)
        }
        val activity = controller.setup().get()
        val root = activity.findViewById<android.view.View>(android.R.id.content)
        root.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(1080, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(2400, android.view.View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2400)
        assertTrue("nothing was laid out", root.width > 0 && root.height > 0)
        controller.destroy()
    }

    /**
     * The camera HUD's layout, which [MainActivity]'s own exclusion would otherwise leave as the
     * only screen in the app with no coverage at all.
     *
     * Inflating it without the activity skips CameraX and the interpreter while still catching
     * what a layout rewrite actually gets wrong: an attribute the platform will not take, a
     * drawable that is not there, a custom view that throws on inflate, a style that fails to
     * resolve during measure.
     */
    @Test
    fun `the camera HUD inflates`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.setTheme(R.style.Theme_Cindy)
        val binding = com.cindy.tracker.databinding.ActivityMainBinding
            .inflate(android.view.LayoutInflater.from(context))
        binding.root.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(1080, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(2400, android.view.View.MeasureSpec.EXACTLY)
        )
        binding.root.layout(0, 0, 1080, 2400)
        // The bands have to reach both edges, or the picture shows through beside the HUD.
        assertEquals("the top band is inset from the glass", 1080, binding.bandTop.width)
        assertEquals("the bottom band is inset from the glass", 1080, binding.bandBottom.width)
        assertTrue("the bands ate the whole screen", binding.bandTop.height + binding.bandBottom.height < 2400)
    }

    @Test
    fun `the help screen builds`() = smoke<HelpActivity>()

    @Test
    fun `the menu builds`() {
        smoke<MenuActivity>(
            MenuActivity.intent(ApplicationProvider.getApplicationContext(), workoutLive = false)
        )
    }

    /** The menu refuses the movement picker mid-workout, and says so in an extra row. */
    @Test
    fun `the menu builds mid-workout`() {
        smoke<MenuActivity>(
            MenuActivity.intent(ApplicationProvider.getApplicationContext(), workoutLive = true)
        )
    }

    /**
     * With a track chosen, which is the other branch of the music row's subtitle — and of the
     * sheet behind it, which grows a toggle only once there is something to toggle.
     */
    @Test
    fun `the menu builds with a track chosen`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val profile = Profile(context)
        profile.musicTrack = "content://fake/track.mp3"
        profile.musicOn = false
        smoke<MenuActivity>(MenuActivity.intent(context, workoutLive = false))
        profile.musicTrack = null
        profile.musicOn = true
    }

    /** With a watch paired, which drops the "add your age" clause once the details are set too. */
    @Test
    fun `the menu builds with a watch paired`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val profile = Profile(context)
        profile.heartRateDevice = HeartRateDevice("AA:BB:CC:DD:EE:FF", "Test Strap")
        smoke<MenuActivity>(MenuActivity.intent(context, workoutLive = false))
        profile.heartRateDevice = null
    }

    /**
     * Both branches of the heart-rate sheet, reached the same way an athlete would: tapping the
     * row. Robolectric reports no BLE feature, so the paired branch's source reports UNSUPPORTED
     * rather than actually connecting to anything — this only has to show that neither branch
     * throws.
     */
    @Test
    fun `the heart-rate sheet builds with and without a watch`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val profile = Profile(context)
        profile.heartRateDevice = null

        var activity = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        var row = findByDescriptionPrefix(
            activity.findViewById<android.view.View>(android.R.id.content), "Heart rate"
        )
        assertTrue("no Heart rate row", row != null)
        row!!.performClick()
        var dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        dialog!!.dismiss()

        profile.heartRateDevice = HeartRateDevice("AA:BB:CC:DD:EE:FF", "Test Strap")
        activity = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        row = findByDescriptionPrefix(
            activity.findViewById<android.view.View>(android.R.id.content), "Heart rate"
        )
        assertTrue("no Heart rate row", row != null)
        row!!.performClick()
        dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        dialog!!.dismiss()
        profile.heartRateDevice = null
    }

    /** The other branch of the reminder row's subtitle: on, and (in the test) able to post. */
    @Test
    fun `the menu builds with the reminder on`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        Profile(context).reminderOn = true
        try {
            smoke<MenuActivity>(MenuActivity.intent(context, workoutLive = false))
        } finally {
            Profile(context).reminderOn = false
        }
    }

    /** The first view under [root] whose contentDescription starts with [prefix]. */
    private fun findByDescriptionPrefix(
        root: android.view.View, prefix: String
    ): android.view.View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescriptionPrefix(root.getChildAt(i), prefix)?.let { return it }
            }
        }
        return null
    }

    /** The first view under [root] whose contentDescription contains [substring]. */
    private fun findByDescriptionContains(
        root: android.view.View, substring: String
    ): android.view.View? {
        if (root.contentDescription?.toString()?.contains(substring) == true) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescriptionContains(root.getChildAt(i), substring)?.let { return it }
            }
        }
        return null
    }

    /** The first view of type [T] under [root]; for a custom view with no id of its own. */
    private inline fun <reified T : android.view.View> firstOfType(root: android.view.View): T? =
        @Suppress("UNCHECKED_CAST") (firstOfClass(root, T::class.java) as? T)

    /** [firstOfType]'s recursion, kept out of the inline function since that cannot call itself. */
    private fun firstOfClass(root: android.view.View, cls: Class<*>): android.view.View? {
        if (cls.isInstance(root)) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                firstOfClass(root.getChildAt(i), cls)?.let { return it }
            }
        }
        return null
    }

    @Test
    fun `the reminder row opens its sheet`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        Profile(context).reminderOn = false
        val activity = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        val row = findByDescriptionPrefix(
            activity.findViewById<android.view.View>(android.R.id.content), "Daily reminder"
        )
        assertTrue("no Daily reminder row", row != null)
        row!!.performClick()
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        Profile(context).reminderOn = false
    }

    /** The first text view under [root] showing exactly [text]. */
    private fun findByText(root: android.view.View, text: String): android.view.View? {
        if (root is android.widget.TextView && root.text.toString() == text) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                findByText(root.getChildAt(i), text)?.let { return it }
            }
        }
        return null
    }

    /** The menu with its voice sheet open, as the athlete would see it: the menu, and the sheet. */
    private fun openVoiceSheet(): Pair<android.app.Activity, android.app.Dialog> {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val activity = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        val row = findByDescriptionPrefix(
            activity.findViewById<android.view.View>(android.R.id.content), "Voice"
        )
        assertTrue("no Voice row", row != null)
        row!!.performClick()
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        return activity to dialog
    }

    @Test
    fun `the voice sheet lists every language, each with a way to hear it`() {
        val (_, dialog) = openVoiceSheet()
        val root = dialog.window!!.decorView
        VoicePacks.all.forEach { pack ->
            assertTrue("no row for ${pack.englishName}", findByDescriptionPrefix(root, pack.nativeName) != null)
            assertTrue(
                "no way to hear ${pack.englishName}",
                findByDescriptionPrefix(root, "Hear ${pack.englishName}") != null
            )
        }
        assertTrue("no way to manage voices", findByDescriptionPrefix(root, "Manage voices") != null)
    }

    @Test
    fun `the voice sheet builds while the engine has not answered`() {
        // Nothing has connected to a speech engine here, which is the state of a sheet opened in
        // the first moment: every row is still being checked, and none of that is an error.
        val (_, dialog) = openVoiceSheet()
        assertTrue("no row is being checked", findByText(dialog.window!!.decorView, "Checking…") != null)
    }

    @Test
    fun `choosing a language and saving stores it, and the Voice row names it`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        Profile(context).voiceLanguage = "en"
        val (activity, dialog) = openVoiceSheet()
        val root = dialog.window!!.decorView

        findByDescriptionPrefix(root, "Español")!!.performClick()
        findByText(root, "SAVE")!!.performClick()

        assertEquals("es", Profile(context).voiceLanguage)
        assertTrue(
            "the Voice row does not name the language",
            findByDescriptionPrefix(
                activity.findViewById<android.view.View>(android.R.id.content), "Voice, On"
            )?.contentDescription?.toString()?.endsWith("Español") == true
        )
        Profile(context).voiceLanguage = "en"
    }

    @Test
    fun `dismissing the voice sheet without saving leaves the language alone`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        Profile(context).voiceLanguage = "en"
        val (_, dialog) = openVoiceSheet()

        findByDescriptionPrefix(dialog.window!!.decorView, "Deutsch")!!.performClick()
        dialog.dismiss()

        assertEquals("en", Profile(context).voiceLanguage)
    }

    /**
     * The sheet that asks for a birth year and a sex. Opened directly rather than through a row,
     * so it is covered whichever screen ends up reaching it.
     */
    @Test
    fun `the heart-rate details sheet builds`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val activity = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        activity.askHeartRateDetails(Profile(activity)) {}
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        dialog.dismiss()
    }

    @Test
    fun `the records screen builds when empty`() = smoke<RecordsActivity>()

    /**
     * With history, which is a different screen: the streak card, the calendar and the progress
     * chart only exist once there is something to draw them from.
     */
    @Test
    fun `the records screen builds with history`() {
        val store = RecordStore(ApplicationProvider.getApplicationContext())
        store.clear()
        val day = 24L * 60 * 60 * 1000
        val now = System.currentTimeMillis()
        repeat(3) { i ->
            store.add(
                Attempt(
                    rounds = 12 + i,
                    reps = i,
                    atMillis = now - (2 - i) * day,
                    durationMs = 20 * 60 * 1000L,
                    roundSplitsMs = List(12 + i) { 60_000L + it * 500L },
                    profile = CindyProfile.STANDARD
                )
            )
        }
        smoke<RecordsActivity>()
        store.clear()
    }

    /**
     * Every category the report has to keep apart: standard, knee push-ups, unrecognised
     * movements, and a session with the camera lost for a minute (a lower bound).
     */
    @Test
    fun `the progress report builds across categories`() {
        val store = RecordStore(ApplicationProvider.getApplicationContext())
        store.clear()
        val day = 24L * 60 * 60 * 1000
        val now = System.currentTimeMillis()
        fun attempt(daysAgo: Int, rounds: Int, profile: CindyProfile?, untracked: Long = 0L) =
            Attempt(
                rounds = rounds,
                reps = 0,
                atMillis = now - daysAgo * day,
                durationMs = 20 * 60 * 1000L,
                roundSplitsMs = List(rounds) { 60_000L },
                profile = profile,
                untrackedMs = untracked
            )
        store.add(attempt(16, 12, CindyProfile.STANDARD))
        store.add(attempt(11, 14, CindyProfile(push = PushVariant.KNEE_PUSH_UP)))
        store.add(attempt(7, 13, null))
        store.add(attempt(3, 15, CindyProfile.STANDARD))
        store.add(attempt(1, 16, CindyProfile.STANDARD, untracked = 60_000L))
        smoke<RecordsActivity>()
        store.clear()
    }

    /** Every view under [root] whose contentDescription is exactly [description]. */
    private fun findByDescription(
        root: android.view.View, description: String
    ): android.view.View? {
        if (root.contentDescription?.toString() == description) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescription(root.getChildAt(i), description)?.let { return it }
            }
        }
        return null
    }

    private fun click(activity: android.app.Activity, description: String) {
        val view = findByDescription(
            activity.findViewById<android.view.View>(android.R.id.content), description
        )
        assertTrue("no view described \"$description\"", view != null)
        view!!.performClick()
    }

    @Test
    fun `the chart card switches metric and range`() {
        val store = RecordStore(ApplicationProvider.getApplicationContext())
        store.clear()
        val day = 24L * 60 * 60 * 1000
        val now = System.currentTimeMillis()
        repeat(3) { i ->
            store.add(
                Attempt(
                    rounds = 12 + i,
                    reps = i,
                    atMillis = now - (2 - i) * day,
                    durationMs = 20 * 60 * 1000L,
                    roundSplitsMs = List(12 + i) { 60_000L + it * 500L },
                    profile = CindyProfile.STANDARD
                )
            )
        }
        val activity = Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        click(activity, "Pace")
        click(activity, "Volume")
        click(activity, "1M")
        store.clear()
    }

    @Test
    fun `the chart card handles a range with no sessions`() {
        val store = RecordStore(ApplicationProvider.getApplicationContext())
        store.clear()
        val day = 24L * 60 * 60 * 1000
        val old = System.currentTimeMillis() - 730 * day
        repeat(2) { i ->
            store.add(
                Attempt(
                    rounds = 12 + i,
                    reps = 0,
                    atMillis = old + i * day,
                    durationMs = 20 * 60 * 1000L,
                    roundSplitsMs = List(12 + i) { 60_000L },
                    profile = CindyProfile.STANDARD
                )
            )
        }
        val activity = Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        click(activity, "1M")
        store.clear()
    }

    @Test
    fun `a trained day opens its sessions`() {
        val store = RecordStore(ApplicationProvider.getApplicationContext())
        store.clear()
        val now = System.currentTimeMillis()
        repeat(2) { i ->
            store.add(
                Attempt(
                    rounds = 12 + i,
                    reps = 0,
                    atMillis = now - i * 1000L,
                    durationMs = 20 * 60 * 1000L,
                    roundSplitsMs = List(12 + i) { 60_000L },
                    profile = CindyProfile.STANDARD
                )
            )
        }
        val activity = Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        activity.openDay(java.time.LocalDate.now())
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        store.clear()
    }

    @Test
    fun `the results screen builds`() {
        val attempt = Attempt(
            rounds = 18,
            reps = 7,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = List(18) { 55_000L + it * 1_200L },
            profile = CindyProfile.STANDARD,
            manualReps = 4
        )
        smoke<ResultsActivity>(
            ResultsActivity.intent(
                ApplicationProvider.getApplicationContext(), attempt, stoppedEarly = false
            )
        )
    }

    /**
     * A skipped movement survives the trip to the results screen.
     *
     * The screen used to be handed a field per extra, and `countedReps` was not one of them. It
     * therefore rebuilt the attempt with that field null and fell back to `rounds * 30 + reps`:
     * a round with the pull-ups skipped was *filed* as 25 reps and *displayed* as 30, while the
     * voice read out the true 25 over the top of it. The attempt now travels whole.
     */
    @Test
    fun `the results screen shows the reps that were counted, not the round tally`() {
        val skipped = Attempt(
            rounds = 1,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 116_000L,
            // Pull-ups skipped: ten push-ups and fifteen squats is the whole round's work.
            countedReps = 25
        )
        val intent = ResultsActivity.intent(
            ApplicationProvider.getApplicationContext(), skipped, stoppedEarly = true
        )
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()

        val shown = activity.findViewById<android.widget.TextView>(R.id.scoreDetail).text.toString()
        assertTrue(shown, shown.contains("25 reps"))
        assertTrue(shown, !shown.contains("30 reps"))
        activity.finish()
    }

    /**
     * A session at non-standard movements takes the other branch of the level panel — no rung,
     * no progress bar, and a different line under the title.
     */
    @Test
    fun `the results screen builds for an adaptive session`() {
        val attempt = Attempt(
            rounds = 9,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = emptyList(),
            profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        )
        smoke<ResultsActivity>(
            ResultsActivity.intent(
                ApplicationProvider.getApplicationContext(), attempt, stoppedEarly = true
            )
        )
    }

    /** The first stored session is always worth a line; the box under the score shows it. */
    @Test
    fun `the results screen celebrates a first session`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val attempt = Attempt(
            rounds = 12,
            reps = 3,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(attempt)
        val intent = ResultsActivity.intent(context, attempt, stoppedEarly = false)
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()

        assertEquals(
            android.view.View.VISIBLE,
            activity.findViewById<android.view.View>(R.id.celebration).visibility
        )
        activity.finish()
        store.clear()
    }

    /**
     * A lower score than the best one, three weeks on, is no record and no streak of either kind
     * (last week would make two weeks in a row, which is a milestone), so nothing is claimed.
     */
    @Test
    fun `the results screen stays quiet for an ordinary session`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val now = System.currentTimeMillis()
        store.add(
            Attempt(
                rounds = 20,
                reps = 0,
                atMillis = now - 21L * 24 * 60 * 60 * 1000,
                durationMs = 20 * 60 * 1000L,
                profile = CindyProfile.STANDARD
            )
        )
        val today = Attempt(
            rounds = 10,
            reps = 0,
            atMillis = now,
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(today)
        val intent = ResultsActivity.intent(context, today, stoppedEarly = false)
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()

        assertEquals(
            android.view.View.GONE,
            activity.findViewById<android.view.View>(R.id.celebration).visibility
        )
        activity.finish()
        store.clear()
    }

    /** Every text the given view tree shows, so a test can say what a built-in-code section says. */
    private fun textsIn(root: android.view.View): List<String> {
        val texts = mutableListOf<String>()
        fun walk(v: android.view.View) {
            if (v is android.widget.TextView) texts += v.text.toString()
            if (v is android.view.ViewGroup) {
                for (i in 0 until v.childCount) walk(v.getChildAt(i))
            }
        }
        walk(root)
        return texts
    }

    private fun showResults(attempt: Attempt): ResultsActivity {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        store.add(attempt)
        return Robolectric.buildActivity(
            ResultsActivity::class.java,
            ResultsActivity.intent(context, attempt, stoppedEarly = false)
        ).setup().get()
    }

    private val timedRound = listOf(
        SetSplit(Exercise.PULLUP, 14_000L, 5, 0),
        SetSplit(Exercise.PUSHUP, 17_000L, 10, 0),
        SetSplit(Exercise.SQUAT, 21_000L, 15, 0)
    )

    /** A round timed set by set fills the numbers, the round track and the movement card. */
    @Test
    fun `the results screen builds with set splits and shows the round numbers`() {
        val attempt = Attempt(
            rounds = 1,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = listOf(52_000L),
            profile = CindyProfile.STANDARD,
            countedReps = 30,
            setSplits = timedRound
        )
        val activity = showResults(attempt)

        fun visibility(id: Int) = activity.findViewById<android.view.View>(id).visibility
        assertEquals(android.view.View.VISIBLE, visibility(R.id.trackTitle))
        assertEquals(android.view.View.VISIBLE, visibility(R.id.track))
        assertEquals(android.view.View.VISIBLE, visibility(R.id.movements))
        val tiles = textsIn(activity.findViewById(R.id.tiles))
        assertTrue(tiles.toString(), tiles.containsAll(listOf("ROUNDS", "REPS", "TIME", "FASTEST")))
        val movements = textsIn(activity.findViewById(R.id.movements))
        assertTrue(movements.toString(), movements.contains("pull-ups"))
        assertTrue(movements.toString(), movements.contains("0:14 total"))
        // The headline numbers moved up into the tiles; the details keep only what is left.
        val details = textsIn(activity.findViewById(R.id.stats))
        assertTrue(details.toString(), details.none { it == "Total reps" || it == "Rounds completed" })
        activity.finish()
        RecordStore(activity).clear()
    }

    /** A session the camera lost you in says so over the round track and the movement card. */
    @Test
    fun `the results screen says at least over a lower bound session's rounds`() {
        val attempt = Attempt(
            rounds = 1,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = listOf(52_000L),
            profile = CindyProfile.STANDARD,
            countedReps = 30,
            untrackedMs = 60_000L,
            setSplits = timedRound
        )
        val activity = showResults(attempt)

        val track = textsIn(activity.findViewById(R.id.track))
        assertTrue(track.toString(), track.any { it.contains("The camera lost you for 1:00") })
        val movements = textsIn(activity.findViewById(R.id.movements))
        assertEquals(movements.toString(), 3, movements.count { it == "at least" })
        activity.finish()
        RecordStore(activity).clear()
    }

    /** A record from before sets were timed has its tiles and nothing drawn from sets it lacks. */
    @Test
    fun `the results screen hides the round track and movements without set times`() {
        val attempt = Attempt(
            rounds = 12,
            reps = 3,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = List(12) { 100_000L },
            profile = CindyProfile.STANDARD
        )
        val activity = showResults(attempt)

        fun visibility(id: Int) = activity.findViewById<android.view.View>(id).visibility
        assertEquals(android.view.View.GONE, visibility(R.id.trackTitle))
        assertEquals(android.view.View.GONE, visibility(R.id.track))
        assertEquals(android.view.View.GONE, visibility(R.id.movementsTitle))
        assertEquals(android.view.View.GONE, visibility(R.id.movements))
        val tiles = textsIn(activity.findViewById(R.id.tiles))
        assertTrue(tiles.toString(), tiles.contains("12"))
        assertTrue(tiles.toString(), tiles.contains("1:40"))
        activity.finish()
        RecordStore(activity).clear()
    }

    /** An adaptive session names its own movements everywhere the three are shown. */
    @Test
    fun `the results screen uses the adaptive session's own movement names`() {
        val attempt = Attempt(
            rounds = 1,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            roundSplitsMs = listOf(52_000L),
            profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP),
            countedReps = 30,
            setSplits = timedRound
        )
        val activity = showResults(attempt)

        val movements = textsIn(activity.findViewById(R.id.movements))
        assertTrue(movements.toString(), movements.contains("knee push-ups"))
        assertTrue(movements.toString(), movements.none { it.contains("standard push-ups") })
        val track = textsIn(activity.findViewById(R.id.track))
        assertTrue(track.toString(), track.any { it.contains("10 knee push-ups") })
        activity.finish()
        RecordStore(activity).clear()
    }

    /**
     * The calorie footnote has no id of its own — it is one more TextView the session stats
     * group grows in code — so it is found the same way [findByDescription] finds a row: by
     * walking the group Results actually built.
     */
    private fun statsFootnotes(activity: android.app.Activity): List<String> {
        val texts = mutableListOf<String>()
        fun walk(v: android.view.View) {
            if (v is android.widget.TextView) texts += v.text.toString()
            if (v is android.view.ViewGroup) {
                for (i in 0 until v.childCount) walk(v.getChildAt(i))
            }
        }
        walk(activity.findViewById(R.id.stats))
        return texts
    }

    /** A trace whose one sample covers the whole of a short attempt's clock, seeded with age and
     *  sex so [Calories.estimate] is free to use it rather than falling back to the MET model. */
    private fun heartRateAttempt(context: android.content.Context): Attempt {
        val store = RecordStore(context)
        val attempt = Attempt(
            rounds = 1,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 4_000L,
            countedReps = 10
        )
        store.add(attempt)
        HeartRateStore(context).save(
            attempt.atMillis,
            HeartRateTrace(
                startedAtMillis = attempt.atMillis,
                samples = listOf(HeartRateSample(clockMs = 0L, bpm = 150)),
                pauses = emptyList()
            )
        )
        return attempt
    }

    /**
     * A trace that covers the whole of the (short) workout clock: no minute is left for the MET
     * model to estimate, so the footnote is the "whole workout" wording rather than the blended
     * one — and it says nothing about METs, which only the blended and MET-only wordings mention.
     */
    @Test
    fun `the results screen credits heart rate for the whole workout`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 70.0
        profile.birthYear = 1990
        profile.sex = Sex.MALE
        val attempt = heartRateAttempt(context)

        val intent = ResultsActivity.intent(context, attempt, stoppedEarly = false)
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()
        val footnotes = statsFootnotes(activity)

        assertTrue("no heart-rate footnote: $footnotes", footnotes.any { it.contains("heart rate") })
        assertTrue("should not mention METs: $footnotes", footnotes.none { it.contains("METs") })

        activity.finish()
        HeartRateStore(context).clear()
        store.clear()
        profile.bodyWeightKg = 0.0
        profile.birthYear = 0
        profile.sex = null
    }

    /**
     * A trace was recorded, but there is no age or sex yet to read it with — the footnote invites
     * adding them rather than silently falling back to the MET model without saying why.
     */
    @Test
    fun `the results screen invites adding age and sex once a trace exists`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 70.0
        profile.birthYear = 0
        profile.sex = null
        val attempt = heartRateAttempt(context)

        val intent = ResultsActivity.intent(context, attempt, stoppedEarly = false)
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()
        val footnotes = statsFootnotes(activity)

        assertTrue(
            "no invitation to add age: $footnotes",
            footnotes.any { it.contains("tap to add your age") }
        )

        activity.finish()
        HeartRateStore(context).clear()
        store.clear()
        profile.bodyWeightKg = 0.0
    }

    /**
     * With no trace at all — the ordinary case until a watch is paired — the calorie footnote is
     * exactly what it always was. Heart rate must never change a number it never touched.
     */
    @Test
    fun `the results screen footnote is unchanged without a heart-rate trace`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 70.0
        profile.birthYear = 1990
        profile.sex = Sex.MALE
        val attempt = Attempt(
            rounds = 1,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 4_000L,
            countedReps = 10
        )
        store.add(attempt)

        val intent = ResultsActivity.intent(context, attempt, stoppedEarly = false)
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()
        val footnotes = statsFootnotes(activity)

        val expected = "Estimated from %.0f kg at about %.1f METs. Tap to change your weight."
            .format(java.util.Locale.US, 70.0, Calories.met(attempt.totalReps, attempt.durationMs))
        assertTrue("footnote changed: $footnotes", footnotes.any { it == expected })

        activity.finish()
        store.clear()
        profile.bodyWeightKg = 0.0
        profile.birthYear = 0
        profile.sex = null
    }

    // ── reopening a session from Progress ───────────────────────────────────

    @Test
    fun `reopening a saved session shows its date and time, and a single DONE`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val attempt = Attempt(
            rounds = 12,
            reps = 3,
            atMillis = System.currentTimeMillis() - 2L * 24 * 60 * 60 * 1000,
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(attempt)

        val activity = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.review(context, attempt.atMillis)
        ).setup().get()

        val headline = activity.findViewById<android.widget.TextView>(R.id.headline).text.toString()
        assertTrue("headline was not a date: $headline", headline != "TIME" && headline != "STOPPED")
        val actions = activity.findViewById<android.view.ViewGroup>(R.id.actions)
        assertEquals("review mode should offer only DONE", 1, actions.childCount)
        assertEquals("DONE", (actions.getChildAt(0) as android.widget.TextView).text.toString())
        assertTrue(
            "the streak row describes today, not the reviewed day",
            findByText(activity.findViewById(R.id.stats), "Streak") == null
        )

        activity.finish()
        store.clear()
    }

    @Test
    fun `a review intent for a session no longer on the board finishes`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        RecordStore(context).clear()
        val activity = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.review(context, 123_456_789L)
        ).setup().get()
        assertTrue("did not finish", activity.isFinishing)
    }

    @Test
    fun `the compare card is hidden without an earlier session at the same movements`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val attempt = Attempt(
            rounds = 10,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(attempt)
        val intent = ResultsActivity.intent(context, attempt, stoppedEarly = false)
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()

        assertEquals(
            android.view.View.GONE,
            activity.findViewById<android.view.View>(R.id.compareTitle).visibility
        )
        assertEquals(
            android.view.View.GONE,
            activity.findViewById<android.view.View>(R.id.compare).visibility
        )

        activity.finish()
        store.clear()
    }

    /** The card appears with an earlier session at the same movements, and tapping it opens it. */
    @Test
    fun `the compare card shows an earlier session and opens it when tapped`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val earlier = Attempt(
            rounds = 8,
            reps = 0,
            atMillis = System.currentTimeMillis() - 2L * 24 * 60 * 60 * 1000,
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(earlier)
        val attempt = Attempt(
            rounds = 10,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(attempt)
        val intent = ResultsActivity.intent(context, attempt, stoppedEarly = false)
        val activity = Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()

        assertEquals(
            android.view.View.VISIBLE,
            activity.findViewById<android.view.View>(R.id.compareTitle).visibility
        )
        val compare = activity.findViewById<android.view.View>(R.id.compare)
        assertEquals(android.view.View.VISIBLE, compare.visibility)

        val card = findByDescriptionContains(compare, "${Progress.formatReps(earlier.totalReps)} reps")
        assertTrue("no comparison card for the earlier session", card != null)
        card!!.performClick()

        val started = Shadows.shadowOf(activity).nextStartedActivity
        assertEquals(ResultsActivity::class.java.name, started.component?.className)
        val reopened = Robolectric.buildActivity(ResultsActivity::class.java, started).setup().get()
        assertEquals("8", reopened.findViewById<android.widget.TextView>(R.id.score).text.toString())

        reopened.finish()
        activity.finish()
        store.clear()
    }

    @Test
    fun `tapping a leaderboard row opens that session`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val attempt = Attempt(
            rounds = 9,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(attempt)
        val activity = Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        val root = activity.findViewById<android.view.View>(android.R.id.content)

        val row = findByDescriptionContains(root, "You, 9")
        assertTrue("no leaderboard row for the session", row != null)
        row!!.performClick()

        val started = Shadows.shadowOf(activity).nextStartedActivity
        assertEquals(ResultsActivity::class.java.name, started.component?.className)
        val reopened = Robolectric.buildActivity(ResultsActivity::class.java, started).setup().get()
        assertEquals("9", reopened.findViewById<android.widget.TextView>(R.id.score).text.toString())

        reopened.finish()
        store.clear()
    }

    @Test
    fun `tapping a day-sheet row opens that session and dismisses the sheet`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val attempt = Attempt(
            rounds = 11,
            reps = 0,
            atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L,
            profile = CindyProfile.STANDARD
        )
        store.add(attempt)
        val activity = Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        activity.openDay(java.time.LocalDate.now())
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)

        val row = findByDescriptionContains(dialog!!.window!!.decorView, "11 ·")
        assertTrue("no day-sheet row for the session", row != null)
        row!!.performClick()

        assertTrue("the sheet did not dismiss", !dialog.isShowing)
        val started = Shadows.shadowOf(activity).nextStartedActivity
        assertEquals(ResultsActivity::class.java.name, started.component?.className)
        val reopened = Robolectric.buildActivity(ResultsActivity::class.java, started).setup().get()
        assertEquals("11", reopened.findViewById<android.widget.TextView>(R.id.score).text.toString())

        reopened.finish()
        store.clear()
    }

    @Test
    fun `the chart's OPEN button opens the selected session`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val day = 24L * 60 * 60 * 1000
        val now = System.currentTimeMillis()
        val older = Attempt(
            rounds = 10, reps = 0, atMillis = now - day,
            durationMs = 20 * 60 * 1000L, profile = CindyProfile.STANDARD
        )
        val newer = Attempt(
            rounds = 12, reps = 0, atMillis = now,
            durationMs = 20 * 60 * 1000L, profile = CindyProfile.STANDARD
        )
        store.add(older)
        store.add(newer)
        val activity = Robolectric.buildActivity(RecordsActivity::class.java).setup().get()
        val root = activity.findViewById<android.view.View>(android.R.id.content)
        val chart = firstOfType<ProgressChartView>(root)
        assertTrue("no progress chart", chart != null)

        // The default metric (Score) sorts its points oldest first, so index 0 is `older`.
        chart!!.select(0)
        val openButton = findByText(root, "OPEN")
        assertTrue("no OPEN button after selecting a point", openButton != null)
        assertEquals(android.view.View.VISIBLE, openButton!!.visibility)
        openButton.performClick()

        val started = Shadows.shadowOf(activity).nextStartedActivity
        assertEquals(ResultsActivity::class.java.name, started.component?.className)
        val reopened = Robolectric.buildActivity(ResultsActivity::class.java, started).setup().get()
        assertEquals("10", reopened.findViewById<android.widget.TextView>(R.id.score).text.toString())

        reopened.finish()
        store.clear()
    }

    /** A full round with its sets banked, so there is something for the lifted card to count. */
    private fun liftedAttempt(profile: CindyProfile = CindyProfile.STANDARD) = Attempt(
        rounds = 1,
        reps = 0,
        atMillis = System.currentTimeMillis(),
        durationMs = 20 * 60 * 1000L,
        countedReps = 30,
        profile = profile,
        setSplits = listOf(
            SetSplit(Exercise.PULLUP, 14_000L, 5, 0),
            SetSplit(Exercise.PUSHUP, 17_000L, 10, 0),
            SetSplit(Exercise.SQUAT, 21_000L, 15, 0)
        )
    )

    /** With a weight on file the card says what was lifted and burned, as one TalkBack sentence. */
    @Test
    fun `the results screen shows what was lifted and burned once a weight is on file`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 80.0
        val attempt = liftedAttempt()
        store.add(attempt)

        val activity = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.intent(context, attempt, stoppedEarly = false)
        ).setup().get()
        val holder = activity.findViewById<android.view.ViewGroup>(R.id.lifted)

        assertEquals(android.view.View.VISIBLE, holder.visibility)
        val card = holder.getChildAt(0)
        val spoken = card.contentDescription.toString()
        // (5 x 0.95 + 10 x 0.64 + 15 x 0.88) x 80 = 1,948 kg, rounded to the nearest 10.
        assertTrue(spoken, spoken.contains("You lifted about 1,950 kg."))
        assertTrue(spoken, spoken.contains("You burned"))
        assertTrue(spoken, spoken.contains("An estimate from your weight"))
        assertTrue("card is one stop", card.isFocusable)

        activity.finish()
        store.clear()
        profile.bodyWeightKg = 0.0
    }

    /** Without one, a single row invites the athlete to enter it, and nothing is made up. */
    @Test
    fun `the results screen invites a weight rather than showing an empty card`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        Profile(context).bodyWeightKg = 0.0
        val attempt = liftedAttempt()
        store.add(attempt)

        val activity = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.intent(context, attempt, stoppedEarly = false)
        ).setup().get()
        val holder = activity.findViewById<android.view.ViewGroup>(R.id.lifted)

        assertEquals(android.view.View.VISIBLE, holder.visibility)
        assertTrue("no invitation", findByDescriptionPrefix(holder, "Your weight") != null)
        assertTrue("claims a lifted figure", findByDescriptionContains(holder, "You lifted") == null)

        activity.finish()
        store.clear()
    }

    /** An old record cannot say which movement its reps were, so only the burned half remains. */
    @Test
    fun `the results screen says nothing of what was lifted for an old record`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 80.0
        val old = Attempt(
            rounds = 2, reps = 0, atMillis = System.currentTimeMillis(),
            durationMs = 20 * 60 * 1000L, profile = CindyProfile.STANDARD
        )
        store.add(old)

        val activity = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.intent(context, old, stoppedEarly = false)
        ).setup().get()
        val holder = activity.findViewById<android.view.ViewGroup>(R.id.lifted)

        assertTrue("no energy card", findByDescriptionContains(holder, "You burned") != null)
        assertTrue("claims a lifted figure", findByDescriptionContains(holder, "You lifted") == null)

        activity.finish()
        store.clear()
        profile.bodyWeightKg = 0.0
    }

    /** Band-assisted pull-ups are named as left out, and the shares applied are the athlete's own. */
    @Test
    fun `the results screen names the movements it left out of what was lifted`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 80.0
        val attempt = liftedAttempt(CindyProfile(pull = PullVariant.BAND_ASSISTED_PULL_UP))
        store.add(attempt)

        val activity = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.intent(context, attempt, stoppedEarly = false)
        ).setup().get()
        val spoken = activity.findViewById<android.view.ViewGroup>(R.id.lifted)
            .getChildAt(0).contentDescription.toString()

        assertTrue(spoken, spoken.contains("Band-assisted pull-ups are left out"))
        assertTrue(spoken, !spoken.contains("strict pull-ups"))

        activity.finish()
        store.clear()
        profile.bodyWeightKg = 0.0
    }

    /** The same card draws when a past session is reopened. */
    @Test
    fun `a reopened session shows the lifted card too`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 80.0
        val attempt = liftedAttempt()
        store.add(attempt)

        val activity = Robolectric.buildActivity(
            ResultsActivity::class.java, ResultsActivity.review(context, attempt.atMillis)
        ).setup().get()

        assertTrue(
            "no lifted card on review",
            findByDescriptionContains(activity.findViewById(R.id.lifted), "You lifted") != null
        )

        activity.finish()
        store.clear()
        profile.bodyWeightKg = 0.0
    }

    /**
     * The animal row: as many of the animal as the count, five at most, and a "×N" beyond that.
     * The JVM has no emoji font, so the font check is told every glyph is available.
     */
    @Test
    fun `the lifted card draws the animal and its count when the phone can draw it`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        val profile = Profile(context)
        profile.bodyWeightKg = 80.0
        val attempt = liftedAttempt()
        store.add(attempt)
        ResultsActivity.glyphCheck = { true }
        try {
            val activity = Robolectric.buildActivity(
                ResultsActivity::class.java,
                ResultsActivity.intent(context, attempt, stoppedEarly = false)
            ).setup().get()
            val spoken = activity.findViewById<android.view.ViewGroup>(R.id.lifted)
                .getChildAt(0).contentDescription.toString()

            // 1,948 kg is 2.8 cows, 3.9 horses or 6.5 bears, whichever the day's rotation picked.
            assertTrue(spoken, spoken.contains("As heavy as "))
            val emojiViews = mutableListOf<android.widget.TextView>()
            fun walk(v: android.view.View) {
                if (v is android.widget.TextView && v.typeface == android.graphics.Typeface.DEFAULT) emojiViews += v
                if (v is android.view.ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
            }
            walk(activity.findViewById(R.id.lifted))
            // Three to five of the animal, plus the one beside the energy figure.
            assertTrue("emoji drawn: ${emojiViews.size}", emojiViews.size in 4..6)
            activity.finish()
        } finally {
            ResultsActivity.glyphCheck = null
            store.clear()
            profile.bodyWeightKg = 0.0
        }
    }

    // ── the round splits on the results page ───────────────────────────────────

    private fun launchResults(attempt: Attempt, vararg others: Attempt): android.app.Activity {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = RecordStore(context)
        store.clear()
        others.forEach { store.add(it) }
        store.add(attempt)
        val intent = ResultsActivity.intent(context, attempt, stoppedEarly = false)
        return Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()
    }

    private fun splitsAttempt(
        at: Long,
        splits: List<Long>,
        sets: List<SetSplit> = emptyList(),
        durationMs: Long = splits.sum(),
        counted: Int? = splits.size * 30
    ) = Attempt(
        rounds = splits.size, reps = 0, atMillis = at, durationMs = durationMs,
        roundSplitsMs = splits, setSplits = sets, countedReps = counted, profile = CindyProfile.STANDARD
    )

    private fun threeSets(pull: Long, push: Long, squat: Long) = listOf(
        SetSplit(Exercise.PULLUP, pull, 5, 0), SetSplit(Exercise.PUSHUP, push, 10, 0),
        SetSplit(Exercise.SQUAT, squat, 15, 0)
    )

    private fun text(activity: android.app.Activity, id: Int) =
        activity.findViewById<android.widget.TextView>(id).text.toString()

    @Test
    fun `the splits are stacked by movement when the sets were timed, and read out when chosen`() {
        val now = System.currentTimeMillis()
        val activity = launchResults(
            splitsAttempt(
                now, listOf(168_000L, 150_000L),
                threeSets(41_000L, 52_000L, 75_000L) + threeSets(40_000L, 50_000L, 60_000L)
            )
        )

        val view = activity.findViewById<RoundSplitsView>(R.id.splits)
        assertEquals(android.view.View.VISIBLE, activity.findViewById<android.view.View>(R.id.splitsCard).visibility)
        assertEquals(2, view.barCount)
        assertEquals("Fastest: round 2 at 2:30 · average 2:39", text(activity, R.id.splitsReadout))

        view.select(0)

        assertEquals("Round 1 · 2:48", text(activity, R.id.splitsReadout))
        assertEquals("Pull-ups 0:41 · push-ups 0:52 · squats 1:15", text(activity, R.id.splitsDetail))
        assertEquals(
            "no comparison, so no line for one",
            android.view.View.GONE, activity.findViewById<android.view.View>(R.id.splitsVersus).visibility
        )
        activity.finish()
    }

    /** A record from before set times existed has round splits and nothing else. */
    @Test
    fun `a very old record still draws plain bars and says it has no movement times`() {
        val activity = launchResults(
            splitsAttempt(System.currentTimeMillis(), listOf(168_000L, 150_000L, 160_000L), counted = null)
        )

        val view = activity.findViewById<RoundSplitsView>(R.id.splits)
        assertEquals(3, view.barCount)

        view.select(1)

        assertEquals("No per-movement times for this round", text(activity, R.id.splitsDetail))
        assertTrue(!text(activity, R.id.splitsNote).contains("stacks"))
        activity.finish()
    }

    @Test
    fun `no complete round hides the splits instead of charting nothing`() {
        val activity = launchResults(
            splitsAttempt(System.currentTimeMillis(), emptyList(), durationMs = 90_000L)
        )

        assertEquals(android.view.View.GONE, activity.findViewById<android.view.View>(R.id.splitsCard).visibility)
        assertEquals(android.view.View.GONE, activity.findViewById<android.view.View>(R.id.splitsTitle).visibility)
        activity.finish()
    }

    @Test
    fun `the round the clock stopped in is drawn as an open bar`() {
        val activity = launchResults(
            splitsAttempt(
                System.currentTimeMillis(), listOf(168_000L),
                threeSets(41_000L, 52_000L, 75_000L) + SetSplit(Exercise.PULLUP, 38_000L, 5, 0),
                durationMs = 248_000L, counted = 35
            )
        )

        val view = activity.findViewById<RoundSplitsView>(R.id.splits)
        assertEquals(2, view.barCount)

        view.select(1)

        assertEquals("Round 2 · 1:20 so far", text(activity, R.id.splitsReadout))
        assertTrue(text(activity, R.id.splitsDetail).startsWith("5 of 30 reps"))
        assertTrue(text(activity, R.id.splitsNote).contains("outlined bar"))
        activity.finish()
    }

    @Test
    fun `an earlier session adds a tick and a line against it, and the chip changes which`() {
        val now = System.currentTimeMillis()
        val day = 24 * 60 * 60 * 1000L
        val best = splitsAttempt(now - 3 * day, listOf(177_000L, 140_000L, 150_000L, 150_000L))
        val last = splitsAttempt(now - day, listOf(160_000L, 160_000L))
        val activity = launchResults(splitsAttempt(now, listOf(168_000L, 150_000L)), best, last)

        val view = activity.findViewById<RoundSplitsView>(R.id.splits)
        view.select(0)

        assertEquals("9 s faster than your best's round 1", text(activity, R.id.splitsVersus))
        assertTrue(text(activity, R.id.splitsNote).contains("in your best"))

        val chip = findByText(activity.findViewById(R.id.compare), "Last time")
        assertTrue("no Last time chip", chip != null)
        chip!!.performClick()

        // The selection survives the new comparison; the sentence is now about the other one.
        assertEquals(0, view.selected)
        assertEquals("8 s slower than round 1 last time", text(activity, R.id.splitsVersus))
        assertTrue(text(activity, R.id.splitsNote).contains("last time"))
        activity.finish()
    }
}
