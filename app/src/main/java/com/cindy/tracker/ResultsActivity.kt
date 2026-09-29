package com.cindy.tracker

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityResultsBinding
import java.util.Locale

/** What just happened: score, rank, pace, and how the rounds actually went. */
class ResultsActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_ATTEMPT = "attempt"
        private const val EXTRA_STOPPED = "stopped"

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
         */
        fun intent(context: Context, a: Attempt, stoppedEarly: Boolean): Intent =
            Intent(context, ResultsActivity::class.java).apply {
                putExtra(EXTRA_ATTEMPT, Records.encode(listOf(a)))
                putExtra(EXTRA_STOPPED, stoppedEarly)
            }
    }

    private lateinit var binding: ActivityResultsBinding
    private lateinit var profile: Profile
    private lateinit var attempt: Attempt
    private var stoppedEarly = false

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
        val previousBest = Records.personalRecord(RecordStore(this).all(), a)
        binding.scoreDetail.text = buildString {
            append("${a.totalReps} reps in ${formatDuration(a.durationMs)} of clock")
            if (a.pausedMs > 0L) append(" · ${formatDuration(a.realTimeMs)} real")
            if (Records.beatsBenchmark(a)) append("  ·  past ${Records.BENCHMARK_NAME}")
        }

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
        previousBest?.let {
            val delta = a.totalReps - it.totalReps
            stat("Against your best", deltaText(it.scoreLabel(), delta))
        }
        binding.stats.addView(group)

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
     * Shown as an estimate, because that is what it is: without a heart rate the arithmetic is a
     * MET table and the athlete's weight, and the answer carries real uncertainty. Saying so is
     * cheaper than being quietly wrong.
     */
    private fun energy(a: Attempt, group: InsetGroup) {
        val kcal = Calories.burned(a.totalReps, a.durationMs, profile.bodyWeightKg)
        if (kcal == null) {
            group.row(statRow("Calories", "Set your weight") { askBodyWeight() })
            return
        }
        val kg = profile.bodyWeightKg
        group.row(statRow("Calories (est.)", "$kcal kcal") { askBodyWeight() })
        group.attach(styledText(
            R.style.Cindy_Footnote,
            "Estimated from %.0f kg at about %.1f METs. Tap to change your weight."
                .format(Locale.US, kg, Calories.met(a.totalReps, a.durationMs))
        ).apply {
            textSize = 11f
            setPadding(dp(18), 0, dp(18), dp(14))
        })
    }

    /** Asks for body weight, and redraws whatever depended on it. Shared with [MenuActivity]. */
    private fun askBodyWeight() = askBodyWeight(profile) { render(attempt, stoppedEarly) }
}
