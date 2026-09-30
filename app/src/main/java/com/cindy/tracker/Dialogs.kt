package com.cindy.tracker

import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.util.Calendar
import java.util.Locale

/**
 * The sheets that outlived the one screen they were written on, plus one written straight here.
 *
 * The first two used to be private methods: the movement picker on [MainActivity] behind a HUD
 * chip, and the body-weight prompt on [ResultsActivity] behind the calorie line. Moving the
 * picker to [MenuActivity] would have meant a second copy of eighty lines, and body weight was
 * only ever reachable *after* a workout, which is the one moment nobody wants to fill in a form.
 * Hoisting them here lets the menu offer both without either screen owning them.
 *
 * [askHeartRateDetails] has no such history — the heart-rate settings the menu and the results
 * screen both need to reach are new — but it belongs beside the other two for the same reason:
 * one place owns a sheet that more than one screen opens.
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
 * Beneath them sits one setting that is about how the squats are counted rather than which squat
 * was chosen: whether an air-squat session may switch itself to heels flat (see
 * [Profile.smartSquats]). It is saved and discarded with the choices, so SAVE is the one place
 * anything here changes.
 *
 * [onSave] receives the new profile only when something is actually chosen.
 */
fun Activity.chooseMovements(
    current: CindyProfile,
    profile: Profile = Profile(this),
    onSave: (CindyProfile) -> Unit
) {
    val sheet = CindySheet(
        this,
        title = "Make Cindy yours",
        subtitle = "Anything other than the standard three is saved as an Adaptive Cindy and " +
            "ranked against your own sessions at the same movements."
    )

    // Printed as "+1" to match the button it points at, but said in words: a screen reader's
    // reading of a bare glyph is not something to leave to chance.
    val shown = { t: Tracking -> if (t == Tracking.MANUAL) "you tap +1" else null }
    val said = { t: Tracking -> if (t == Tracking.MANUAL) "you tap plus one" else null }
    val pull = sheet.choiceGroup(
        "PULL", PullVariant.entries, current.pull, { it.label }, { shown(it.tracking) }, { said(it.tracking) }
    )
    val push = sheet.choiceGroup(
        "PUSH", PushVariant.entries, current.push, { it.label }, { shown(it.tracking) }, { said(it.tracking) }
    )
    val squat = sheet.choiceGroup(
        "SQUAT", SquatVariant.entries, current.squat, { it.label }, { shown(it.tracking) }, { said(it.tracking) }
    )

    var smart = profile.smartSquats
    sheet.toggle("Spot heels-flat squats", smart) { smart = it }
    sheet.add(
        sheetNote(
            "Off while it's being tested. When on, three heels-flat squats in a standard Cindy " +
                "switch it to Adaptive Cindy — Cindy says so out loud — and count them, the " +
                "first three included. Applies when Air squat is chosen."
        )
    )

    sheet.actions(
        primary = "SAVE",
        onPrimary = {
            profile.smartSquats = smart
            onSave(CindyProfile(pull = pull()!!, push = push()!!, squat = squat()!!))
        },
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
        // A weight already entered is there to be replaced, not appended to.
        setSelectAllOnFocus(true)
        isFocusableInTouchMode = true
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
    // The sheet is the only one here with a field in it, and the athlete opened it to type. The
    // keyboard therefore comes up with it rather than waiting for a tap on a box they have
    // already aimed at — [CindySheet] lifts the sheet clear of the IME, which is what makes this
    // safe to do rather than a way of hiding the SAVE button behind a keyboard.
    input.post {
        if (input.requestFocus()) {
            (input.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }
    }
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

/**
 * Asks for the two things [Calories] needs beyond body weight to use heart rate: a birth year and
 * a sex. [onSaved] runs only once both are valid and stored.
 */
fun Activity.askHeartRateDetails(profile: Profile, onSaved: () -> Unit) {
    val input = EditText(this, null, 0, R.style.Cindy_MetricM).apply {
        inputType = InputType.TYPE_CLASS_NUMBER
        hint = "Year of birth"
        setHintTextColor(getColor(R.color.label_quaternary))
        gravity = Gravity.CENTER
        background = null
        setBackgroundResource(R.drawable.glass_card_small)
        setPadding(dp(20), dp(16), dp(20), dp(16))
        if (profile.birthYear != 0) setText("%d".format(Locale.US, profile.birthYear))
        // A birth year already entered is there to be replaced, not appended to.
        setSelectAllOnFocus(true)
        isFocusableInTouchMode = true
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    val sheet = CindySheet(
        this,
        title = "For heart-rate calories",
        subtitle = "Heart-rate calorie formulas are fitted separately for women and men, and " +
            "shift with age. Used only for calories, and it stays on this phone."
    )
    sheet.add(input)
    // Same reasoning as askBodyWeight: the athlete opened this sheet to type, so the keyboard
    // comes up with it rather than waiting for a tap on a field they have already aimed at.
    input.post {
        if (input.requestFocus()) {
            (input.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    val sex = sheet.choiceGroup(
        "SEX", Sex.entries, profile.sex, { it.label },
        { if (it == Sex.UNSTATED) "uses the average of both formulas" else null }
    )

    sheet.actions(
        primary = "SAVE",
        onPrimary = {
            val year = input.text.toString().trim().toIntOrNull()
            val age = year?.let { Calendar.getInstance().get(Calendar.YEAR) - it }
            val chosenSex = sex()
            when {
                age == null || age < Profile.MIN_AGE || age > Profile.MAX_AGE -> {
                    Toast.makeText(
                        this,
                        "Enter a birth year that makes you ${Profile.MIN_AGE} to " +
                            "${Profile.MAX_AGE}",
                        Toast.LENGTH_LONG
                    ).show()
                }
                chosenSex == null -> {
                    Toast.makeText(this, "Choose one — the formula needs it", Toast.LENGTH_LONG).show()
                }
                else -> {
                    // age non-null implies year non-null, since age is only ever derived from it.
                    profile.birthYear = year!!
                    profile.sex = chosenSex
                    onSaved()
                }
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
 * One field's options, as a grouped list rather than a column of radio buttons.
 *
 * Returns a getter for the current choice: the sheet is built once and read when SAVE is tapped,
 * so the selection lives in the rows themselves rather than in a field on the caller. [selected]
 * may be null — [askHeartRateDetails] opens with a sex that has never been chosen, which
 * [chooseMovements] never does, since every movement already has one.
 *
 * [note] is the one thing that varies between the two callers: a movement says when it is tapped
 * in rather than seen, a sex says which one is the average of the other two. Whatever it returns
 * is shown under the option's label, and read out after it, so the choice and its consequence
 * arrive together whichever field this is building. [spoken] is the same note in the words a
 * screen reader should say, when the printed one leans on a symbol.
 */
private fun <T> CindySheet.choiceGroup(
    title: String,
    options: List<T>,
    selected: T?,
    label: (T) -> String,
    note: (T) -> String?,
    spoken: (T) -> String? = note
): () -> T? {
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
                note(option)?.let {
                    addView(ctx.styledText(R.style.Cindy_Footnote, it).apply {
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
            describeAsButton(label(option) + (spoken(option)?.let { ", $it" } ?: ""))
        }
        group.row(row)
    }
    content.addView(group)
    return { chosen }
}
