package com.cindy.tracker

import android.app.Activity
import android.app.AlertDialog
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.util.Locale

/**
 * The two dialogs that outlived the one screen they were written on.
 *
 * Both used to be private methods: the movement picker on [MainActivity] behind a HUD chip, and
 * the body-weight prompt on [ResultsActivity] behind the calorie line. Moving the picker to
 * [MenuActivity] would have meant a second copy of eighty lines, and body weight was only ever
 * reachable *after* a workout, which is the one moment nobody wants to fill in a form. Hoisting
 * them here lets the menu offer both without either screen owning them.
 */

/**
 * "Make Cindy yours": one choice per movement, taken before the clock starts.
 *
 * Neutral names only. No "easy", "beginner", "scaled" or "cheat" — a band-assisted pull-up is a
 * different prescription, not a lesser athlete, and the app has no business editorialising about
 * which one someone ought to be doing. What it does say plainly is which choices it can score
 * with the camera and which it will ask to be tapped in, because that is a fact about the app
 * rather than a judgement about the person.
 *
 * [onSave] receives the new profile only when something is actually chosen.
 */
fun Activity.chooseMovements(current: CindyProfile, onSave: (CindyProfile) -> Unit) {
    val container = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(px(20), px(4), px(20), px(4))
    }
    container.addView(dialogNote(
        "Anything other than the standard three is saved as an Adaptive Cindy and ranked " +
            "against your own sessions at the same movements."
    ))
    val pull = variantGroup(container, "PULL", PullVariant.entries, current.pull,
        { it.label }, { it.tracking })
    val push = variantGroup(container, "PUSH", PushVariant.entries, current.push,
        { it.label }, { it.tracking })
    val squat = variantGroup(container, "SQUAT", SquatVariant.entries, current.squat,
        { it.label }, { it.tracking })

    AlertDialog.Builder(this)
        .setTitle("Make Cindy yours")
        .setView(ScrollView(this).apply { addView(container) })
        .setNegativeButton("Cancel", null)
        .setPositiveButton("Save") { _, _ ->
            onSave(
                CindyProfile(
                    pull = PullVariant.entries[pull.checkedRadioButtonId],
                    push = PushVariant.entries[push.checkedRadioButtonId],
                    squat = SquatVariant.entries[squat.checkedRadioButtonId]
                )
            )
        }
        .show()
}

/**
 * Asks for body weight in kilograms, the one thing about the athlete [Calories] needs and the
 * camera cannot see. [onSaved] runs only when a plausible weight was stored.
 */
fun Activity.askBodyWeight(profile: Profile, onSaved: () -> Unit) {
    val input = EditText(this).apply {
        inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        hint = "kg"
        if (profile.hasBodyWeight) setText("%.0f".format(Locale.US, profile.bodyWeightKg))
        setPadding(px(24), px(16), px(24), px(16))
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
                Toast.makeText(
                    this,
                    "Enter a weight between ${Profile.MIN_KG.toInt()} and " +
                        "${Profile.MAX_KG.toInt()} kg",
                    Toast.LENGTH_LONG
                ).show()
                return@setPositiveButton
            }
            profile.bodyWeightKg = kg
            onSaved()
        }
        .show()
}

/** Small print inside a dialog. */
fun Activity.dialogNote(text: String): TextView = TextView(this).apply {
    this.text = text
    setTextColor(getColor(R.color.on_surface_dim))
    textSize = 12f
    setPadding(0, px(8), 0, px(4))
}

/** One movement's options, as radio buttons whose ids are their ordinal. */
private fun <T> Activity.variantGroup(
    parent: LinearLayout,
    title: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    tracking: (T) -> Tracking
): RadioGroup {
    parent.addView(TextView(this).apply {
        text = title
        setTextColor(getColor(R.color.on_surface_dim))
        textSize = 11f
        setPadding(0, px(14), 0, px(2))
    })
    val group = RadioGroup(this)
    options.forEachIndexed { i, option ->
        group.addView(RadioButton(this).apply {
            id = i
            // Said on the option itself, so the choice and its consequence arrive together.
            text = if (tracking(option) == Tracking.MANUAL) {
                "${label(option)}  ·  you tap +1"
            } else {
                label(option)
            }
            textSize = 15f
            minHeight = px(48)
        })
    }
    group.check(options.indexOf(selected))
    parent.addView(group)
    return group
}

private fun Activity.px(value: Int): Int = (value * resources.displayMetrics.density).toInt()
