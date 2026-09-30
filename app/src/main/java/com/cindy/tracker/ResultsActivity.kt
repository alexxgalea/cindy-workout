package com.cindy.tracker

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.work.WorkManager
import com.cindy.tracker.databinding.ActivityResultsBinding
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.roundToInt

/** What just happened: score, rank, pace, and how the rounds actually went. */
class ResultsActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_ATTEMPT = "attempt"
        private const val EXTRA_STOPPED = "stopped"
        private const val EXTRA_HEELS_FLAT = "heels_flat_spotted"

        /** The width of the icon at the start of a celebration row, so the text lines up. */
        private const val ICON_SLOT_DP = 36

        /** How many new badges are named; the rest are counted. */
        private const val MAX_BADGE_ROWS = 3

        /**
         * Carries the attempt in the record format, rather than a field per extra.
         *
         * Taking it apart into a dozen extras meant every new field had to be remembered in
         * three places, and [Attempt.countedReps] was remembered in two: it reached the record
         * board and was dropped on the way to this screen, where the missing value falls back to
         * `rounds * 30 + reps` — the inferred tally countedReps exists to replace. A session
         * with the pull-ups skipped was therefore *saved* as 25 reps and *shown* as 30, with the
         * voice saying the true number over a screen contradicting it.
         *
         * One encoder, already versioned and already round-trip tested, is what stops the next
         * field being forgotten. It also makes the screen show exactly what was filed.
         *
         * [heelsFlatSpotted] is the one fact the record cannot carry: that its movements were not
         * the ones the athlete chose but the ones smart squat counting switched to. The record
         * says what the session was filed as; this lets the screen say why.
         */
        fun intent(
            context: Context,
            a: Attempt,
            stoppedEarly: Boolean,
            heelsFlatSpotted: Boolean = false
        ): Intent =
            Intent(context, ResultsActivity::class.java).apply {
                putExtra(EXTRA_ATTEMPT, Records.encode(listOf(a)))
                putExtra(EXTRA_STOPPED, stoppedEarly)
                putExtra(EXTRA_HEELS_FLAT, heelsFlatSpotted)
            }
    }

    private lateinit var binding: ActivityResultsBinding
    private lateinit var profile: Profile
    private lateinit var attempt: Attempt
    private var stoppedEarly = false
    private var heelsFlatSpotted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityResultsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        profile = Profile(this)
        // Nothing to report on without one, and inventing an empty score to show instead would
        // be the same lie in a different place.
        attempt = Records.decode(intent.getStringExtra(EXTRA_ATTEMPT)).firstOrNull() ?: run {
            finish()
            return
        }
        stoppedEarly = intent.getBooleanExtra(EXTRA_STOPPED, false)
        heelsFlatSpotted = intent.getBooleanExtra(EXTRA_HEELS_FLAT, false)

        binding.actions.addView(glassButton("PROGRESS").apply {
            setOnClickListener { startActivity(Intent(this@ResultsActivity, RecordsActivity::class.java)) }
        })
        binding.actions.addView(primaryButton("DONE").apply {
            setOnClickListener { finish() }
        })
        render(attempt, stoppedEarly)
    }

    private fun render(a: Attempt, stopped: Boolean) {
        binding.headline.text = if (stopped) "STOPPED" else "TIME"

        // Rounds are the score; loose reps are a footnote on it, so they drop a weight and a
        // shade rather than sitting in the same 72sp as the number that matters.
        binding.score.text = "${a.rounds}"
        binding.scoreReps.visibility = if (a.reps > 0) View.VISIBLE else View.GONE
        if (a.reps > 0) binding.scoreReps.text = "+${a.reps}"

        // The record this score was actually chasing: the best previous attempt at the same
        // movements. Ranking it against a different prescription would flatter or insult it
        // depending only on which way the difficulty happened to fall.
        val all = RecordStore(this).all()
        val previousBest = Records.personalRecord(all, a)
        binding.scoreDetail.text = buildString {
            append("${a.totalReps} reps in ${formatDuration(a.durationMs)} of clock")
            if (a.pausedMs > 0L) append(" · ${formatDuration(a.realTimeMs)} real")
            if (Records.beatsBenchmark(a)) append("  ·  past ${Records.BENCHMARK_NAME}")
        }

        celebrate(a, all)
        renderLevel(a)

        binding.stats.removeAllViews()
        val group = InsetGroup(this)
        fun stat(label: String, value: CharSequence, onTap: (() -> Unit)? = null) =
            group.row(statRow(label, value, onTap))

        stat("Rounds completed", "${a.rounds}")
        stat("Workout time", formatDuration(a.durationMs))
        if (a.pausedMs > 0L) {
            // The clock stops when you pause; the day does not.
            stat("Paused", formatDuration(a.pausedMs))
            stat("Real time", formatDuration(a.realTimeMs))
        }
        a.avgRoundMs?.let { stat("Average round", formatDuration(it)) }
        a.fastestRoundMs?.let { stat("Fastest round", formatDuration(it)) }
        a.slowestRoundMs?.let { stat("Slowest round", formatDuration(it)) }
        stat("Total reps", "${a.totalReps}")
        // Said beside the score it explains. The athlete did not choose this label, and a record
        // that reads "Adaptive Cindy" with no word about why would look like a fault.
        if (heelsFlatSpotted) stat("Squats", "Heels flat · Adaptive Cindy") { explainHeelsFlat() }
        val zone = ZoneId.systemDefault()
        val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        val today = LocalDate.now()
        val days = Streak.daysTrained(all, zone)
        val streakDays = Streak.current(days, today)
        val streakWeeks = Streak.currentWeeks(Streak.weeksTrained(days, firstDay), today, firstDay)
        stat(
            "Streak",
            "$streakDays day${if (streakDays == 1) "" else "s"} · " +
                "$streakWeeks week${if (streakWeeks == 1) "" else "s"}"
        )
        // Said out loud rather than folded into the total: the app saw most of these and was
        // told about the rest, and those are different kinds of claim.
        if (a.manualReps > 0) stat("Added by hand", "${a.manualReps} of ${a.totalReps}")
        // Said plainly and next to the score it qualifies, rather than buried. A total the
        // camera could not stand behind is a floor, and the athlete is owed that distinction
        // here — where they are reading the number — not in a settings screen.
        if (a.untrackedMs > 0L) {
            stat("Camera lost you", formatDuration(a.untrackedMs))
            if (a.scoreIsLowerBound) stat("Score", "At least ${a.totalReps} — some reps may be missing")
        }
        energy(a, group)
        strava(a, group)
        previousBest?.let {
            val delta = a.totalReps - it.totalReps
            stat("Against your best", deltaText(it.scoreLabel(), delta))
        }
        binding.stats.addView(group)

        movementBreakdown(a)

        val splits = a.roundSplitsMs
        if (splits.isEmpty()) {
            binding.splitsTitle.visibility = View.GONE
            binding.splits.visibility = View.GONE
            binding.splitsNote.text = "No complete rounds to chart."
        } else {
            val fastest = splits.indexOf(splits.min())
            binding.splits.setValues(
                splits,
                highlightIndex = fastest,
                labels = splits.indices.map { "${it + 1}" },
                meanLabel = a.avgRoundMs?.let { "AVG ${formatDuration(it)}" }
            )
            // Taller is slower here, so say which way to read it.
            binding.splitsNote.text = buildString {
                append("Taller is slower. Fastest was round ${fastest + 1} at ${formatDuration(splits[fastest])}.")
                if (a.pausedMs > 0L) append(" Splits exclude paused time.")
            }
        }
    }

    /**
     * Where the round's time went, per movement. Hidden unless every movement has a finished set,
     * because a share of two movements would be a share of nothing. Cleared first because
     * [render] runs again when the body weight changes.
     */
    private fun movementBreakdown(a: Attempt) {
        binding.movements.removeAllViews()
        val shares = Progress.movementBreakdown(a)
        val show = if (shares.isEmpty()) View.GONE else View.VISIBLE
        binding.movementsTitle.visibility = show
        binding.movements.visibility = show
        if (shares.isEmpty()) return
        val group = InsetGroup(this)
        shares.forEach { s ->
            group.row(
                statRow(
                    s.label, "${formatDuration(s.avgMs)} · ${(s.share * 100).roundToInt()}%"
                )
            )
        }
        group.attach(styledText(
            R.style.Cindy_Footnote,
            "Average of each finished set. Set times include getting into position."
        ).apply {
            textSize = 11f
            setPadding(dp(18), 0, dp(18), dp(14))
        })
        binding.movements.addView(
            group,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }

    /**
     * The box under the score that says what this session earned: a first Cindy, a record, a
     * streak milestone, and the badges it won. Hidden when it earned nothing, rather than
     * congratulating an ordinary day. Cleared first because [render] runs again when the body
     * weight changes.
     *
     * The first row is the headline, whichever kind it is. The two lists can say the same thing
     * in different voices: a first session is also the First Cindy badge, and a streak milestone
     * is also a streak badge. That overlap is accepted rather than worked around, because every
     * row is true and keeping them apart would tie this box to the badge catalogue.
     */
    private fun celebrate(a: Attempt, all: List<Attempt>) {
        val box = binding.celebration
        box.removeAllViews()
        val zone = ZoneId.systemDefault()
        val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        val lines = Cheer.forResult(all, a, zone, firstDay)
        // Latest in the catalogue first. Within a family that is the hardest one earned, and the
        // badges of a first session sink to the bottom, where the line above already says so.
        val badges = Badges.earnedBy(all, a, zone, firstDay).sortedByDescending { it.ordinal }
        if (lines.isEmpty() && badges.isEmpty()) {
            box.visibility = View.GONE
            return
        }
        box.visibility = View.VISIBLE

        var rows = 0
        fun row(icon: View, text: String) {
            val headline = rows == 0
            box.addView(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                if (!headline) setPadding(0, dp(10), 0, 0)
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
                addView(icon)
                val style = if (headline) R.style.Cindy_Title2 else R.style.Cindy_Headline
                addView(styledText(style, text).apply {
                    if (headline) setTextColor(getColor(R.color.achievement))
                    layoutParams = LinearLayout.LayoutParams(
                        0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                    ).apply { marginStart = dp(12) }
                })
            })
            rows++
        }

        for (line in lines) {
            val trophy = line.kind == Celebration.Kind.FIRST || line.kind == Celebration.Kind.RECORD
            val icon = if (trophy) {
                medal(1)
            } else {
                ImageView(this).apply {
                    setImageResource(R.drawable.ic_flame)
                    imageTintList = ColorStateList.valueOf(getColor(R.color.achievement))
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }
            }
            row(slot(icon, 28), line.text)
        }
        for (badge in badges.take(MAX_BADGE_ROWS)) {
            row(slot(badgeDisc(badge, earned = true, sizeDp = 36), 36), "New badge: ${badge.title}")
        }
        if (badges.size > MAX_BADGE_ROWS) {
            box.addView(styledText(
                R.style.Cindy_Callout, "+${badges.size - MAX_BADGE_ROWS} more in your profile"
            ).apply {
                setTextColor(getColor(R.color.label_secondary))
                setPadding(dp(ICON_SLOT_DP + 12), dp(10), 0, 0)
            })
        }
    }

    /**
     * A fixed-width place for the icon at the start of a row, so that the text beside it lines up
     * whether the icon is a trophy, a flame or a badge.
     */
    private fun slot(icon: View, sizeDp: Int): View = FrameLayout(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            dp(ICON_SLOT_DP), ViewGroup.LayoutParams.WRAP_CONTENT
        )
        addView(icon, FrameLayout.LayoutParams(dp(sizeDp), dp(sizeDp), Gravity.CENTER))
    }

    /** "17  +22", with the delta green when it is one. Green is the affirmative everywhere. */
    private fun deltaText(score: String, delta: Int): CharSequence {
        val sign = if (delta >= 0) "+" else "−"
        val text = "$score  $sign${kotlin.math.abs(delta)}"
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(
                    getColor(if (delta >= 0) R.color.state_ok else R.color.label_tertiary)
                ),
                score.length + 2, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    /**
     * The ladder, or — for a session that did not run the standard movements — what it did run.
     *
     * The rungs are calibrated against strict Cindy and top out level with the benchmark, so
     * showing them here would be ranking an adaptive athlete on a workout they did not attempt.
     * That is not a demotion: the panel says what was performed and compares it with the same
     * thing done before, which is the only comparison that means anything.
     */
    private fun renderLevel(a: Attempt) {
        val level = a.level
        if (level != null) {
            binding.levelTitle.text = level.title
            binding.levelRung.text = "${level.ordinal + 1} of ${Level.entries.size}"
            binding.levelRung.visibility = View.VISIBLE
            binding.levelBlurb.text = level.blurb
            binding.levelProgress.visibility = View.VISIBLE
            binding.levelProgress.progress = (Level.progress(a.rounds) * 100).toInt()
            binding.levelNext.text = Level.roundsToNext(a.rounds)?.let { need ->
                "$need more round${if (need == 1) "" else "s"} to ${Level.next(level)?.title}"
            } ?: "Top of the ladder."
            return
        }
        val profile = a.profile
        binding.levelTitle.text = profile?.mode?.label ?: "Adaptive Cindy"
        binding.levelRung.visibility = View.GONE
        binding.levelBlurb.text = profile?.changedMovements()?.takeIf { it.isNotEmpty() }
            ?: "Movements this version does not recognise."
        // No rung, so no bar to fill: an empty progress bar would read as "no progress".
        binding.levelProgress.visibility = View.GONE
        binding.levelNext.text =
            "Ranked against your own sessions at these movements, not the strict ladder."
    }

    /**
     * The energy estimate, or an invitation to make one possible.
     *
     * Shown as an estimate either way, because that is what it is. Without a heart rate the
     * arithmetic is a MET table and the athlete's weight; where a watch was heard from during
     * this workout, the minutes it covered switch to the Keytel heart-rate equation instead, and
     * the footnote says exactly how much of the number came from which — a dropped connection
     * costs precision, never the figure itself. The row stays labelled "Calories (est.)" whatever
     * produced it: heart rate makes this a better estimate, not a measurement.
     */
    private fun energy(a: Attempt, group: InsetGroup) {
        val body = profile.body()
        val trace = HeartRateStore(this).load(a.atMillis)
        val est = Calories.estimate(a.totalReps, a.durationMs, body, trace)
        if (est == null) {
            group.row(statRow("Calories", "Set your weight") { askBodyWeight() })
            return
        }
        group.row(
            statRow("Calories (est.)", "${est.kcal} kcal") {
                // A trace was recorded but there is nothing yet to read it with — offer the
                // details that would unlock it rather than the weight prompt that already ran.
                if (trace != null && !body.canUseHeartRate) askHeartRateDetails() else askBodyWeight()
            }
        )
        val formula = when (body.sex) {
            Sex.FEMALE -> "female"
            Sex.MALE -> "male"
            Sex.UNSTATED, null -> "averaged"
        }
        val footnote = when {
            est.usedHeartRate && est.estimatedMs == 0L ->
                "From your heart rate across the whole workout · %.0f kg, %d, %s formula.".format(
                    Locale.US, body.weightKg, body.age!!, formula
                )
            est.usedHeartRate ->
                ("From your heart rate for ${formatDuration(est.heartRateMs)} of " +
                    "${formatDuration(a.durationMs)}; the other ${formatDuration(est.estimatedMs)} " +
                    "estimated from your reps at about %.1f METs · %.0f kg, %d, %s formula.").format(
                    Locale.US, est.met, body.weightKg, body.age!!, formula
                )
            trace != null && !body.canUseHeartRate ->
                ("Estimated from %.0f kg at about %.1f METs. Your heart rate was recorded — tap " +
                    "to add your age and sex and use it.").format(Locale.US, body.weightKg, est.met)
            else ->
                "Estimated from %.0f kg at about %.1f METs. Tap to change your weight."
                    .format(Locale.US, body.weightKg, est.met)
        }
        group.attach(styledText(R.style.Cindy_Footnote, footnote).apply {
            textSize = 11f
            setPadding(dp(18), 0, dp(18), dp(14))
        })
    }

    /**
     * Why this session says Adaptive Cindy when the athlete chose the standard movements, and a
     * way to make the change their own.
     *
     * The second half matters more than the first: smart squat counting is an experiment, and
     * the honest thing to do with its first guess is to say what it guessed and let the athlete
     * either keep it or not. The note names the one way it could have guessed wrong, which is a
     * camera that cannot see the knees bend.
     */
    private fun explainHeelsFlat() {
        CindySheet(
            this,
            title = "Adaptive Cindy activated",
            subtitle = "Your squats were heels flat, so after three of them Cindy switched this " +
                "session to Adaptive Cindy and counted every squat from then on, those three " +
                "included. It is ranked with your other heels-flat sessions."
        ).add(
            sheetNote(
                "If you were squatting to full depth, the camera may not be seeing your knees " +
                    "bend — stand side-on to the phone, or raise it. SET HEELS FLAT makes it " +
                    "your choice for every workout."
            )
        ).actions(
            primary = "SET HEELS FLAT",
            onPrimary = {
                profile.movements = profile.movements.copy(squat = SquatVariant.HEELS_FLAT)
                toast("Squats set to heels flat")
            },
            secondary = "NOT NOW",
            onSecondary = {}
        ).show()
    }

    /** Asks for body weight, and redraws whatever depended on it. Shared with [MenuActivity]. */
    private fun askBodyWeight() = askBodyWeight(profile) { render(attempt, stoppedEarly) }

    /** Asks for age and sex, and redraws whatever depended on them. Shared with [MenuActivity]. */
    private fun askHeartRateDetails() = askHeartRateDetails(profile) { render(attempt, stoppedEarly) }

    /**
     * What happened to this attempt's Strava upload, or an offer to start one.
     *
     * Hidden entirely when the build carries no Strava credentials — there is nothing honest
     * this row could say. Otherwise it stays live for as long as this screen is open: the
     * worker walks through its states on its own schedule, with no tap here to cause most of
     * them, so the row has to notice rather than only answer. Only this one row is rebuilt when
     * it does, not the whole screen.
     */
    private fun strava(a: Attempt, group: InsetGroup) {
        if (!StravaConfig.available) return
        val row = stravaRowView(a)
        stravaRow = row
        group.row(row)

        // Observed once for the life of the screen. [render] runs again whenever the body
        // weight changes, and each run builds a fresh group; an observer per run would pile up,
        // each one holding a group that is no longer on screen.
        if (stravaObserved) return
        stravaObserved = true
        WorkManager.getInstance(this)
            .getWorkInfosForUniqueWorkLiveData(StravaUploads.uniqueWorkName(a.atMillis))
            .observe(this) { refreshStravaRow(a) }
    }

    /** The row currently on screen, so a state change replaces it rather than adding another. */
    private var stravaRow: View? = null
    private var stravaObserved = false

    private fun stravaRowView(a: Attempt): View {
        val (value, onTap) = stravaRowContent(a, StravaTokenStore(this))
        return statRow("Strava", value, onTap)
    }

    private fun refreshStravaRow(a: Attempt) {
        val old = stravaRow ?: return
        val parent = old.parent as? ViewGroup ?: return
        val index = parent.indexOfChild(old)
        val updated = stravaRowView(a)
        parent.removeViewAt(index)
        parent.addView(updated, index, old.layoutParams)
        stravaRow = updated
    }

    /** The Strava row's value and tap action, for whichever state applies right now. */
    private fun stravaRowContent(a: Attempt, tokens: StravaTokenStore): Pair<String, (() -> Unit)?> {
        if (!tokens.connected) return "Connect to upload" to { connectFromResults(a.atMillis) }
        val status = StravaUploads.status(this, a.atMillis)
        return when (status?.state) {
            null -> "Upload" to { StravaUploads.enqueue(this, a.atMillis) }
            StravaUploadState.QUEUED, StravaUploadState.PROCESSING -> "Uploading…" to null
            StravaUploadState.DONE -> {
                val id = status.activityId
                if (id != null) "View activity ↗" to { openStravaActivity(id) } else "Uploaded" to null
            }
            StravaUploadState.FAILED ->
                "Couldn't upload — tap to retry" to { StravaUploads.enqueue(this, a.atMillis) }
            StravaUploadState.NEEDS_RECONNECT -> "Reconnect to upload" to { connectFromResults(a.atMillis) }
            StravaUploadState.UNAVAILABLE -> "Not available for this attempt" to null
        }
    }

    private fun openStravaActivity(activityId: Long) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(StravaApi.activityUrl(activityId))))
        } catch (e: ActivityNotFoundException) {
            toast("Opening the activity needs the Strava app or a web browser")
        }
    }

    /**
     * Starts OAuth for one particular attempt, rather than the menu's general connect.
     *
     * [StravaTokenStore.afterConnectUploadAtMillis] carries the request across the round trip
     * to Strava's consent page: [StravaAuthActivity] reads it back once the athlete returns,
     * uploads that attempt, and clears it.
     */
    private fun connectFromResults(atMillis: Long) {
        val tokens = StravaTokenStore(this)
        tokens.afterConnectUploadAtMillis = atMillis
        val state = StravaAuth.newState()
        tokens.pendingState = state
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(StravaAuth.authorizeUri(state))))
        } catch (e: ActivityNotFoundException) {
            tokens.pendingState = null
            tokens.afterConnectUploadAtMillis = null
            toast("Connecting needs the Strava app or a web browser")
        }
    }

    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
}
