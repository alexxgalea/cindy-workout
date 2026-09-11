package com.cindy.tracker

import android.app.Activity
import android.content.res.ColorStateList
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.util.Locale

/**
 * The two sheets that outlived the one screen they were written on.
 *
 * Both used to be private methods: the movement picker on [MainActivity] behind a HUD chip, and
 * the body-weight prompt on [ResultsActivity] behind the calorie line. Moving the picker to
 * [MenuActivity] would have meant a second copy of eighty lines, and body weight was only ever
 * reachable *after* a workout, which is the one moment nobody wants to fill in a form. Hoisting
 * them here lets the menu offer both without either screen owning them.
 *
 * They were `AlertDialog`s until the redesign. See [CindySheet] for why they no longer are.
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
    val sheet = CindySheet(
        this,
        title = "Make Cindy yours",
        subtitle = "Anything other than the standard three is saved as an Adaptive Cindy and " +
            "ranked against your own sessions at the same movements."
    )

    val pull = sheet.variantGroup("PULL", PullVariant.entries, current.pull, { it.label }, { it.tracking })
    val push = sheet.variantGroup("PUSH", PushVariant.entries, current.push, { it.label }, { it.tracking })
    val squat = sheet.variantGroup("SQUAT", SquatVariant.entries, current.squat, { it.label }, { it.tracking })

    sheet.actions(
        primary = "SAVE",
        onPrimary = { onSave(CindyProfile(pull = pull(), push = push(), squat = squat())) },
        secondary = "CANCEL",
        onSecondary = {}
    ).show()
}

/**
 * Asks for body weight in kilograms, the one thing about the athlete [Calories] needs and the
 * camera cannot see. [onSaved] runs only when a plausible weight was stored.
 */
fun Activity.askBodyWeight(profile: Profile, onSaved: () -> Unit) {
    val input = EditText(this, null, 0, R.style.Cindy_MetricM).apply {
        inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        hint = "kg"
        setHintTextColor(getColor(R.color.label_quaternary))
        gravity = Gravity.CENTER
        background = null
        setBackgroundResource(R.drawable.glass_card_small)
        setPadding(dp(20), dp(16), dp(20), dp(16))
        if (profile.hasBodyWeight) setText("%.0f".format(Locale.US, profile.bodyWeightKg))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    val sheet = CindySheet(
        this,
        title = "Your body weight",
        subtitle = "Calories are estimated from body weight and how hard you worked. " +
            "It stays on this phone."
    )
    sheet.add(input)
    sheet.actions(
        primary = "SAVE",
        onPrimary = {
            val kg = input.text.toString().trim().toDoubleOrNull()
            if (kg == null || kg < Profile.MIN_KG || kg > Profile.MAX_KG) {
                Toast.makeText(
                    this,
                    "Enter a weight between ${Profile.MIN_KG.toInt()} and " +
                        "${Profile.MAX_KG.toInt()} kg",
                    Toast.LENGTH_LONG
                ).show()
            } else {
                profile.bodyWeightKg = kg
                onSaved()
            }
        },
        secondary = "CANCEL",
        onSecondary = {}
    ).show()
}

/** Small print inside a sheet. */
fun Activity.sheetNote(text: String): TextView =
    styledText(R.style.Cindy_Footnote, text).apply { setPadding(0, dp(8), 0, dp(4)) }

/**
 * One movement's options, as a grouped list rather than a column of radio buttons.
 *
 * Returns a getter for the current choice: the sheet is built once and read when SAVE is tapped,
 * so the selection lives in the rows themselves rather than in a field on the caller.
 */
private fun <T> CindySheet.variantGroup(
    title: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    tracking: (T) -> Tracking
): () -> T {
    val ctx = content.context
    var chosen = selected
    val ticks = mutableListOf<ImageView>()

    content.addView(ctx.eyebrow(title).apply {
        setPadding(ctx.dp(4), ctx.dp(18), 0, ctx.dp(8))
    })

    val group = ctx.insetGroup { }
    options.forEachIndexed { index, option ->
        val tick = ImageView(ctx).apply {
            setImageResource(R.drawable.ic_check)
            imageTintList = ColorStateList.valueOf(ctx.getColor(R.color.label))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            visibility = if (option == chosen) View.VISIBLE else View.INVISIBLE
            layoutParams = LinearLayout.LayoutParams(ctx.dp(19), ctx.dp(19))
                .apply { marginStart = ctx.dp(12) }
        }
        ticks += tick

        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = ctx.dp(52)
            setPadding(ctx.dp(18), ctx.dp(12), ctx.dp(16), ctx.dp(12))

            addView(LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                )
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                addView(ctx.styledText(R.style.Cindy_Headline, label(option)))
                // Said on the option itself, so the choice and its consequence arrive together.
                if (tracking(option) == Tracking.MANUAL) {
                    addView(ctx.styledText(R.style.Cindy_Footnote, "you tap +1").apply {
                        setPadding(0, ctx.dp(2), 0, 0)
                    })
                }
            })
            addView(tick)

            setOnClickListener {
                chosen = option
                ticks.forEachIndexed { i, t ->
                    t.visibility = if (i == index) View.VISIBLE else View.INVISIBLE
                }
            }
            describeAsButton(
                label(option) +
                    if (tracking(option) == Tracking.MANUAL) ", you tap plus one" else ""
            )
        }
        group.row(row)
    }
    content.addView(group)
    return { chosen }
}
