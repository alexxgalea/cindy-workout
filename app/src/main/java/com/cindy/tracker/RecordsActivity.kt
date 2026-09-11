package com.cindy.tracker

import android.content.res.ColorStateList
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
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

        binding.actions.addView(glassButton("CLEAR", R.color.state_alert).apply {
            setOnClickListener { confirmClear() }
        })
        binding.actions.addView(primaryButton("DONE").apply {
            setOnClickListener { finish() }
        })
        render()
    }

    /**
     * The one irreversible thing in the app, and it asks twice.
     *
     * A tester lost their history and the likeliest explanation was this button: the confirmation
     * put CLEAR in the *filled* slot, which on every other sheet in the app is where the safe,
     * expected action sits — and which is also where the thumb already is, having just tapped a
     * filled button to get here. Two taps in the same place wiped the board.
     *
     * So the sheet is built the other way round: KEEP THEM is the filled primary, so a reflex
     * second tap cancels; clearing is the quiet secondary, painted in the alert colour; and the
     * question names the number of sessions at stake, because "your records" is abstract in a way
     * that "41 sessions" is not. There is nothing to restore them from afterwards — the store is
     * one preference string — which is exactly why the ask is this loud.
     */
    private fun confirmClear() {
        val sessions = store.all().size
        if (sessions == 0) return
        CindySheet(
            this,
            title = if (sessions == 1) "Delete your 1 session?" else "Delete all $sessions sessions?",
            subtitle = "Every attempt logged on this phone goes, including your best. This " +
                "cannot be undone. The benchmark stays."
        ).actions(
            primary = "KEEP THEM",
            onPrimary = {},
            secondary = "DELETE",
            onSecondary = {
                store.clear()
                toast("Records cleared")
                render()
            },
            secondaryTint = R.color.state_alert
        ).show()
    }

    private fun toast(message: String) =
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

    private fun render() {
        val rows = binding.rows
        rows.removeAllViews()

        streak()
        history()

        val mine = Records.ranked(store.all())
        val beaten = mine.firstOrNull()?.let { Records.beatsBenchmark(it) } == true

        rows.addView(section("LEADERBOARD"))

        if (mine.isEmpty()) {
            rows.addView(insetGroup {
                row(benchmarkRow(if (beaten) "2" else "1"))
            })
            rows.addView(styledText(
                R.style.Cindy_Footnote,
                "No attempts yet. Finish a 20-minute Cindy and it lands here."
            ).apply {
                gravity = Gravity.CENTER
                setPadding(0, dp(28), 0, 0)
            })
            return
        }

        val dateFormat = SimpleDateFormat("d MMM yyyy", Locale.US)
        rows.addView(insetGroup {
            row(benchmarkRow(if (beaten) "2" else "1"))
            mine.forEachIndexed { i, a ->
                val outranks = Records.beatsBenchmark(a)
                row(rankRow(
                    rank = if (outranks) "${i + 1}" else "${i + 2}",
                    name = "You",
                    detail = "${dateFormat.format(Date(a.atMillis))} · ${a.caption}" +
                        (a.avgRoundMs?.let { " · ${formatDuration(it)}/round" } ?: ""),
                    score = a.scoreLabel(),
                    mine = true,
                    // "Best" means best at these movements. Across categories it would be
                    // comparing a band-assisted Cindy with a strict one and calling one better.
                    best = a == Records.bestIn(mine, a.profile)
                ))
            }
        })
    }

    private fun benchmarkRow(rank: String) = rankRow(
        rank = rank,
        name = Records.BENCHMARK_NAME,
        detail = "the benchmark · ${Records.BENCHMARK.totalReps} reps",
        score = Records.BENCHMARK.scoreLabel(),
        mine = false,
        best = false
    )

    private fun section(title: String) = eyebrow(title).apply {
        setPadding(dp(4), dp(10), 0, dp(10))
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

        binding.rows.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(20), dp(18), dp(20), dp(20))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(12) }

            addView(eyebrow("STREAK"))
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.BOTTOM
                setPadding(0, dp(8), 0, 0)
                addView(styledText(R.style.Cindy_MetricL, if (current == 0) "0" else "$current"))
                addView(styledText(
                    R.style.Cindy_Title2,
                    if (current == 1) "day" else "days"
                ).apply {
                    setTextColor(getColor(R.color.label_secondary))
                    setPadding(dp(7), 0, 0, dp(4))
                })
            })
            addView(styledText(R.style.Cindy_Callout, when {
                // Said plainly, because it is the one fact that changes what they do today.
                atRisk && current > 0 -> "Train today to keep it going."
                current > 0 -> "Trained today. Longest: $longest."
                longest > 0 -> "Longest was $longest day${if (longest == 1) "" else "s"}."
                else -> "No streak yet."
            }).apply {
                if (atRisk && current > 0) setTextColor(getColor(R.color.state_alert))
                setPadding(0, dp(8), 0, 0)
            })
            addView(View(context).apply {
                setBackgroundColor(getColor(R.color.hairline))
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, hairlinePx()
                ).apply { topMargin = dp(14) }
            })
            addView(styledText(
                R.style.Cindy_Footnote,
                "${days.size} day${if (days.size == 1) "" else "s"} trained · " +
                    "${attempts.size} attempt${if (attempts.size == 1) "" else "s"}"
            ).apply { setPadding(0, dp(13), 0, 0) })
        })

        calendar(days, today)
    }

    /** The month grid, with arrows back through the athlete's history. */
    private fun calendar(days: Set<LocalDate>, today: LocalDate) {
        val earliest = days.minOrNull()?.let { YearMonth.from(it) } ?: YearMonth.from(today)
        val latest = YearMonth.from(today)
        if (shownMonth > latest) shownMonth = latest
        if (shownMonth < earliest) shownMonth = earliest

        binding.rows.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(16), dp(12), dp(16), dp(16))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(12) }

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(monthArrow(R.drawable.ic_chevron_left, shownMonth > earliest) {
                    shownMonth = shownMonth.minusMonths(1)
                    render()
                })
                addView(styledText(R.style.Cindy_Headline, "%s %d".format(
                    Locale.getDefault(),
                    shownMonth.month.getDisplayName(TextStyle.FULL, Locale.getDefault()),
                    shownMonth.year
                )).apply {
                    gravity = Gravity.CENTER
                    layoutParams = LinearLayout.LayoutParams(
                        0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                    )
                })
                addView(monthArrow(R.drawable.ic_chevron_right, shownMonth < latest) {
                    shownMonth = shownMonth.plusMonths(1)
                    render()
                })
            })

            addView(CalendarView(context).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(4) }
                show(shownMonth, days, today)
            })
        })
    }

    /** A 48dp target, because these are small glyphs on a screen used with wet hands. */
    private fun monthArrow(icon: Int, enabled: Boolean, onTap: () -> Unit): ImageView =
        ImageView(this).apply {
            setImageResource(icon)
            imageTintList = ColorStateList.valueOf(
                getColor(if (enabled) R.color.label_secondary else R.color.label_quaternary)
            )
            setPadding(dp(15), dp(15), dp(15), dp(15))
            layoutParams = LinearLayout.LayoutParams(dp(46), dp(46))
            contentDescription =
                if (icon == R.drawable.ic_chevron_left) "Previous month" else "Next month"
            if (enabled) {
                setOnClickListener { onTap() }
                describeAsButton()
            } else {
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
        }

    /** Score over time, oldest to newest, so progress is visible at a glance. */
    private fun history() {
        val past = store.chronological()
        if (past.size < 2) return

        binding.rows.addView(section("PROGRESS"))
        binding.rows.addView(SplitsChartView(this).apply {
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(16), dp(16), dp(16), dp(16))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(150)
            )
            val best = past.indexOf(past.maxByOrNull { it.totalReps })
            setValues(
                past.map { it.totalReps.toLong() },
                highlightIndex = best,
                meanLabel = "AVG ${past.sumOf { it.totalReps } / past.size}"
            )
        })
        binding.rows.addView(styledText(R.style.Cindy_Footnote, buildString {
            val delta = past.last().totalReps - past.first().totalReps
            append("${past.size} attempts · ")
            append(when {
                delta > 0 -> "up $delta reps since your first"
                delta < 0 -> "${-delta} reps below your first"
                else -> "level with your first"
            })
        }).apply { setPadding(dp(4), dp(10), 0, dp(6)) })
    }
}
