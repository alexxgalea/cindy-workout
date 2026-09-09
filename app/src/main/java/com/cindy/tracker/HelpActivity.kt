package com.cindy.tracker

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityHelpBinding

/**
 * What Cindy is, and what this app is doing while you do it.
 *
 * The workout half is CrossFit's, quoted rather than paraphrased and attributed on the page —
 * the definition, the scaled version, the score tiers and the pacing advice all come from
 * [SOURCE]. Note that CrossFit does *not* publish per-movement range-of-motion standards on that
 * page; it links out to a page per movement. So this screen does not state any either, rather
 * than inventing standards and putting CrossFit's name near them.
 *
 * The second half is this app's own, and is the part most worth reading: the camera cannot see
 * what it is not shown, and every hint it gives has a specific cause.
 */
class HelpActivity : AppCompatActivity() {

    private companion object {
        const val SOURCE = "https://www.crossfit.com/cindy"
    }

    private lateinit var binding: ActivityHelpBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityHelpBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnBack.setOnClickListener { finish() }
        binding.btnSource.setOnClickListener { openSource() }
        binding.btnSource.contentDescription = "Open the CrossFit page for Cindy"

        render()
    }

    private fun openSource() {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(SOURCE)))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, "No browser to open $SOURCE", Toast.LENGTH_LONG).show()
        }
    }

    private fun render() {
        heading("THE WORKOUT")
        card {
            big("AMRAP 20:00")
            body("5 pull-ups\n10 push-ups\n15 air squats")
            quiet("One round is 30 reps. The score is rounds completed, plus any reps of the " +
                "round you are part-way through when the clock stops.")
        }
        quote(
            "Complete as many rounds and reps as possible in 20 minutes of: " +
                "5 pull-ups, 10 push-ups, 15 squats"
        )

        heading("SCALED")
        card {
            big("AMRAP 12:00")
            body("3 ring rows\n6 assisted push-ups\n9 squats")
            quiet("CrossFit's beginner version. This app counts the prescribed workout only — " +
                "use the +1 and −1 buttons if you are working at the scaled version.")
        }
        bullets(
            "Pull-ups scale to \"any movement that is an upper-body pulling option\" — " +
                "leg-assisted pull-ups, or ring rows.",
            "Push-ups scale to \"any bodyweight horizontal pressing movement, like an incline " +
                "push-up or push-up from the knees\".",
            "Squats scale on reps, or by squatting \"to a target that could be set above the " +
                "typical full range of motion\"."
        )

        heading("WHAT IT TESTS")
        quote(
            "Tests athletes' muscular endurance, stamina, and capacity with various low-skill " +
                "gymnastics elements."
        )
        paragraph(
            "Cindy is time-priority: the 20 minutes are fixed and you chase reps inside them. " +
                "That is why the clock here never stops for a rep and only pauses when you say so."
        )

        heading("WHAT A GOOD SCORE IS")
        paragraph("CrossFit's tiers, in rounds:")
        val best = RecordStore(this).all().maxByOrNull { it.totalReps }
        // The scaled tier is deliberately never ticked: this app counts the prescribed rep
        // scheme, so it has no idea whether the work was scaled, and a tick there would be a
        // claim it cannot make.
        tier("Beginner", "8–10+ rounds, scaled", null, best)
        tier("Intermediate", "8–10+ rounds as prescribed", 8, best)
        tier("Rx'd", "20+ rounds", 20, best)
        tier("Elite", "25+ rounds", 25, best)
        if (best != null) {
            quiet("Your best so far: ${best.scoreLabel()} — ${best.rounds} rounds.")
        } else {
            quiet("Finish a Cindy and your best will show up against these.")
        }
        quiet("This app's own ladder in RECORDS is a separate, finer-grained scale. These four " +
            "are CrossFit's.")

        heading("PACING")
        bullets(
            "\"The fastest athletes will complete rounds in under 45 seconds.\"",
            "\"Striving to complete each round in under 2 minutes is a great goal for all " +
                "levels to shoot for.\"",
            "The results screen charts every round split, so you can see where the pace went."
        )
        quote(
            "If muscular failure and full range of motion are a concern with push-ups, consider " +
                "breaking up the reps early. For example, many athletes will start this workout " +
                "by performing 5 reps, taking a quick break to shake out their arms, and " +
                "completing the remaining 5 reps."
        )

        heading("RANGE OF MOTION")
        quote(
            "Adhering to the full range of motion in all movements is important for structural " +
                "integrity and joint health."
        )
        paragraph(
            "CrossFit keeps the standards for each movement on its own page rather than on the " +
                "Cindy page, so this screen does not restate them. Tap CROSSFIT.COM below and " +
                "follow the links to The Kipping Pull-up, The Push-up and The Air Squat."
        )

        heading("HOW THIS APP COUNTS")
        paragraph(
            "A phone on the floor sees a different shape than one at chest height, so nothing " +
                "here is a fixed angle. The app learns your range from your own movement and " +
                "judges reps against that."
        )
        bullets(
            "Stand the phone so your whole body stays in frame, and leave it there — moving it " +
                "mid-workout invalidates what it has learned, so a pause re-calibrates.",
            "START runs a setup check first: two slow pull-ups teach it your range. SKIP goes " +
                "straight in and calibrates as you go.",
            "For pull-ups it works out where your bar is from your dead hangs. The box on screen " +
                "is the bar zone your hands must be inside; the dashed line under it is where " +
                "your head has to drop back below before the next rep can count.",
            "Push-ups and squats do not start counting until you are actually in position — " +
                "\"Get set on the floor\", \"Stand up to start\". Getting up off the floor after " +
                "push-ups is not a squat.",
            "When a rep will not count, the status line says why, and says it out loud if " +
                "nothing changes. VOICE turns that off.",
            "−1 and +1 fix a miscount. Hold +1 to skip to the next movement."
        )

        heading("CALORIES AND STREAKS")
        paragraph(
            "The calorie figure on the results screen is an estimate, and it is labelled as one. " +
                "Without a heart-rate strap there is no honest way to measure this, so it uses " +
                "the standard MET equation that every strapless tracker uses underneath: " +
                "kcal = MET × 3.5 × your weight in kg ÷ 200, per minute."
        )
        bullets(
            "The Compendium of Physical Activities puts vigorous calisthenics and general " +
                "circuit training at 8 METs. That is taken to describe ten rounds in the " +
                "twenty minutes.",
            "Cindy is an AMRAP, so eight rounds and twenty-five rounds are not the same effort. " +
                "The MET is scaled by the rate you actually worked at, and capped at both ends — " +
                "no one sustains more than 14 METs for twenty minutes.",
            "Paused time is excluded. Resting with the clock stopped is not work.",
            "Nothing is shown until you enter your body weight, because a guessed weight would " +
                "produce a confident number that is wrong by however far the guess missed. It " +
                "is stored on this phone only."
        )
        paragraph(
            "The streak on the RECORDS screen counts consecutive days on which you trained, in " +
                "your own time zone. It does not break the moment midnight passes — a day you " +
                "have not finished living yet still counts as alive, so training this evening " +
                "keeps it going."
        )

        heading("SOURCE")
        paragraph(
            "The workout, the scaled version, the score tiers and the pacing quotes on this " +
                "screen are from CrossFit's own page for Cindy."
        )
        quiet(SOURCE)
    }

    // ── building blocks ───────────────────────────────────────────────────────

    private fun heading(text: String) = binding.sections.addView(
        TextView(this).apply {
            this.text = text
            letterSpacing = 0.12f
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 12f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(22), 0, dp(8))
        }
    )

    private fun paragraph(text: String) = binding.sections.addView(
        TextView(this).apply {
            this.text = text
            setTextColor(getColor(R.color.on_surface))
            textSize = 14f
            setLineSpacing(dp(4).toFloat(), 1f)
            setPadding(0, 0, 0, dp(8))
        }
    )

    private fun quiet(text: String) = binding.sections.addView(
        TextView(this).apply {
            this.text = text
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 12f
            setLineSpacing(dp(3).toFloat(), 1f)
            setPadding(0, dp(2), 0, dp(8))
        }
    )

    /** CrossFit's words, marked as theirs by an accent rule rather than by quote marks alone. */
    private fun quote(text: String) = binding.sections.addView(
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }
            addView(TextView(context).apply {
                setBackgroundColor(getColor(R.color.accent))
                layoutParams = LinearLayout.LayoutParams(dp(3), ViewGroup.LayoutParams.MATCH_PARENT)
            })
            addView(TextView(context).apply {
                this.text = "“$text”"
                setTextColor(getColor(R.color.on_surface))
                textSize = 14f
                setTypeface(typeface, Typeface.ITALIC)
                setLineSpacing(dp(4).toFloat(), 1f)
                setPadding(dp(12), dp(2), 0, dp(2))
            })
        }
    )

    private fun bullets(vararg items: String) = items.forEach { item ->
        binding.sections.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
            addView(TextView(context).apply {
                text = "·"
                setTextColor(getColor(R.color.accent))
                textSize = 14f
                setTypeface(typeface, Typeface.BOLD)
                width = dp(16)
            })
            addView(TextView(context).apply {
                this.text = item
                setTextColor(getColor(R.color.on_surface))
                textSize = 14f
                setLineSpacing(dp(4).toFloat(), 1f)
            })
        })
    }

    private fun card(build: LinearLayout.() -> Unit) = binding.sections.addView(
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.bg_row)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }
            build()
        }
    )

    private fun LinearLayout.big(text: String) = addView(TextView(context).apply {
        this.text = text
        setTextColor(getColor(R.color.accent))
        textSize = 22f
        typeface = Typeface.MONOSPACE
        setTypeface(typeface, Typeface.BOLD)
    })

    private fun LinearLayout.body(text: String) = addView(TextView(context).apply {
        this.text = text
        setTextColor(getColor(R.color.on_surface))
        textSize = 16f
        setLineSpacing(dp(5).toFloat(), 1f)
        setPadding(0, dp(6), 0, 0)
    })

    private fun LinearLayout.quiet(text: String) = addView(TextView(context).apply {
        this.text = text
        setTextColor(getColor(R.color.on_surface_dim))
        textSize = 12f
        setLineSpacing(dp(3).toFloat(), 1f)
        setPadding(0, dp(10), 0, 0)
    })

    /**
     * One of CrossFit's score tiers, lit up when the athlete's best has reached it.
     *
     * A null [minRounds] is a tier this app cannot judge, and is never ticked.
     */
    private fun tier(name: String, detail: String, minRounds: Int?, best: Attempt?) {
        val reached = minRounds != null && best != null && best.rounds >= minRounds
        binding.sections.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundResource(if (reached) R.drawable.bg_row_benchmark else R.drawable.bg_row)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
            contentDescription =
                if (reached) "$name, $detail, reached" else "$name, $detail, not yet reached"

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                addView(TextView(context).apply {
                    text = name
                    setTextColor(getColor(if (reached) R.color.accent else R.color.on_surface))
                    textSize = 16f
                    setTypeface(typeface, Typeface.BOLD)
                })
                addView(TextView(context).apply {
                    text = detail
                    setTextColor(getColor(R.color.on_surface_dim))
                    textSize = 12f
                })
            })
            if (reached) {
                addView(TextView(context).apply {
                    text = "✓"
                    setTextColor(getColor(R.color.accent))
                    textSize = 20f
                    setTypeface(typeface, Typeface.BOLD)
                })
            }
        })
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
