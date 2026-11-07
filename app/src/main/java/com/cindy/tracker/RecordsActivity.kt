package com.cindy.tracker

import android.content.res.ColorStateList
import android.os.Bundle
import android.text.format.DateFormat
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityRecordsBinding
import java.text.SimpleDateFormat
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/** The record board: the benchmark to chase, then every attempt logged on this phone. */
class RecordsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRecordsBinding
    private lateinit var store: RecordStore
    /** The month the calendar is showing; the athlete can page back through it. */
    private var shownMonth: YearMonth = YearMonth.now()
    private var metric = ProgressMetric.SCORE
    private var range = ProgressRange.ALL
    /** The kind of Cindy the chart and the peaks are about; follows the latest until chosen. */
    private var category: CindyProfile? = null
    private var categoryChosen = false
    /** The board as it was last drawn, so [onResume] can tell whether it has changed since. */
    private var shownAttempts: List<Attempt> = emptyList()
    private lateinit var progressHolder: LinearLayout
    private lateinit var calendarHolder: LinearLayout
    private lateinit var leaderboardHolder: LinearLayout
    /** Whether the ranking shows every session instead of the top few. */
    private var leaderboardExpanded = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRecordsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        store = RecordStore(this)

        // Sessions are deleted one at a time, from their own page: there is deliberately no
        // button here that takes the whole board at once.
        render()
    }

    /**
     * Redraws when the board changed while this screen was waiting underneath another.
     *
     * A session's own page can discard it, and this screen is built from the board once, so
     * without this the calendar, the chart and the leaderboard would go on showing a session
     * that no longer exists. Compared rather than redrawn blindly, so coming back from nothing
     * more than a system dialog costs nothing.
     */
    override fun onResume() {
        super.onResume()
        if (store.all() != shownAttempts) render()
    }

    /** Reopens a saved attempt on the results screen, as it looked the day it happened. */
    private fun openSession(atMillis: Long) {
        startActivity(ResultsActivity.review(this, atMillis))
    }

    private fun render() {
        binding.rows.removeAllViews()
        val attempts = store.all()
        shownAttempts = attempts
        val today = LocalDate.now()
        val zone = ZoneId.systemDefault()
        val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        if (!categoryChosen || category !in Progress.categories(attempts)) {
            category = Progress.defaultCategory(attempts)
        }

        // How am I doing, first: the habit and the week in one card, then whether the score is
        // moving. What is only reference (the bests, the ranking, the calendar) follows.
        hero(attempts, today, zone, firstDay)
        progressCard(attempts, today, zone, firstDay)
        if (attempts.isNotEmpty()) peaks(attempts, today, zone, firstDay)
        leaderboard(attempts)
        if (attempts.isNotEmpty()) calendar(attempts, today, zone, firstDay)
    }

    /**
     * The athlete's sessions as a ranking, with the benchmark standing among them.
     *
     * Each row is a place: its rank, the day it was done and its score. Only the top
     * [LEADERBOARD_ROWS] sessions show at first, so that a long history stays a ranking and does
     * not become a log; the rest is one tap away, and the calendar reaches any one day.
     */
    private fun leaderboard(attempts: List<Attempt>) {
        binding.rows.addView(section("LEADERBOARD"))
        leaderboardHolder = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        binding.rows.addView(leaderboardHolder)
        renderLeaderboard(attempts)
    }

    /** Rebuilds only the ranking, so showing more rows does not scroll the page to the top. */
    private fun renderLeaderboard(attempts: List<Attempt>) {
        leaderboardHolder.removeAllViews()
        val standings = Records.standings(attempts)
        val ownRanked = standings.mapNotNull { it.attempt }

        if (ownRanked.isEmpty()) {
            leaderboardHolder.addView(insetGroup { row(benchmarkRow(1)) })
            leaderboardHolder.addView(styledText(
                R.style.Cindy_Footnote,
                "No attempts yet. Finish a 20-minute Cindy and it lands here."
            ).apply {
                gravity = Gravity.CENTER
                setPadding(0, dp(28), 0, 0)
            })
            return
        }

        val dateFormat = SimpleDateFormat("d MMM yyyy", Locale.US)
        val timeFormat = SimpleDateFormat(
            if (DateFormat.is24HourFormat(this)) "HH:mm" else "h:mm a", Locale.US
        )
        // Cut by place, benchmark included, so the athlete's top five always show whole.
        var sessionsShown = 0
        val shown = standings.filter { place ->
            if (leaderboardExpanded) return@filter true
            if (place.attempt == null) return@filter true
            sessionsShown++ < LEADERBOARD_ROWS
        }
        leaderboardHolder.addView(insetGroup {
            shown.forEach { place ->
                val a = place.attempt
                if (a == null) {
                    row(benchmarkRow(place.rank))
                } else {
                    row(rankRow(
                        rank = place.rank,
                        title = dateFormat.format(Date(a.atMillis)),
                        detail = listOfNotNull(
                            timeFormat.format(Date(a.atMillis)),
                            a.caption,
                            a.avgRoundMs?.let { "${formatDuration(it)}/round" }
                        ).joinToString(" · "),
                        score = a.scoreLabel(),
                        mine = true,
                        // "Best" means best at these movements. Across categories it would be
                        // comparing a band-assisted Cindy with a strict one and calling one better.
                        best = a == Records.bestIn(ownRanked, a.profile)
                    ) { openSession(a.atMillis) })
                }
            }
            if (ownRanked.size > LEADERBOARD_ROWS) {
                row(moreRow(
                    if (leaderboardExpanded) "Show the top $LEADERBOARD_ROWS"
                    else "Show all ${ownRanked.size} sessions"
                ) {
                    leaderboardExpanded = !leaderboardExpanded
                    renderLeaderboard(attempts)
                })
            }
        })
    }

    /** The row that opens or closes the rest of the ranking: a centred label, 56dp to hit. */
    private fun moreRow(label: String, onTap: () -> Unit): View =
        styledText(R.style.Cindy_Callout, label).apply {
            gravity = Gravity.CENTER
            minimumHeight = dp(56)
            foreground = rowRipple()
            setTextColor(getColor(R.color.label_secondary))
            setOnClickListener { onTap() }
            describeAsButton(label)
        }

    private fun benchmarkRow(rank: Int) = rankRow(
        rank = rank,
        title = Records.BENCHMARK_NAME,
        detail = "the benchmark · ${Records.BENCHMARK.totalReps} reps",
        score = Records.BENCHMARK.scoreLabel(),
        mine = false,
        best = false
    )

    private fun section(title: String) = eyebrow(title).apply {
        setPadding(dp(4), dp(10), 0, dp(10))
    }

    /** The glass card every block of the report sits on. */
    private fun card(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundResource(R.drawable.glass_card)
        setPadding(dp(20), dp(18), dp(20), dp(20))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(12) }
    }

    /**
     * The habit, rather than the scores: a line that is true today, both streaks, and which days
     * of this week were trained.
     *
     * The week strip earns its place over a number because the shape carries the information.
     */
    private fun hero(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDay: DayOfWeek
    ) {
        val card = card()
        card.addView(styledText(
            R.style.Cindy_Title2, Cheer.headline(attempts, today, zone, firstDay)
        ).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        })
        binding.rows.addView(card)
        if (attempts.isEmpty()) {
            card.addView(styledText(
                R.style.Cindy_Callout,
                "Finish a session and your streak, progress and peaks start here."
            ).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
                setPadding(0, dp(8), 0, 0)
            })
            return
        }

        val days = Streak.daysTrained(attempts, zone)
        val daily = Streak.current(days, today)
        val weeks = Streak.weeksTrained(days, firstDay)
        val weekly = Streak.currentWeeks(weeks, today, firstDay)

        card.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(16), 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            addView(streakColumn("DAILY STREAK", daily, if (daily == 1) "day" else "days", true))
            addView(streakColumn(
                "WEEKLY STREAK", weekly, if (weekly == 1) "week" else "weeks", false
            ))
        })

        card.addView(WeekStripView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(16) }
            show(Streak.weekStart(today, firstDay), days, today)
        })

        card.addView(View(this).apply {
            setBackgroundColor(getColor(R.color.hairline))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, hairlinePx()
            ).apply { topMargin = dp(16) }
        })
        thisWeek(card, attempts, today, zone, firstDay)
    }

    /**
     * One streak: its name, then the number. Read out as a single sentence, so TalkBack does not
     * announce "4", "days" and "daily streak" as three unrelated things.
     */
    private fun streakColumn(label: String, value: Int, unit: String, flame: Boolean): View =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            val name = label.lowercase(Locale.US).replaceFirstChar { it.uppercase() }
            contentDescription = "$name: $value $unit"
            isFocusable = true

            addView(eyebrow(label).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
            })
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(6), 0, 0)
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
                if (flame) {
                    addView(ImageView(context).apply {
                        setImageResource(R.drawable.ic_flame)
                        imageTintList = ColorStateList.valueOf(getColor(
                            if (value > 0) R.color.achievement else R.color.label_tertiary
                        ))
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                        layoutParams = LinearLayout.LayoutParams(dp(26), dp(26)).apply {
                            marginEnd = dp(6)
                        }
                    })
                }
                addView(styledText(R.style.Cindy_MetricL, "$value").apply {
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                })
                addView(styledText(R.style.Cindy_Headline, unit).apply {
                    setTextColor(getColor(R.color.label_secondary))
                    setPadding(dp(6), 0, 0, 0)
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                })
            })
            (0 until childCount).forEach {
                getChildAt(it).importantForAccessibility =
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
        }

    /** Sessions, reps and time this week against last, as the last block of the hero card. */
    private fun thisWeek(
        card: LinearLayout, attempts: List<Attempt>, today: LocalDate, zone: ZoneId,
        firstDay: DayOfWeek
    ) {
        val s = Progress.summary(attempts, today, zone, firstDay)
        val now = s.thisWeek
        val before = s.lastWeek
        card.addView(eyebrow("THIS WEEK").apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(16) }
        })
        card.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8) }
            addView(tile(
                "Sessions", "${now.sessions}", now.sessions - before.sessions, ""
            ))
            addView(tile(
                "Reps", Progress.formatReps(now.reps), now.reps - before.reps, ""
            ))
            addView(tile(
                "Time", Progress.formatClock(now.clockMs),
                ((now.clockMs - before.clockMs) / 60_000L).toInt(), " min"
            ))
        })
    }

    /** One figure of the week: label, value and, when it moved, the change since last week. */
    private fun tile(label: String, value: String, delta: Int, suffix: String): View =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            addView(styledText(R.style.Cindy_Footnote, label).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
            })
            addView(styledText(R.style.Cindy_MetricS, value).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(4) }
            })
            val change = Progress.formatDelta(delta)
            if (change != null) {
                addView(styledText(R.style.Cindy_Footnote, change + suffix).apply {
                    setTextColor(getColor(
                        if (delta > 0) R.color.state_ok else R.color.label_tertiary
                    ))
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
                    ).apply { topMargin = dp(2) }
                })
            }
            val versus = when {
                delta > 0 -> ", ${delta}$suffix more than last week"
                delta < 0 -> ", ${-delta}$suffix fewer than last week"
                else -> ""
            }
            contentDescription = "$label this week: $value$versus"
            isFocusable = true
            (0 until childCount).forEach {
                getChildAt(it).importantForAccessibility =
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
        }

    /** Personal bests in the chosen category; never across categories. */
    private fun peaks(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDay: DayOfWeek
    ) {
        val list = Peaks.of(attempts, category, today, zone, firstDay)
        if (list.isEmpty()) return
        binding.rows.addView(section("PEAKS"))
        binding.rows.addView(insetGroup {
            list.forEach { row(peakRow(it.rank, it.title, it.detail, it.value)) }
        })
        binding.rows.addView(styledText(
            R.style.Cindy_Footnote,
            "Scores and rounds are compared only with sessions at the same movements. " +
                "Streaks and weeks count everything."
        ).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(dp(4), dp(10), 0, dp(6))
        })
    }

    /**
     * The month grid, with arrows back through the athlete's history, and under it the totals
     * that are about the whole history rather than about this week.
     */
    private fun calendar(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDay: DayOfWeek
    ) {
        val days = Streak.daysTrained(attempts, zone)
        calendarHolder = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        binding.rows.addView(calendarHolder)
        renderCalendar(days, today, Streak.currentRun(days, today))

        val month = Progress.summary(attempts, today, zone, firstDay).thisMonth
        // What the next streak milestone costs lives here, with the days it counts, rather than
        // in the first card, where the headline above already says where the streak stands.
        val lines = listOfNotNull(
            Cheer.nextStep(attempts, today, zone, firstDay),
            "This month: ${month.sessions} session${if (month.sessions == 1) "" else "s"} · " +
                "${Progress.formatReps(month.reps)} reps · ${Progress.formatClock(month.clockMs)}",
            "${days.size} day${if (days.size == 1) "" else "s"} trained · " +
                "${attempts.size} session${if (attempts.size == 1) "" else "s"} in all"
        )
        binding.rows.addView(styledText(R.style.Cindy_Footnote, lines.joinToString("\n")).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(dp(4), dp(4), 0, dp(6))
        })
    }

    /**
     * Rebuilds only the calendar card, so paging months does not scroll the report back to the
     * top the way a full [render] would.
     */
    private fun renderCalendar(days: Set<LocalDate>, today: LocalDate, currentRun: Set<LocalDate>) {
        val earliest = days.minOrNull()?.let { YearMonth.from(it) } ?: YearMonth.from(today)
        val latest = YearMonth.from(today)
        if (shownMonth > latest) shownMonth = latest
        if (shownMonth < earliest) shownMonth = earliest
        calendarHolder.removeAllViews()

        calendarHolder.addView(LinearLayout(this).apply {
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
                    renderCalendar(days, today, currentRun)
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
                    renderCalendar(days, today, currentRun)
                })
            })

            addView(CalendarView(context).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(4) }
                show(shownMonth, days, today, currentRun)
                onDayTap = { openDay(it) }
            })
        })
    }

    /** The sessions of one trained day, oldest first, in a sheet. Nothing to show, no sheet. */
    internal fun openDay(date: LocalDate) {
        val zone = ZoneId.systemDefault()
        val sessions = store.all()
            .filter { Progress.localDate(it, zone) == date }
            .sortedBy { it.atMillis }
        if (sessions.isEmpty()) return

        val timeFormat = SimpleDateFormat(
            if (DateFormat.is24HourFormat(this)) "HH:mm" else "h:mm a", Locale.US
        )
        val title = DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.US).format(date)
        val subtitle = if (sessions.size == 1) "1 session" else "${sessions.size} sessions"
        val sheet = CindySheet(this, title, subtitle)
        // Each row opens its session and the sheet gets out of the way, rather than leaving the
        // athlete to dismiss a day they are no longer looking at.
        val group = insetGroup {
            sessions.forEach { a ->
                row(navRow(
                    timeFormat.format(Date(a.atMillis)),
                    "${a.scoreLabel()} \u00b7 ${a.caption}"
                ) {
                    sheet.dismiss()
                    openSession(a.atMillis)
                })
            }
        }
        group.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(16) }

        sheet.add(group)
            .actions(primary = "DONE", onPrimary = {})
            .show()
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

    /**
     * The chart card: what to plot, over how long, and (when more than one kind of Cindy has
     * been trained) which one. Needs two sessions before a line means anything.
     */
    private fun progressCard(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDay: DayOfWeek
    ) {
        if (attempts.size < 2) return
        progressHolder = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        binding.rows.addView(progressHolder)
        renderProgress(attempts, today, zone, firstDay)
    }

    /**
     * Rebuilds only the chart card, so flipping metric or range does not scroll the report back
     * to the top the way a full [render] would.
     */
    private fun renderProgress(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDay: DayOfWeek
    ) {
        progressHolder.removeAllViews()
        val from = range.start(today)
        val edge = DateTimeFormatter.ofPattern("d MMM", Locale.US)
        fun edgeLabel(millis: Long) = edge.format(Instant.ofEpochMilli(millis).atZone(zone))

        val series = when (metric) {
            ProgressMetric.SCORE -> Progress.scoreSeries(attempts, category, from, zone)
            ProgressMetric.PACE -> Progress.paceSeries(attempts, category, from, zone)
            ProgressMetric.VOLUME -> null
        }
        val points = series?.points
            ?: Progress.weeklyVolume(attempts, from, today, zone, firstDay)
        val overview = Progress.overview(metric, points)

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(16), dp(16), dp(16), dp(16))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        card.addView(chipRow(ProgressMetric.values().map { it.label }, metric.ordinal) {
            metric = ProgressMetric.values()[it]
            renderProgress(attempts, today, zone, firstDay)
        }.apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        })

        val headline = styledText(R.style.Cindy_Headline, overview.first).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        // Only a selected line point is one session; a bar is a week of them, and nothing
        // selected is the whole range, so the button only ever appears beside a point.
        val openButton = glassButton("OPEN").apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            visibility = View.GONE
        }
        card.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8) }
            addView(headline)
            addView(openButton)
        })
        val detail = styledText(R.style.Cindy_Footnote, overview.second).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        card.addView(detail)

        if (points.isEmpty()) {
            card.addView(styledText(R.style.Cindy_Footnote, "No sessions in this range").apply {
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(200)
                ).apply { topMargin = dp(8) }
            })
        } else {
            val chart = ProgressChartView(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(176)
                ).apply { topMargin = dp(8) }
            }
            val describe = { i: Int ->
                Progress.describe(metric, points, i, zone).let { "${it.first}. ${it.second}" }
            }
            if (series == null) {
                chart.showBars(
                    points,
                    edgeLabel(points.first().atMillis) to edgeLabel(points.last().atMillis),
                    { v -> Progress.formatReps(v.roundToInt()) },
                    describe
                )
            } else {
                val xStart = (from ?: Progress.localDate(points.first().attempt!!, zone))
                    .atStartOfDay(zone).toInstant().toEpochMilli()
                val xEnd = System.currentTimeMillis()
                chart.showLine(
                    points = points,
                    best = series.best,
                    xStart = xStart,
                    xEnd = xEnd,
                    invertY = metric == ProgressMetric.PACE,
                    edgeLabels = edgeLabel(xStart) to edgeLabel(xEnd),
                    axisLabel = { v ->
                        if (metric == ProgressMetric.PACE) formatDuration((v * 1000).toLong())
                        else "${v.roundToInt()}"
                    },
                    describe = describe
                )
            }
            chart.onSelect = { i ->
                val text = if (i == null) overview else Progress.describe(metric, points, i, zone)
                headline.text = text.first
                detail.text = text.second
                // A volume bar is a week, not a session, and series is null for exactly that mode.
                val at = i?.let { points[it].attempt?.atMillis }
                openButton.visibility = if (series != null && at != null) View.VISIBLE else View.GONE
                if (at != null) openButton.setOnClickListener { openSession(at) }
            }
            chart.contentDescription = "${metric.label} chart, ${overview.first}" +
                if (overview.second.isEmpty()) "" else ", ${overview.second}"
            card.addView(chart)
        }

        card.addView(chipRow(ProgressRange.values().map { it.label }, range.ordinal) {
            range = ProgressRange.values()[it]
            renderProgress(attempts, today, zone, firstDay)
        }.apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4) }
        })

        val categories = Progress.categories(attempts)
        if (categories.size > 1) {
            card.addView(HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
                addView(
                    chipRow(
                        categories.map { it?.label() ?: "Movements not recognised" },
                        categories.indexOf(category)
                    ) {
                        category = categories[it]
                        categoryChosen = true
                        render()    // the peaks follow the category
                    }.apply {
                        layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT
                        )
                    }
                )
            })
        }
        progressHolder.addView(card)

        progressHolder.addView(styledText(R.style.Cindy_Footnote, progressNote(attempts)).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(dp(4), dp(10), 0, dp(6))
        })
    }

    /** The line under the chart card: how the athlete has moved, or what the chart counts. */
    private fun progressNote(attempts: List<Attempt>): String = when (metric) {
        ProgressMetric.SCORE -> {
            val past = attempts.filter { it.profile == category }.sortedBy { it.atMillis }
            if (past.size < 2) {
                "${past.size} attempt${if (past.size == 1) "" else "s"} at these movements"
            } else {
                val delta = past.last().totalReps - past.first().totalReps
                "${past.size} attempts · " + when {
                    delta > 0 -> "up $delta reps since your first"
                    delta < 0 -> "${-delta} reps below your first"
                    else -> "level with your first"
                }
            }
        }
        ProgressMetric.PACE -> "Higher is faster. Full 20-minute sessions only."
        ProgressMetric.VOLUME -> "Every session counts toward volume, whatever the movements."
    }

    private companion object {
        /** How many of the athlete's own sessions the ranking shows until asked for the rest. */
        const val LEADERBOARD_ROWS = 5
    }
}
