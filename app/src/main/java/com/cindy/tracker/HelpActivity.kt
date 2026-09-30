package com.cindy.tracker

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.TextViewCompat
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

        binding.actions.addView(glassButton("CROSSFIT.COM").apply {
            // An arrow, because this one leaves the app.
            setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, R.drawable.ic_external, 0)
            compoundDrawablePadding = dp(8)
            TextViewCompat.setCompoundDrawableTintList(
                this, ColorStateList.valueOf(getColor(R.color.label_secondary))
            )
            setOnClickListener { openSource() }
            describeAsButton("Open the CrossFit page for Cindy")
        })
        binding.actions.addView(primaryButton("DONE").apply {
            setOnClickListener { finish() }
        })

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
        // First, because it is the one thing on this screen that is for someone who is lost rather
        // than curious: the pages and the tour of the camera screen, taken again.
        binding.sections.addView(insetGroup {
            row(navRow("Take the tour", "The first-launch pages and a tour of the camera screen") {
                startActivity(TutorialActivity.intent(this@HelpActivity, replay = true))
            })
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) })

        heading("THE WORKOUT")
        workoutCard()
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
        val history = RecordStore(this).all()
        // These tiers describe the prescribed movements, so only a standard Cindy is measured
        // against them. Ticking "Rx'd" off the back of a session run with knee push-ups would be
        // exactly the claim the note below has always refused to make -- the difference now is
        // that the app records which movements were used and can tell.
        val best = Records.bestIn(history, CindyProfile.STANDARD)
        // The scaled tier is deliberately never ticked: this app counts the prescribed rep
        // scheme, so it has no idea whether the work was scaled, and a tick there would be a
        // claim it cannot make.
        tier("Beginner", "8–10+ rounds, scaled", null, best)
        tier("Intermediate", "8–10+ rounds as prescribed", 8, best)
        tier("Rx'd", "20+ rounds", 20, best)
        tier("Elite", "25+ rounds", 25, best)
        val adaptiveBest = history.filter { it.profile?.isStandard != true }.maxByOrNull { it.totalReps }
        when {
            best != null ->
                quiet("Your best so far: ${best.scoreLabel()} — ${best.rounds} rounds.")
            // Not "no score": they have trained, and saying otherwise to someone whose sessions
            // were all adaptive would be the app pretending they were not there.
            adaptiveBest != null -> quiet(
                "Your best is ${adaptiveBest.scoreLabel()} at ${adaptiveBest.caption}. These " +
                    "tiers describe the prescribed movements, so it is ranked against your own " +
                    "sessions at the same movements instead."
            )
            else -> quiet("Finish a Cindy and your best will show up against these.")
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
        diagram()
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

    /**
     * The rep scheme beside the mark whose proportions it is: the arcs are 270°, 180° and 90° of
     * a circle, which is fifteen, ten and five. The pips repeat the arcs' own weights, so the
     * mark on the launcher and the list in the card are visibly the same fact.
     */
    private fun workoutCard() {
        val weights = intArrayOf(R.color.label, R.color.label_secondary, R.color.label_tertiary)
        val scheme = listOf("5" to "Pull-ups", "10" to "Push-ups", "15" to "Air squats")

        card {
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL

                addView(ImageView(context).apply {
                    setImageResource(R.drawable.mark_arcs)
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(dp(62), dp(62)))

                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(
                        0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                    ).apply { marginStart = dp(18) }

                    addView(styledText(R.style.Cindy_Title2, "AMRAP 20:00"))
                    scheme.forEachIndexed { i, (count, name) ->
                        addView(LinearLayout(context).apply {
                            orientation = LinearLayout.HORIZONTAL
                            gravity = Gravity.CENTER_VERTICAL
                            setPadding(0, if (i == 0) dp(12) else dp(7), 0, 0)
                            addView(View(context).apply {
                                background = dotDrawable(weights[i])
                            }, LinearLayout.LayoutParams(dp(6), dp(6)))
                            addView(styledText(R.style.Cindy_Headline, count).apply {
                                gravity = Gravity.END
                                layoutParams = LinearLayout.LayoutParams(
                                    dp(22), ViewGroup.LayoutParams.WRAP_CONTENT
                                ).apply { marginStart = dp(10) }
                            })
                            addView(styledText(R.style.Cindy_Body, name).apply {
                                setTextColor(getColor(R.color.label_body))
                            }.withStartMargin(dp(10)))
                        })
                    }
                })
            })
            rule()
            quiet("One round is 30 reps. The score is rounds completed, plus any reps of the " +
                "round you are part-way through when the clock stops.")
        }
    }

    /**
     * The placement diagram, in its permanent home.
     *
     * It is offered once before the first setup check and can be dismissed for good there, so it
     * needs somewhere to live afterwards — this is the section that already gives the same advice
     * in words.
     */
    private fun diagram() = binding.sections.addView(
        PlacementGuideView(this).apply {
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(12), dp(14), dp(12), dp(8))
        },
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(210)).apply {
            topMargin = dp(4)
            bottomMargin = dp(14)
        }
    )

    private fun heading(text: String) {
        // A new section ends whatever group of tiers was being collected.
        tierGroup = null
        binding.sections.addView(eyebrow(text).apply { setPadding(dp(4), dp(24), 0, dp(10)) })
    }

    private fun paragraph(text: String) = binding.sections.addView(
        styledText(R.style.Cindy_Body, text).apply {
            setTextColor(getColor(R.color.label_body))
            setPadding(dp(4), 0, dp(4), dp(10))
        }
    )

    private fun quiet(text: String) = binding.sections.addView(
        styledText(R.style.Cindy_Footnote, text).apply { setPadding(dp(4), dp(2), dp(4), dp(10)) }
    )

    /**
     * CrossFit's words, marked as theirs by attribution rather than by a coloured bar.
     *
     * The bar down the side said "this is special"; the credit underneath says whose it is, which
     * is both the more useful fact and the one the screen is obliged to carry.
     */
    private fun quote(text: String) = binding.sections.addView(
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(20), dp(18), dp(20), dp(15))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }

            addView(styledText(R.style.Cindy_Body, "\u201C$text\u201D").apply {
                setTextColor(getColor(R.color.label_body))
                setTypeface(typeface, Typeface.ITALIC)
            })
            addView(View(context).apply {
                setBackgroundColor(getColor(R.color.hairline))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, hairlinePx()
                ).apply { topMargin = dp(14) }
            })
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(11), 0, 0)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                addView(ImageView(context).apply {
                    setImageResource(R.drawable.ic_link)
                    imageTintList = ColorStateList.valueOf(getColor(R.color.label_tertiary))
                }, LinearLayout.LayoutParams(dp(12), dp(12)))
                addView(eyebrow("CROSSFIT.COM").apply {
                    textSize = 10f
                    setPadding(dp(7), 0, 0, 0)
                })
            })
            contentDescription = "Quotation from crossfit.com: $text"
        }
    )

    private fun bullets(vararg items: String) = items.forEach { item ->
        binding.sections.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(4), 0, dp(4), dp(12))
            addView(View(context).apply {
                background = dotDrawable(R.color.label_tertiary)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(5), dp(5)).apply { topMargin = dp(9) })
            addView(styledText(R.style.Cindy_Body, item).apply {
                setTextColor(getColor(R.color.label_body))
                setPadding(dp(12), 0, 0, 0)
            })
        })
    }

    private fun card(build: LinearLayout.() -> Unit) = binding.sections.addView(
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(20), dp(18), dp(20), dp(18))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }
            build()
        }
    )

    private fun LinearLayout.rule() = addView(View(context).apply {
        setBackgroundColor(getColor(R.color.hairline))
    }, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, hairlinePx()
    ).apply { topMargin = dp(16) })

    private fun LinearLayout.big(text: String) =
        addView(styledText(R.style.Cindy_Title2, text))

    private fun LinearLayout.body(text: String) =
        addView(styledText(R.style.Cindy_Body, text).apply {
            setTextColor(getColor(R.color.label_body))
            textSize = 16f
            setPadding(0, dp(8), 0, 0)
        })

    private fun LinearLayout.quiet(text: String) =
        addView(styledText(R.style.Cindy_Footnote, text).apply { setPadding(0, dp(12), 0, 0) })

    /** The tiers of the section being built, so four calls make one card rather than four. */
    private var tierGroup: InsetGroup? = null

    /**
     * One of CrossFit's score tiers, ticked when the athlete's best has reached it.
     *
     * A null [minRounds] is a tier this app cannot judge, and is never ticked.
     */
    private fun tier(name: String, detail: String, minRounds: Int?, best: Attempt?) {
        val group = tierGroup ?: InsetGroup(this).also {
            tierGroup = it
            binding.sections.addView(it)
        }
        val reached = minRounds != null && best != null && best.rounds >= minRounds

        group.row(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(14), dp(18), dp(14))
            if (reached) setBackgroundColor(getColor(R.color.surface_glass))

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                )
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                addView(styledText(R.style.Cindy_Headline, name))
                addView(styledText(R.style.Cindy_Footnote, detail).apply {
                    setPadding(0, dp(2), 0, 0)
                })
            })

            if (minRounds == null) {
                // Never ticked, and said so rather than left ambiguously empty: this app counts
                // the prescribed rep scheme, so it cannot know whether the work was scaled.
                addView(eyebrow("not scored").apply {
                    textSize = 10f
                    letterSpacing = 0.04f
                    setTextColor(getColor(R.color.label_quaternary))
                })
            } else {
                addView(ImageView(context).apply {
                    setImageResource(
                        if (reached) R.drawable.ic_check_filled else R.drawable.ic_ring_empty
                    )
                }, LinearLayout.LayoutParams(dp(22), dp(22)))
            }
            contentDescription =
                if (reached) "$name, $detail, reached" else "$name, $detail, not yet reached"
        })
    }
}
