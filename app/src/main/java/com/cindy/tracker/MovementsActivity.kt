package com.cindy.tracker

import android.os.Bundle
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityMovementsBinding

/**
 * Movements: one choice per movement, taken before the clock starts.
 *
 * A tap on a row gives it the check and is saved there and then, so there is no SAVE and nothing
 * to CANCEL; the page is left from its top bar or with back, and what was chosen stays chosen.
 * This replaces the sheet that saved only on SAVE (spec #139): changing a variation took the menu,
 * Movements, the choice and then SAVE, and the last of those is what a tap now does.
 *
 * Neutral names only. No "easy", "beginner", "scaled" or "cheat" — a band-assisted pull-up is a
 * different prescription, not a lesser athlete, and the app has no business editorialising about
 * which one someone ought to be doing. What it does say plainly is which choices it can score
 * with the camera and which it will ask to be tapped in, because that is a fact about the app
 * rather than a judgement about the person.
 *
 * Beneath them sits one setting that is about how the squats are counted rather than which squat
 * was chosen: whether an air-squat session may switch itself to heels flat (see
 * [Profile.smartSquats]). It is saved on its tap like the choices.
 *
 * The menu refuses to open this while a workout is live, and the camera screen picks the choice
 * up when it resumes ([MainActivity] rebuilds its engine), so the page itself holds no rule about
 * either.
 */
class MovementsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMovementsBinding
    private lateinit var profile: Profile

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMovementsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        profile = Profile(this)

        val current = profile.movements

        // Printed as "+1" to match the button it points at, but said in words: a screen reader's
        // reading of a bare glyph is not something to leave to chance.
        val shown = { t: Tracking -> if (t == Tracking.MANUAL) "you tap +1" else null }
        val said = { t: Tracking -> if (t == Tracking.MANUAL) "you tap plus one" else null }

        // Each tap changes one movement and keeps the other two as they are *now*, not as they
        // were when the page opened, so that three taps in a row add up to the three choices.
        binding.choices.addView(choiceSection(
            "PULL", PullVariant.entries, current.pull, { it.label }, { shown(it.tracking) },
            { said(it.tracking) }
        ) { profile.movements = profile.movements.copy(pull = it) })
        binding.choices.addView(choiceSection(
            "PUSH", PushVariant.entries, current.push, { it.label }, { shown(it.tracking) },
            { said(it.tracking) }
        ) { profile.movements = profile.movements.copy(push = it) })
        binding.choices.addView(choiceSection(
            "SQUAT", SquatVariant.entries, current.squat, { it.label }, { shown(it.tracking) },
            { said(it.tracking) }
        ) { profile.movements = profile.movements.copy(squat = it) })

        binding.choices.addView(switchRow("Spot heels-flat squats", profile.smartSquats) {
            profile.smartSquats = it
        })
        binding.choices.addView(
            sheetNote(
                "Off while it's being tested. When on, three heels-flat squats in a standard " +
                    "Cindy switch it to Adaptive Cindy — Cindy says so out loud — and count " +
                    "them, the first three included. Applies when Air squat is chosen."
            )
        )
        // The consequence of a choice, said where the choices are. It is not a line that says what
        // the page is; it is what taking anything but the standard three does to the score.
        binding.choices.addView(
            styledText(
                R.style.Cindy_Footnote,
                "Anything other than the standard three is saved as an Adaptive Cindy and " +
                    "ranked against your own sessions at the same movements."
            ).apply { setPadding(dp(4), dp(14), dp(4), 0) },
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }
}
