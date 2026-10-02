package com.cindy.tracker

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.format.DateFormat
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.work.WorkManager
import com.cindy.tracker.databinding.ActivityResultsBinding
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.WeekFields
import java.util.Date
import java.util.Locale

/** What just happened: score, rank, pace, and how the rounds actually went. */
class ResultsActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_ATTEMPT = "attempt"
        private const val EXTRA_STOPPED = "stopped"
        private const val EXTRA_HEELS_FLAT = "heels_flat_spotted"
        private const val EXTRA_REVIEW_AT = "review_at"

        /**
         * Stands in for the font check when set. The JVM test environment has no emoji font and
         * answers "no glyph" to every question, which would leave the animal row untestable.
         */
        internal var glyphCheck: ((String) -> Boolean)? = null

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

        /**
         * Reopens a session already on the record board — from the leaderboard, a day in the
         * calendar, or a selected point on the progress chart — rather than the one a workout
         * just finished with.
         *
         * [atMillis] is the key [RecordStore] already files the attempt under, so there is
         * nothing of its own to encode: the session is read back by it in [onCreate]. A
         * timestamp nothing on the board matches — the board was cleared while this intent was
         * already in flight — finishes rather than showing an empty page.
         */
        fun review(context: Context, atMillis: Long): Intent =
            Intent(context, ResultsActivity::class.java).apply {
                putExtra(EXTRA_REVIEW_AT, atMillis)
            }
    }

    private lateinit var binding: ActivityResultsBinding
    private lateinit var profile: Profile
    private lateinit var attempt: Attempt
    private var stoppedEarly = false
    private var heelsFlatSpotted = false
    /** True once this screen is reopening a saved session rather than ending a live one. */
    private var reviewing = false
    /** What this session is measured against; the one field later sections also hang off. */
    private var comparison: Attempt? = null
    private lateinit var compareCardHolder: FrameLayout
    /** The round splits on screen, kept so a new comparison can redraw them without a rebuild. */
    private var splitData: RoundSplits.Split? = null
    private var comparisonKind: Comparisons.Kind? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityResultsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        profile = Profile(this)
        reviewing = intent.hasExtra(EXTRA_REVIEW_AT)
        attempt = if (reviewing) {
            val atMillis = intent.getLongExtra(EXTRA_REVIEW_AT, -1L)
            RecordStore(this).all().firstOrNull { it.atMillis == atMillis } ?: run {
                finish()
                return
            }
        } else {
            // Nothing to report on without one, and inventing an empty score to show instead
            // would be the same lie in a different place.
            Records.decode(intent.getStringExtra(EXTRA_ATTEMPT)).firstOrNull() ?: run {
                finish()
                return
            }
        }
        // Neither extra exists on a review intent; reading them without the guard would answer
        // with their defaults anyway, but saying so here is the honest version of that accident.
        stoppedEarly = !reviewing && intent.getBooleanExtra(EXTRA_STOPPED, false)
        heelsFlatSpotted = !reviewing && intent.getBooleanExtra(EXTRA_HEELS_FLAT, false)

        if (reviewing) {
            // Reopened from Progress, which is where this came from — PROGRESS would be a way
            // back to a page already behind this one.
            binding.actions.addView(primaryButton("DONE").apply {
                setOnClickListener { finish() }
            })
        } else {
            binding.actions.addView(glassButton("PROGRESS").apply {
                setOnClickListener { startActivity(Intent(this@ResultsActivity, RecordsActivity::class.java)) }
            })
            binding.actions.addView(primaryButton("DONE").apply {
                setOnClickListener { finish() }
            })
        }
        render(attempt, stoppedEarly)
    }

    private fun render(a: Attempt, stopped: Boolean) {
        val zone = ZoneId.systemDefault()
        binding.headline.text = when {
            reviewing -> reviewHeadline(a, zone)
            stopped -> "STOPPED"
            else -> "TIME"
        }

        // Rounds are the score; loose reps are a footnote on it, so they drop a weight and a
        // shade rather than sitting in the same 72sp as the number that matters.
        binding.score.text = "${a.rounds}"
        binding.scoreReps.visibility = if (a.reps > 0) View.VISIBLE else View.GONE
        if (a.reps > 0) binding.scoreReps.text = "+${a.reps}"

        // Sessions this one could honestly be measured against: in review, only what had
        // already happened — so reopening an old session cannot be credited with a celebration,
        // a record or a comparison that later sessions, not this one, actually earned. After a
        // workout [a] is always the latest attempt on the board, so this changes nothing there.
        val all = RecordStore(this).all().filter { it.atMillis <= a.atMillis }
        binding.scoreDetail.text = buildString {
            append("${a.totalReps} reps in ${formatDuration(a.durationMs)} of clock")
            if (a.pausedMs > 0L) append(" · ${formatDuration(a.realTimeMs)} real")
            if (Records.beatsBenchmark(a)) append("  ·  past ${Records.BENCHMARK_NAME}")
        }

        celebrate(a, all)
        sessionNumbers(a)
        renderLevel(a)
        liftedCard(a)
        compareCard(a, all)

        binding.stats.removeAllViews()
        val group = InsetGroup(this)
        fun stat(label: String, value: CharSequence, onTap: (() -> Unit)? = null) =
            group.row(statRow(label, value, onTap))

        if (a.pausedMs > 0L) {
            // The clock stops when you pause; the day does not.
            stat("Paused", formatDuration(a.pausedMs))
            stat("Real time", formatDuration(a.realTimeMs))
        }
        // Said beside the score it explains. The athlete did not choose this label, and a record
        // that reads "Adaptive Cindy" with no word about why would look like a fault.
        if (heelsFlatSpotted) stat("Squats", "Heels flat · Adaptive Cindy") { explainHeelsFlat() }
        // A streak describes today, which a session reopened from another day is not.
        if (!reviewing) {
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
        }
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
        binding.stats.addView(group)

        roundSplits(a)
    }

    /**
     * Where each round's time went. Hidden when there is no complete round, because a bar of
     * nothing says nothing. Built again, whole, every time [render] runs, which is what the body
     * weight prompt triggers; the comparison ticks are the one part that changes without it.
     */
    private fun roundSplits(a: Attempt) {
        val split = RoundSplits.of(a)
        splitData = split
        if (split == null) {
            binding.splitsTitle.visibility = View.GONE
            binding.splitsCard.visibility = View.GONE
            binding.splitsNote.text = "No complete rounds to chart."
            return
        }
        binding.splitsTitle.visibility = View.VISIBLE
        binding.splitsCard.visibility = View.VISIBLE
        binding.splits.onSelect = { showSplitReadout(it) }
        binding.splits.show(
            split.bars, split.fastest, split.averageMs, "AVG ${formatDuration(split.averageMs)}"
        ) { i -> RoundSplits.readout(a, split, i, comparison, comparisonKind).spoken() }
        // The comparison was chosen before this ran, so the ticks, the note and the readout are
        // all drawn against it here, the same way a later chip tap redraws them.
        splitsComparison()
    }

    /**
     * Redraws what the round splits take from [comparison]: the tick over each bar, the readout
     * and the note under the chart. A no-op until the splits themselves have been built.
     */
    private fun splitsComparison() {
        val split = splitData ?: return
        val reference = comparison
        // Which sentence "your best's round 5" or "round 5 last time" is: worked out once here,
        // not per scrub step, because it reads the record board.
        comparisonKind = reference?.let {
            if (Comparisons.best(RecordStore(this).all(), attempt)?.atMillis == it.atMillis) {
                Comparisons.Kind.BEST
            } else {
                Comparisons.Kind.LAST
            }
        }
        val ticks = RoundSplits.reference(split, reference)
        binding.splits.setReference(ticks)

        val fastest = split.bars[split.fastest]
        // Taller is slower here, so say which way to read it.
        binding.splitsNote.text = buildString {
            append("Taller is slower. Fastest was round ${fastest.round} at ${formatDuration(fastest.ms)}.")
            if (attempt.pausedMs > 0L) append(" Splits exclude paused time.")
            if (split.hasBreakdown) {
                val names = RoundSplits.movementNames(attempt.profile)
                append(" Each bar stacks ${names[0]}, ${names[1]} and ${names[2]}, bottom to top.")
            }
            if (ticks.any { it != null }) {
                append(
                    if (comparisonKind == Comparisons.Kind.LAST) {
                        " The tick over each bar marks the same round last time."
                    } else {
                        " The tick over each bar marks the same round in your best."
                    }
                )
            }
            if (split.hasUnfinished) append(" The outlined bar is the round still under way when the clock stopped.")
        }
        showSplitReadout(binding.splits.selected)
    }

    /** The line above the splits for bar [selected], or the fastest and the average for none. */
    private fun showSplitReadout(selected: Int?) {
        val split = splitData ?: return
        val reading = RoundSplits.readout(attempt, split, selected, comparison, comparisonKind)
        binding.splitsReadout.text = reading.title
        binding.splitsDetail.text = reading.detail
        // Invisible, not gone, while a comparison exists: a line that comes and goes as the
        // finger crosses a round the comparison never played would move the chart under it.
        val versus = reading.versus
        binding.splitsVersus.visibility = when {
            comparison == null -> View.GONE
            versus == null -> View.INVISIBLE
            else -> View.VISIBLE
        }
        binding.splitsVersus.text = versus?.text.orEmpty()
        binding.splitsVersus.setTextColor(
            getColor(if (versus?.faster == true) R.color.state_ok else R.color.label_secondary)
        )
    }

    /**
     * Whether this phone can actually draw [emoji]. Asked of the same typeface the emoji are drawn
     * with, so a "yes" here is a promise about the card and not about some other font: the oldest
     * phone this app runs on (API 26) predates the hippo, and an empty box in its place would be
     * worse than a different animal.
     */
    private val emojiPaint = Paint().apply { typeface = Typeface.DEFAULT }

    private fun canDraw(emoji: String): Boolean =
        glyphCheck?.invoke(emoji) ?: emojiPaint.hasGlyph(emoji)

    /**
     * What the session lifted and burned, as an animal and a cup of tea: one card between the
     * level and the comparison, or, with no body weight on file, one row inviting the athlete to
     * enter it. Hidden when there is nothing to say. Cleared first because [render] runs again
     * when the body weight changes, which is also what turns the invitation into the card.
     *
     * Both figures are estimates and the footnote says how each was reached. The animal is picked
     * by the day the session happened, not today, so reopening it shows the animal it showed
     * the first time.
     */
    private fun liftedCard(a: Attempt) {
        val holder = binding.lifted
        holder.removeAllViews()
        val lifted = Lifted.of(a, profile.bodyWeightKg)
        // The same call, with the same inputs, as the energy row under SESSION: this card must
        // never disagree with the number it sits above.
        val est = Calories.estimate(
            a.totalReps, a.durationMs, profile.body(), HeartRateStore(this).load(a.atMillis)
        )
        if (lifted == null && est == null) {
            val invite = !profile.hasBodyWeight && (a.durationMs > 0L || Lifted.measurable(a))
            holder.visibility = if (invite) View.VISIBLE else View.GONE
            if (invite) {
                holder.addView(
                    InsetGroup(this).apply {
                        row(navRow("Your weight", "Add it to see what you lifted and burned") {
                            askBodyWeight()
                        })
                    },
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
            }
            return
        }
        holder.visibility = View.VISIBLE

        val rotation = Instant.ofEpochMilli(a.atMillis).atZone(ZoneId.systemDefault())
            .toLocalDate().toEpochDay()
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(20), dp(18), dp(20), dp(18))
            // One sentence for the whole card: its parts are hidden below, and the emoji, which
            // a screen reader would otherwise name one by one, are never announced on their own.
            isFocusable = true
        }
        // The card is one TalkBack stop, so every child leaves the accessibility tree.
        fun add(view: View, topDp: Int = 0): View {
            view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            card.addView(
                view,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(topDp) }
            )
            return view
        }
        val spoken = mutableListOf<String>()

        if (lifted != null) {
            add(eyebrow("YOU LIFTED"))
            val match = Equivalents.animalFor(lifted.totalKg, rotation, ::canDraw)
            if (match != null) add(animalRow(match), topDp = 12)
            add(figure(lifted.kgPrefix, lifted.kgNumber, "kg"), topDp = if (match != null) 8 else 10)
            spoken += "You lifted ${lifted.kgText().replaceFirstChar { it.lowercase() }}."
            if (match != null) {
                val sentence = Equivalents.heavySentence(match, lifted.atLeast)
                add(styledText(R.style.Cindy_Body, sentence), topDp = 2)
                spoken += sentence
            }
        }

        var energyMethod: String? = null
        if (est != null) {
            if (lifted != null) {
                add(View(this).apply { setBackgroundColor(getColor(R.color.hairline)) }, topDp = 18)
                    .layoutParams.height = hairlinePx()
            }
            add(eyebrow("YOU BURNED"), topDp = if (lifted != null) 18 else 0)
            val match = Equivalents.energyFor(est.kcal.toDouble(), rotation, ::canDraw)
            val prefix = if (a.scoreIsLowerBound) "At least" else null
            val figure = figure(prefix, "${est.kcal}", "kcal")
            if (match == null) {
                add(figure, topDp = 10)
            } else {
                // The emoji sits at the end of the figure's line, so the sentence under it keeps
                // the full width of the card.
                add(LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(figure, LinearLayout.LayoutParams(
                        0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                    ))
                    addView(emoji(match.reference.emoji, sp = 28f))
                }, topDp = 10)
            }
            spoken += "You burned ${if (prefix != null) "at least " else ""}${est.kcal} kcal."
            if (match != null) {
                val sentence = match.reference.sentence(match.count, a.scoreIsLowerBound)
                add(styledText(R.style.Cindy_Body, sentence), topDp = 2)
                spoken += sentence
                energyMethod = match.reference.method
            }
        }

        val note = listOfNotNull(
            lifted?.footnote(tappedIn = a.manualReps > 0),
            // The energy figure is the one the calories row already explains; this only points at it.
            if (est != null) {
                buildString {
                    append("Energy is the same estimate as the calories row below.")
                    energyMethod?.let { append(" $it") }
                    if (lifted == null && a.scoreIsLowerBound) {
                        append(" The camera lost you for part of this session, so this is a floor.")
                    }
                }
            } else null
        ).joinToString(" ")
        add(styledText(R.style.Cindy_Footnote, note), topDp = 16)
        spoken += note

        card.contentDescription = spoken.joinToString(" ")
        holder.addView(
            card,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }

    /** One animal's emoji, up to [Equivalents.MAX_EMOJI], and a "×9" when there are more of it. */
    private fun animalRow(match: Equivalents.AnimalMatch): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        repeat(Equivalents.emojiCount(match.count)) { addView(emoji(match.animal.emoji, sp = 36f)) }
        if (match.count.roundToInt() > Equivalents.MAX_EMOJI) {
            addView(
                styledText(R.style.Cindy_MetricS, "×${match.count.roundToInt()}").apply {
                    setTextColor(getColor(R.color.label_secondary))
                }.withStartMargin(dp(10))
            )
        }
    }

    /**
     * An emoji, in the system's own typeface and full colour. This card is the one place in the
     * app that has colour beyond the accent, deliberately: an animal in monochrome is a glyph.
     */
    private fun emoji(text: String, sp: Float): TextView = TextView(this).apply {
        this.text = text
        typeface = Typeface.DEFAULT
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        includeFontPadding = false
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { marginEnd = dp(4) }
    }

    /**
     * A big figure with a small word either side: "About **12,940** kg". The qualifier and the
     * unit drop to half size and a shade, so the number is what the eye lands on.
     */
    private fun figure(prefix: String?, number: String, unit: String): TextView {
        val text = SpannableStringBuilder()
        fun small(word: String) {
            val start = text.length
            text.append(word)
            text.setSpan(RelativeSizeSpan(0.5f), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            text.setSpan(
                ForegroundColorSpan(getColor(R.color.label_secondary)),
                start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        if (prefix != null) small("$prefix ")
        text.append(number)
        small(" $unit")
        return styledText(R.style.Cindy_MetricM, text).apply { maxLines = 2 }
    }

    /**
     * The session in numbers, right under the score: six tiles, a pill per round, and what each
     * movement came to. Each part is hidden when the record cannot give it, rather than drawn
     * empty: the tiles always have something to say from the attempt's own totals, but the round
     * track and the movement card need the sets, which an older record never filed. Cleared first
     * because [render] runs again when the body weight changes.
     */
    private fun sessionNumbers(a: Attempt) {
        val stats = SessionStats.from(a)
        binding.tiles.removeAllViews()
        binding.tiles.addView(statTileGrid(SessionTiles.of(a, stats)))
        roundTrack(a, stats)
        renderMovements(a, stats)
    }

    private fun roundTrack(a: Attempt, stats: SessionStats?) {
        binding.track.removeAllViews()
        val rounds = stats?.rounds.orEmpty()
        val show = if (rounds.isEmpty()) View.GONE else View.VISIBLE
        binding.trackTitle.visibility = show
        binding.track.visibility = show
        if (rounds.isEmpty()) return

        val plurals = SessionStats.plurals(a.profile)
        val hint = "Tap a round to see what went into it."
        val caption = styledText(R.style.Cindy_Callout, hint).apply {
            setPadding(0, dp(8), 0, 0)
            minHeight = dp(48)
        }
        fun say(i: Int) = rounds[i].caption(plurals, a.scoreIsLowerBound)
        val track = RoundTrackView(this).apply {
            show(rounds, ::say)
            onSelect = { i -> caption.text = i?.let(::say) ?: hint }
        }
        val scheme = Exercise.entries.joinToString(", ") { "${it.target} ${plurals.getValue(it)}" }
        binding.track.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundResource(R.drawable.glass_card)
                setPadding(dp(16), dp(10), dp(16), dp(14))
                addView(track, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ))
                addView(caption)
                // Said once, in the session's own words, so the three segments of a pill can be
                // read: knee push-ups are not "push-ups", and the order is the order they are done.
                addView(styledText(
                    R.style.Cindy_Footnote,
                    "A round is $scheme, in that order, left to right. What was not done stays " +
                        "hollow." + if (a.scoreIsLowerBound) {
                        " The camera lost you for ${formatDuration(a.untrackedMs)}, so rounds " +
                            "may hold more than shown."
                    } else {
                        ""
                    }
                ).apply {
                    textSize = 11f
                    setPadding(0, dp(4), 0, 0)
                })
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }

    private fun renderMovements(a: Attempt, stats: SessionStats?) {
        binding.movements.removeAllViews()
        val movements = stats?.movements.orEmpty()
        val show = if (movements.isEmpty()) View.GONE else View.VISIBLE
        binding.movementsTitle.visibility = show
        binding.movements.visibility = show
        if (movements.isEmpty()) return
        binding.movements.addView(
            movementCard(movements, a.scoreIsLowerBound),
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        binding.movements.addView(styledText(
            R.style.Cindy_Footnote,
            "Times cover finished sets and include getting into position. The average is of " +
                "the sets that reached their target."
        ).apply {
            textSize = 11f
            setPadding(dp(4), dp(10), dp(4), 0)
        })
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

    /** "TUE 29 SEP 2026 · 18:04", honouring the phone's 12/24-hour setting as [RecordsActivity.openDay] does. */
    private fun reviewHeadline(a: Attempt, zone: ZoneId): String {
        val at = Instant.ofEpochMilli(a.atMillis).atZone(zone)
        val date = DateTimeFormatter.ofPattern("EEE d MMM yyyy", Locale.US).format(at).uppercase(Locale.US)
        val timePattern = if (DateFormat.is24HourFormat(this)) "HH:mm" else "h:mm a"
        val time = SimpleDateFormat(timePattern, Locale.US).format(Date(a.atMillis))
        return "$date · $time"
    }

    /**
     * What this session is measured against, replacing the old single "Against your best" row:
     * an eyebrow, a chip per [Comparisons.options], and a card for whichever is chosen. Cleared
     * first because [render] runs again when the body weight changes. Hidden entirely when there
     * is no earlier session at the same movements — a session cannot be measured against a
     * history it does not have.
     */
    private fun compareCard(a: Attempt, all: List<Attempt>) {
        binding.compare.removeAllViews()
        val options = Comparisons.options(all, a)
        if (options.isEmpty()) {
            binding.compareTitle.visibility = View.GONE
            binding.compare.visibility = View.GONE
            comparison = null
            onComparisonChanged()
            return
        }
        binding.compareTitle.visibility = View.VISIBLE
        binding.compare.visibility = View.VISIBLE

        // Keeps whichever chip the athlete already chose across a re-render, rather than
        // snapping back to "Your best" every time the weight prompt redraws the page.
        val kept = comparison?.atMillis?.let { prior -> options.firstOrNull { it.attempt.atMillis == prior } }
        val initial = kept ?: options.first()
        comparison = initial.attempt

        binding.compare.addView(
            chipRow(options.map { it.label }, options.indexOf(initial)) { i ->
                comparison = options[i].attempt
                onComparisonChanged()
            }.apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
            }
        )
        compareCardHolder = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(10) }
        }
        binding.compare.addView(compareCardHolder)
        onComparisonChanged()
    }

    /**
     * Redraws whatever depends on [comparison]: the compare card, and the round splits' ticks.
     * Later sections of this page hang their own charts here rather than each keeping a
     * selection of their own. Runs with no comparison too, since a section that does not need
     * one still has to be drawn; only the card is skipped then.
     */
    private fun onComparisonChanged() {
        val reference = comparison
        if (reference != null && ::compareCardHolder.isInitialized) {
            compareCardHolder.removeAllViews()
            compareCardHolder.addView(comparisonCardView(attempt, reference))
        }
        splitsComparison()
    }

    /** The reference session and the delta, as one tappable card that opens it in review. */
    private fun comparisonCardView(a: Attempt, reference: Attempt): View {
        val dateFormat = SimpleDateFormat("d MMM", Locale.US)
        val referenceLine = "${dateFormat.format(Date(reference.atMillis))} · " +
            "${reference.scoreLabel()} · ${Progress.formatReps(reference.totalReps)} reps"
        val deltaLine = compareDeltaText(a, reference)
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            foreground = rowRipple()
            clipToOutline = true
            minimumHeight = dp(48)
            setPadding(dp(18), dp(14), dp(18), dp(14))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(styledText(R.style.Cindy_Headline, referenceLine))
            addView(styledText(R.style.Cindy_Callout, deltaLine).apply {
                setPadding(0, dp(4), 0, 0)
            })
            setOnClickListener { startActivity(review(this@ResultsActivity, reference.atMillis)) }
            describeAsButton("$referenceLine, $deltaLine")
        }
    }

    /**
     * "+22 reps · 1 round more · 0:09 faster a round", green when [a] is ahead on reps,
     * [R.color.label_tertiary] otherwise. "At least" when [a]'s own score is a lower bound: the
     * true gap can only be larger than this, never smaller.
     */
    private fun compareDeltaText(a: Attempt, reference: Attempt): CharSequence {
        val d = Comparisons.delta(a, reference)
        val parts = mutableListOf<String>()
        parts += when {
            d.reps > 0 -> "+${d.reps} reps"
            d.reps < 0 -> "${-d.reps} fewer reps"
            else -> "level on reps"
        }
        if (d.rounds > 0) {
            parts += "${d.rounds} round${if (d.rounds == 1) "" else "s"} more"
        } else if (d.rounds < 0) {
            parts += "${-d.rounds} round${if (d.rounds == -1) "" else "s"} fewer"
        }
        d.avgRoundMs?.let { ms ->
            if (ms > 0) parts += "${formatDuration(ms)} faster a round"
            else if (ms < 0) parts += "${formatDuration(-ms)} slower a round"
        }
        val text = parts.joinToString(" · ").let { if (a.scoreIsLowerBound) "At least $it" else it }
        return SpannableString(text).apply {
            setSpan(
                ForegroundColorSpan(
                    getColor(if (d.reps > 0) R.color.state_ok else R.color.label_tertiary)
                ),
                0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
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
