package com.cindy.tracker

import android.app.AlertDialog
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityRecordsBinding
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Date
import java.util.Locale

/** The record board: the benchmark to chase, then every attempt logged on this phone. */
class RecordsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRecordsBinding
    private lateinit var store: RecordStore
    /** The month the calendar is showing; the athlete can page back through it. */
    private var shownMonth: YearMonth = YearMonth.now()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRecordsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        store = RecordStore(this)

        binding.btnBack.setOnClickListener { finish() }
        binding.btnClear.setOnClickListener { confirmClear() }
        render()
    }

    private fun confirmClear() {
        if (store.all().isEmpty()) return
        AlertDialog.Builder(this)
            .setTitle("Clear your records?")
            .setMessage("Every attempt logged on this phone will be deleted. The benchmark stays.")
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Clear") { _, _ ->
                store.clear()
                render()
            }
            .show()
    }

    private fun render() {
        val rows = binding.rows
        rows.removeAllViews()

        streak()
        history()
        val mine = Records.ranked(store.all())
        val beaten = mine.firstOrNull()?.let { Records.beatsBenchmark(it) } == true

        rows.addView(
            row(
                rank = if (beaten) "2" else "1",
                name = Records.BENCHMARK_NAME,
                score = Records.BENCHMARK.scoreLabel(),
                detail = "the benchmark · ${Records.BENCHMARK.totalReps} reps",
                benchmark = true
            )
        )

        if (mine.isEmpty()) {
            rows.addView(empty())
            return
        }

        val dateFormat = SimpleDateFormat("d MMM yyyy", Locale.US)
        mine.forEachIndexed { i, a ->
            val outranks = Records.beatsBenchmark(a)
            rows.addView(
                row(
                    rank = if (outranks) "${i + 1}" else "${i + 2}",
                    // "Best" means best at these movements. Across categories it would be
                    // comparing a band-assisted Cindy with a strict one and calling one better.
                    name = if (a == Records.bestIn(mine, a.profile)) "You · best" else "You",
                    score = a.scoreLabel(),
                    detail = "${dateFormat.format(Date(a.atMillis))} · ${a.caption}" +
                        (a.avgRoundMs?.let { " · ${formatDuration(it)}/round" } ?: ""),
                    benchmark = false
                )
            )
        }
    }

    /**
     * The habit, rather than the scores: how many days in a row, and which days they were.
     *
     * A calendar earns its place over a number because the shape carries the information — a
     * streak is a run of filled cells and a fortnight off is a hole, neither of which "0 days"
     * tells you.
     */
    private fun streak() {
        val attempts = store.all()
        if (attempts.isEmpty()) return

        val today = LocalDate.now()
        val days = Streak.daysTrained(attempts, ZoneId.systemDefault())
        val current = Streak.current(days, today)
        val longest = Streak.longest(days)
        val atRisk = Streak.atRisk(days, today)

        binding.rows.addView(TextView(this).apply {
            text = "STREAK"
            letterSpacing = 0.12f
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 12f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, 0, 0, dp(8))
        })

        binding.rows.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.bg_row)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }

            addView(TextView(context).apply {
                text = if (current == 0) "No streak" else
                    "$current day${if (current == 1) "" else "s"}"
                setTextColor(getColor(R.color.accent))
                textSize = 28f
                typeface = android.graphics.Typeface.MONOSPACE
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            addView(TextView(context).apply {
                text = when {
                    // Said plainly, because it is the one fact that changes what they do today.
                    atRisk && current > 0 -> "Train today to keep it going."
                    current > 0 -> "Trained today. Longest: $longest."
                    longest > 0 -> "Longest was $longest day${if (longest == 1) "" else "s"}."
                    else -> ""
                }
                setTextColor(getColor(if (atRisk && current > 0) R.color.warn else R.color.on_surface_dim))
                textSize = 13f
                setPadding(0, dp(4), 0, 0)
            })
            addView(TextView(context).apply {
                text = "${days.size} day${if (days.size == 1) "" else "s"} trained · " +
                    "${attempts.size} attempt${if (attempts.size == 1) "" else "s"}"
                setTextColor(getColor(R.color.on_surface_dim))
                textSize = 12f
                setPadding(0, dp(8), 0, 0)
            })
        })

        calendar(days, today)
    }

    /** The month grid, with arrows back through the athlete's history. */
    private fun calendar(days: Set<LocalDate>, today: LocalDate) {
        val earliest = days.minOrNull()?.let { YearMonth.from(it) } ?: YearMonth.from(today)
        val latest = YearMonth.from(today)
        if (shownMonth > latest) shownMonth = latest
        if (shownMonth < earliest) shownMonth = earliest

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        header.addView(monthArrow("‹", enabled = shownMonth > earliest) {
            shownMonth = shownMonth.minusMonths(1)
            render()
        })
        header.addView(TextView(this).apply {
            text = "%s %d".format(
                Locale.getDefault(),
                shownMonth.month.getDisplayName(TextStyle.FULL, Locale.getDefault()),
                shownMonth.year
            )
            gravity = Gravity.CENTER
            setTextColor(getColor(R.color.on_surface))
            textSize = 15f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        })
        header.addView(monthArrow("›", enabled = shownMonth < latest) {
            shownMonth = shownMonth.plusMonths(1)
            render()
        })
        binding.rows.addView(header)

        binding.rows.addView(CalendarView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(18) }
            show(shownMonth, days, today)
        })
    }

    private fun monthArrow(glyph: String, enabled: Boolean, onTap: () -> Unit): TextView =
        TextView(this).apply {
            text = glyph
            gravity = Gravity.CENTER
            setTextColor(getColor(if (enabled) R.color.on_surface else R.color.on_surface_dim))
            alpha = if (enabled) 1f else 0.3f
            textSize = 22f
            // A 48dp target, because these are small glyphs on a screen used with wet hands.
            minWidth = dp(48)
            minHeight = dp(48)
            contentDescription = if (glyph == "‹") "Previous month" else "Next month"
            if (enabled) {
                isClickable = true
                setOnClickListener { onTap() }
            }
        }

    /** Score over time, oldest to newest, so progress is visible at a glance. */
    private fun history() {
        val past = store.chronological()
        if (past.size < 2) return

        binding.rows.addView(TextView(this).apply {
            text = "PROGRESS"
            letterSpacing = 0.12f
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 12f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, 0, 0, dp(8))
        })
        binding.rows.addView(SplitsChartView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(120)
            ).apply { bottomMargin = dp(6) }
            val best = past.indexOf(past.maxByOrNull { it.totalReps })
            setValues(past.map { it.totalReps.toLong() }, highlightIndex = best)
        })
        binding.rows.addView(TextView(this).apply {
            val first = past.first().totalReps
            val last = past.last().totalReps
            val delta = last - first
            text = "${past.size} attempts · " + when {
                delta > 0 -> "up $delta reps since your first"
                delta < 0 -> "${-delta} reps below your first"
                else -> "level with your first"
            }
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 12f
            setPadding(0, 0, 0, dp(18))
        })
    }

    private fun empty(): TextView = TextView(this).apply {
        text = "No attempts yet.\nFinish a 20-minute Cindy and it lands here."
        gravity = Gravity.CENTER
        setTextColor(getColor(R.color.on_surface_dim))
        textSize = 14f
        setPadding(0, dp(40), 0, 0)
    }

    private fun row(
        rank: String,
        name: String,
        score: String,
        detail: String,
        benchmark: Boolean
    ): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(if (benchmark) R.drawable.bg_row_benchmark else R.drawable.bg_row)
        setPadding(dp(16), dp(14), dp(16), dp(14))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(10) }

        addView(TextView(context).apply {
            text = rank
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 16f
            width = dp(28)
        })

        addView(LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            addView(TextView(context).apply {
                text = name
                setTextColor(getColor(R.color.on_surface))
                textSize = 17f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            addView(TextView(context).apply {
                text = detail
                setTextColor(getColor(R.color.on_surface_dim))
                textSize = 12f
            })
        })

        addView(TextView(context).apply {
            text = score
            setTextColor(getColor(if (benchmark) R.color.accent else R.color.on_surface))
            textSize = 26f
            typeface = android.graphics.Typeface.MONOSPACE
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        })
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
