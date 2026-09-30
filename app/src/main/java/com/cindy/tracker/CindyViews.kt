package com.cindy.tracker

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ColorDrawable
import android.content.res.ColorStateList
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat

/**
 * The shared vocabulary the screens are built from.
 *
 * Every one of these existed already, written out longhand two or three times over: the tappable
 * row with a chevron lived in [MenuActivity], the label/value row in [ResultsActivity], the
 * rank/score row in [RecordsActivity] and again as a tier in [HelpActivity], and each had its own
 * paddings, its own text sizes and its own idea of what a screen reader should hear. Three copies
 * of a component are three components, and they had already drifted.
 *
 * Two conventions hold throughout:
 *
 * - **Styles are applied through the four-argument [TextView] constructor**, not
 *   `setTextAppearance`. A text appearance carries size, colour, family and letter spacing but
 *   *not* `lineSpacingMultiplier`, so prose set the second way loses its leading and quietly
 *   reverts to single-spaced.
 * - **A styled container is invisible to TalkBack.** Anything tappable that is not really a
 *   Button says so through [describeAsButton], and hides its own children so the row arrives as
 *   one node rather than three.
 */

fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

fun Context.dpf(value: Float): Float = value * resources.displayMetrics.density

/** A [TextView] carrying one of the type scale's styles in full. */
fun Context.styledText(styleRes: Int, text: CharSequence? = null): TextView =
    TextView(this, null, 0, styleRes).apply { text?.let { this.text = it } }

/**
 * Gives a view row layout params with a leading margin.
 *
 * A view built in code has **no** layoutParams until a parent adds it, so reaching for
 * `(layoutParams as LinearLayout.LayoutParams).marginStart` inside an `apply {}` is either a
 * crash (unsafe cast on null) or, with `as?`, a margin that silently never appears. Both of
 * those shipped; this exists so the choice cannot come up again.
 */
fun <T : View> T.withStartMargin(
    margin: Int,
    width: Int = ViewGroup.LayoutParams.WRAP_CONTENT,
    height: Int = ViewGroup.LayoutParams.WRAP_CONTENT
): T = apply {
    layoutParams = LinearLayout.LayoutParams(width, height).apply { marginStart = margin }
}

fun Context.eyebrow(text: String): TextView = styledText(R.style.Cindy_Eyebrow, text)

/** A filled circle: the status dot on the HUD, and the pips beside a list of movements. */
fun Context.dotDrawable(colourRes: Int): GradientDrawable = GradientDrawable().apply {
    shape = GradientDrawable.OVAL
    setColor(getColor(colourRes))
}

/**
 * Names a view to a screen reader and reports it as a button.
 *
 * Every control in this app is a styled [TextView] or [LinearLayout]; without this they are all
 * announced as static text, and their long-press actions do not exist at all.
 */
fun View.describeAsButton(label: String? = null, longPress: String? = null) {
    label?.let { contentDescription = it }
    isClickable = true
    isFocusable = true
    ViewCompat.setAccessibilityDelegate(this, object : AccessibilityDelegateCompat() {
        override fun onInitializeAccessibilityNodeInfo(
            host: View,
            info: AccessibilityNodeInfoCompat
        ) {
            super.onInitializeAccessibilityNodeInfo(host, info)
            info.className = Button::class.java.name
            longPress?.let {
                info.addAction(
                    AccessibilityNodeInfoCompat.AccessibilityActionCompat(
                        AccessibilityNodeInfoCompat.ACTION_LONG_CLICK, it
                    )
                )
            }
        }
    })
}

/** Touch feedback that stays inside a row's rounded corners. */
private fun Context.rowRipple(): RippleDrawable = RippleDrawable(
    ColorStateList.valueOf(Color.parseColor("#1FFFFFFF")),
    null,
    ColorDrawable(Color.WHITE)
)

/**
 * One card, with its rows hairline-divided.
 *
 * The old screens gave every row its own rounded rectangle and a 10dp gap, which reads as a pile
 * of unrelated cards rather than a list. Separators are inset to the text edge, as they are in a
 * grouped list on iOS, so the eye follows the column of titles rather than a ladder of full-width
 * rules.
 */
class InsetGroup(context: Context) : LinearLayout(context) {

    init {
        orientation = VERTICAL
        setBackgroundResource(R.drawable.glass_card)
        // So a row's ripple cannot square off the card's corners.
        clipToOutline = true
    }

    /** Adds [view], preceded by a separator unless it is the first row. */
    fun row(view: View) {
        if (childCount > 0) {
            addView(View(context).apply {
                setBackgroundColor(context.getColor(R.color.hairline))
            }, LayoutParams(LayoutParams.MATCH_PARENT, context.hairlinePx()).apply {
                marginStart = context.dp(18)
            })
        }
        addView(view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    /**
     * Adds [view] with no separator above it, so it reads as a continuation of the row before
     * rather than as an entry of its own. For the small print a row sometimes needs.
     */
    fun attach(view: View) {
        addView(view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }
}

/** A hairline is one physical pixel, not one dp — at 3x, a 1dp rule is a visible bar. */
fun Context.hairlinePx(): Int = maxOf(1, (resources.displayMetrics.density * 0.5f).toInt())

fun Context.insetGroup(build: InsetGroup.() -> Unit): InsetGroup =
    InsetGroup(this).apply(build)

/** The column of title over value that every row shares. */
private fun Context.rowText(title: CharSequence, detail: CharSequence?, titleStyle: Int): View =
    LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        // The row speaks for itself; its parts must not also be announced.
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(styledText(titleStyle, title))
        detail?.let {
            addView(styledText(R.style.Cindy_Footnote, it).apply {
                setPadding(0, dp(2), 0, 0)
                tag = ROW_DETAIL
            })
        }
    }

/** Marks the value line [rowText] builds, so [relabelNavRow] can find it again. */
private const val ROW_DETAIL = "cindy.row.detail"

private fun Context.rowFrame(tappable: Boolean, minHeight: Int = 64): LinearLayout =
    LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(minHeight)
        setPadding(dp(18), dp(14), dp(16), dp(14))
        if (tappable) foreground = rowRipple()
    }

private fun Context.chevron(): ImageView = ImageView(this).apply {
    setImageResource(R.drawable.ic_chevron_right)
    imageTintList = ColorStateList.valueOf(getColor(R.color.label_tertiary))
    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    layoutParams = LinearLayout.LayoutParams(dp(17), dp(17)).apply { marginStart = dp(12) }
}

/**
 * A row that opens something: what it is, what it is currently set to, and a chevron.
 *
 * The value is part of the row's spoken name as well as its look — announcing only "body weight"
 * would hide the very thing the row exists to report.
 */
fun Context.navRow(title: String, value: String, onTap: () -> Unit): View =
    rowFrame(tappable = true).apply {
        addView(rowText(title, value, R.style.Cindy_Headline))
        addView(chevron())
        setOnClickListener { onTap() }
        describeAsButton("$title, $value")
    }

/**
 * Changes what a [navRow] says under its title, where it stands.
 *
 * For a row whose value changes while it is on screen. Replacing the row instead would cancel a
 * tap that is under way on it: Android sends the finger's press a cancel when the view beneath
 * it is removed, so a list rebuilt several times a second cannot be tapped at all.
 */
fun View.relabelNavRow(title: String, value: String) {
    val detail = findViewWithTag<TextView>(ROW_DETAIL) ?: return
    if (detail.text.toString() == value) return
    detail.text = value
    contentDescription = "$title, $value"
}

/** A label and its figure. Tappable rows get a chevron and say so. */
fun Context.statRow(
    label: String,
    value: CharSequence,
    onTap: (() -> Unit)? = null
): View = rowFrame(tappable = onTap != null, minHeight = 52).apply {
    addView(styledText(R.style.Cindy_Body, label).apply {
        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    })
    addView(styledText(R.style.Cindy_Headline, value).apply {
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    })
    onTap?.let { tap ->
        addView(chevron())
        setOnClickListener { tap() }
        describeAsButton("$label, $value, tap to change")
    }
}

/** A leaderboard row: rank, who, when, and the score in metric type. */
fun Context.rankRow(
    rank: String,
    name: String,
    detail: String,
    score: String,
    mine: Boolean,
    best: Boolean
): View = rowFrame(tappable = false).apply {
    // The athlete's own rows sit on a slightly brighter film; the benchmark recedes.
    if (mine) setBackgroundColor(getColor(R.color.surface_glass))
    addView(styledText(R.style.Cindy_Callout, rank).apply {
        layoutParams = LinearLayout.LayoutParams(dp(22), ViewGroup.LayoutParams.WRAP_CONTENT)
        setTextColor(getColor(R.color.label_tertiary))
    })
    addView(LinearLayout(this@rankRow).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(styledText(R.style.Cindy_Headline, name).apply {
                if (mine) useExtraBold()
            })
            if (best) addView(badge("BEST").withStartMargin(dp(7)))
        })
        addView(styledText(R.style.Cindy_Footnote, detail).apply { setPadding(0, dp(2), 0, 0) })
    })
    addView(styledText(R.style.Cindy_MetricS, score).apply {
        if (!mine) setTextColor(getColor(R.color.label_secondary))
    }.withStartMargin(dp(10)))
    contentDescription = "$rank, $name, $score, $detail"
}

/** Lifts one word to the heaviest weight without disturbing the rest of its style. */
private fun TextView.useExtraBold() {
    typeface = androidx.core.content.res.ResourcesCompat.getFont(context, R.font.manrope_extrabold)
}

/** A small filled marker. Reserved for facts, never decoration. */
fun Context.badge(text: String): TextView = styledText(R.style.Cindy_Eyebrow, text).apply {
    setTextColor(getColor(R.color.on_primary))
    setBackgroundResource(R.drawable.btn_primary)
    setPadding(dp(6), dp(2), dp(6), dp(2))
    textSize = 9.5f
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
    )
}

/** The one filled control on a screen. */
fun Context.primaryButton(text: String): TextView =
    styledText(R.style.Cindy_Button, text).apply {
        setTextColor(getColor(R.color.on_primary))
        setBackgroundResource(R.drawable.btn_primary)
        foreground = rowRipple()
        gravity = Gravity.CENTER
        layoutParams = LinearLayout.LayoutParams(0, dp(54), 1f)
        describeAsButton()
    }

/** Everything else. */
fun Context.glassButton(text: String, tint: Int = R.color.label): TextView =
    styledText(R.style.Cindy_Button_Small, text).apply {
        setTextColor(getColor(tint))
        setBackgroundResource(R.drawable.btn_glass)
        foreground = rowRipple()
        gravity = Gravity.CENTER
        setPadding(dp(20), 0, dp(20), 0)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, dp(54)
        ).apply { marginEnd = dp(10) }
        describeAsButton()
    }

/** The row of actions every secondary screen ends with, in the thumb's reach. */
fun Context.actionBar(vararg buttons: View): LinearLayout = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(22) }
    buttons.forEach { addView(it) }
}

/**
 * One option in a segmented choice — metric, range, category.
 *
 * The pill is 36dp but the target is 48dp: the inset keeps the row light without shrinking what
 * a wet thumb has to hit.
 */
fun Context.chip(text: String, selected: Boolean, onTap: () -> Unit): TextView =
    styledText(R.style.Cindy_Button_Small, text).apply {
        textSize = 13f
        setTextColor(getColor(if (selected) R.color.on_primary else R.color.label_secondary))
        val pill = GradientDrawable().apply {
            cornerRadius = dpf(18f)
            if (selected) {
                setColor(getColor(R.color.primary_fill))
            } else {
                setColor(getColor(R.color.surface_glass_raised))
                setStroke(hairlinePx(), getColor(R.color.hairline))
            }
        }
        background = InsetDrawable(pill, 0, dp(6), 0, dp(6))
        gravity = Gravity.CENTER
        minWidth = dp(48)
        setPadding(dp(14), 0, dp(14), 0)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, dp(48)
        ).apply { marginEnd = dp(6) }
        setOnClickListener { onTap() }
        describeAsButton(if (selected) "$text, selected" else text)
    }

/** A row of [chip]s; [onSelect] fires only when the choice actually changes. */
fun Context.chipRow(options: List<String>, selected: Int, onSelect: (Int) -> Unit): LinearLayout =
    LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        options.forEachIndexed { i, label ->
            addView(chip(label, i == selected) { if (i != selected) onSelect(i) })
        }
    }

/**
 * A trophy: a disc with its place in it. First is the earned colour; second and third step down
 * the label ramp rather than borrowing metal colours the palette does not have.
 */
fun Context.medal(rank: Int): TextView = styledText(R.style.Cindy_Eyebrow, "$rank").apply {
    textSize = 12f
    letterSpacing = 0f
    setTextColor(getColor(R.color.on_primary))
    gravity = Gravity.CENTER
    background = dotDrawable(
        when (rank) {
            1 -> R.color.achievement
            2 -> R.color.label
            else -> R.color.label_secondary
        }
    )
    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    layoutParams = LinearLayout.LayoutParams(dp(28), dp(28))
}

/** A trophy row: medal, what it is and when, and the figure. */
fun Context.peakRow(rank: Int, title: String, detail: String, value: String): View =
    rowFrame(tappable = false, minHeight = 60).apply {
        addView(medal(rank))
        addView(rowText(title, detail, R.style.Cindy_Headline).apply {
            // rowText assigns LinearLayout.LayoutParams itself, so this cast is safe.
            (layoutParams as LinearLayout.LayoutParams).marginStart = dp(14)
        })
        addView(styledText(R.style.Cindy_MetricS, value).withStartMargin(dp(10)))
        contentDescription = "$title, $value, $detail"
    }
