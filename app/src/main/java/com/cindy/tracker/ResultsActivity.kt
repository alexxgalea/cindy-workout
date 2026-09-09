package com.cindy.tracker

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityResultsBinding
import java.util.Locale

/** What just happened: score, rank, pace, and how the rounds actually went. */
class ResultsActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_ROUNDS = "rounds"
        private const val EXTRA_REPS = "reps"
        private const val EXTRA_AT = "at"
        private const val EXTRA_DURATION = "duration"
        private const val EXTRA_PAUSED = "paused"
        private const val EXTRA_SPLITS = "splits"
        private const val EXTRA_STOPPED = "stopped"

        fun intent(context: Context, a: Attempt, stoppedEarly: Boolean): Intent =
            Intent(context, ResultsActivity::class.java).apply {
                putExtra(EXTRA_ROUNDS, a.rounds)
                putExtra(EXTRA_REPS, a.reps)
                putExtra(EXTRA_AT, a.atMillis)
                putExtra(EXTRA_DURATION, a.durationMs)
                putExtra(EXTRA_PAUSED, a.pausedMs)
                putExtra(EXTRA_SPLITS, a.roundSplitsMs.toLongArray())
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
        attempt = Attempt(
            rounds = intent.getIntExtra(EXTRA_ROUNDS, 0),
            reps = intent.getIntExtra(EXTRA_REPS, 0),
            atMillis = intent.getLongExtra(EXTRA_AT, System.currentTimeMillis()),
            durationMs = intent.getLongExtra(EXTRA_DURATION, 0L),
            pausedMs = intent.getLongExtra(EXTRA_PAUSED, 0L),
            roundSplitsMs = intent.getLongArrayExtra(EXTRA_SPLITS)?.toList() ?: emptyList()
        )
        stoppedEarly = intent.getBooleanExtra(EXTRA_STOPPED, false)

        binding.btnDone.setOnClickListener { finish() }
        binding.btnRecords.setOnClickListener {
            startActivity(Intent(this, RecordsActivity::class.java))
        }
        render(attempt, stoppedEarly)
    }

    private fun render(a: Attempt, stopped: Boolean) {
        binding.headline.text = if (stopped) "STOPPED" else "TIME"
        binding.score.text = a.scoreLabel()

        val previousBest = Records.best(RecordStore(this).all().filter { it.atMillis != a.atMillis })
        binding.scoreDetail.text = buildString {
            append("${a.totalReps} reps in ${formatDuration(a.durationMs)} of clock")
            if (a.pausedMs > 0L) append(" · ${formatDuration(a.realTimeMs)} real")
            if (Records.beatsBenchmark(a)) append("  ·  past ${Records.BENCHMARK_NAME}")
        }

        val level = a.level
        binding.levelTitle.text = level.title
        binding.levelBlurb.text = level.blurb
        binding.levelProgress.progress = (Level.progress(a.rounds) * 100).toInt()
        binding.levelNext.text = Level.roundsToNext(a.rounds)?.let { need ->
            "$need more round${if (need == 1) "" else "s"} to ${Level.next(level)?.title}"
        } ?: "Top of the ladder."

        binding.stats.removeAllViews()
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
        energy(a)
        previousBest?.let {
            val delta = a.totalReps - it.totalReps
            val sign = if (delta >= 0) "+" else ""
            stat("Against your best", "${it.scoreLabel()}  ($sign$delta reps)")
        }

        val splits = a.roundSplitsMs
        if (splits.isEmpty()) {
            binding.splitsTitle.visibility = android.view.View.GONE
            binding.splits.visibility = android.view.View.GONE
            binding.splitsNote.text = "No complete rounds to chart."
        } else {
            val fastest = splits.indexOf(splits.min())
            binding.splits.setValues(
                splits,
                highlightIndex = fastest,
                labels = splits.indices.map { "${it + 1}" }
            )
            // Taller is slower here, so say which way to read it.
            binding.splitsNote.text = buildString {
                append("Taller is slower. Fastest was round ${fastest + 1} at ${formatDuration(splits[fastest])}.")
                if (a.pausedMs > 0L) append(" Splits exclude paused time.")
            }
        }
    }

    /**
     * The energy estimate, or an invitation to make one possible.
     *
     * Shown as an estimate, because that is what it is: without a heart rate the arithmetic is a
     * MET table and the athlete's weight, and the answer carries real uncertainty. Saying so is
     * cheaper than being quietly wrong.
     */
    private fun energy(a: Attempt) {
        val kcal = Calories.burned(a.totalReps, a.durationMs, profile.bodyWeightKg)
        if (kcal == null) {
            stat("Calories", "set weight →") { askBodyWeight() }
            return
        }
        val kg = profile.bodyWeightKg
        stat("Calories (est.)", "$kcal kcal") { askBodyWeight() }
        binding.stats.addView(TextView(this).apply {
            text = "Estimated from %.0f kg at about %.1f METs. Tap to change your weight."
                .format(Locale.US, kg, Calories.met(a.totalReps, a.durationMs))
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 11f
            setPadding(0, 0, 0, dp(6))
        })
    }

    /** Asks for body weight in kilograms, and redraws whatever depended on it. */
    private fun askBodyWeight() {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            hint = "kg"
            if (profile.hasBodyWeight) {
                setText("%.0f".format(Locale.US, profile.bodyWeightKg))
            }
            setPadding(dp(24), dp(16), dp(24), dp(16))
        }
        AlertDialog.Builder(this)
            .setTitle("Your body weight")
            .setMessage(
                "Calories are estimated from body weight and how hard you worked. It stays on " +
                    "this phone."
            )
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Save") { _, _ ->
                val kg = input.text.toString().trim().toDoubleOrNull()
                if (kg == null || kg < Profile.MIN_KG || kg > Profile.MAX_KG) {
                    android.widget.Toast.makeText(
                        this,
                        "Enter a weight between ${Profile.MIN_KG.toInt()} and " +
                            "${Profile.MAX_KG.toInt()} kg",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                    return@setPositiveButton
                }
                profile.bodyWeightKg = kg
                render(attempt, stoppedEarly)
            }
            .show()
    }

    private fun stat(label: String, value: String, onTap: (() -> Unit)? = null) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(9), 0, dp(9))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            addView(TextView(context).apply {
                text = label
                setTextColor(getColor(R.color.on_surface_dim))
                textSize = 14f
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            })
            addView(TextView(context).apply {
                text = value
                setTextColor(getColor(if (onTap == null) R.color.on_surface else R.color.accent))
                textSize = 16f
                typeface = android.graphics.Typeface.MONOSPACE
            })
            onTap?.let { tap ->
                isClickable = true
                setOnClickListener { tap() }
                contentDescription = "$label, $value, tap to change"
            }
        }
        binding.stats.addView(row)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
