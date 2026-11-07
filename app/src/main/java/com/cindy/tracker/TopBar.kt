package com.cindy.tracker

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.util.AttributeSet
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.core.view.ViewCompat

/**
 * The bar every navigation page closes from: a back control at the leading edge and the page's
 * title in the middle (ADR 0007).
 *
 * It replaces the full-width DONE pill. A bottom bar now means an action that does something
 * (SAVE, DISCARD, END), and leaving a page is a thing the top of the page and the system back
 * gesture already say.
 *
 * Pressing the control asks the activity's back dispatcher, which is what the gesture does, so
 * the two cannot drift apart: whatever a page does with back, the control does too. A page that
 * needs something else sets [onBack].
 *
 * The control is 48dp square, the minimum target, and is named "Back" for TalkBack. The title is
 * centred on the bar rather than on the space the control leaves, by keeping the same margin
 * either side, and is announced as a heading.
 */
class TopBar @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : FrameLayout(context, attrs) {

    private val back = ImageView(context).apply {
        setImageResource(R.drawable.ic_chevron_left)
        scaleType = ImageView.ScaleType.CENTER
        foreground = context.rowRipple()
        describeAsButton("Back")
        layoutParams = LayoutParams(context.dp(TARGET_DP), context.dp(TARGET_DP), Gravity.CENTER_VERTICAL or Gravity.START)
        setOnClickListener { goBack() }
    }

    private val titleView: TextView = context.styledText(R.style.Cindy_Headline).apply {
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
        ViewCompat.setAccessibilityHeading(this, true)
        layoutParams = LayoutParams(
            LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER
        ).apply {
            marginStart = context.dp(TARGET_DP)
            marginEnd = context.dp(TARGET_DP)
        }
    }

    /** What the page is called. */
    var title: CharSequence?
        get() = titleView.text
        set(value) {
            titleView.text = value
        }

    /** Replaces the default, which is the activity's own back. */
    var onBack: (() -> Unit)? = null

    init {
        minimumHeight = context.dp(BAR_DP)
        addView(titleView)
        addView(back)
        val styled = context.obtainStyledAttributes(attrs, R.styleable.TopBar)
        try {
            title = styled.getText(R.styleable.TopBar_title)
        } finally {
            styled.recycle()
        }
    }

    private fun goBack() {
        onBack?.let { return it() }
        var c: Context = context
        while (c is ContextWrapper && c !is Activity) c = c.baseContext
        (c as? ComponentActivity)?.onBackPressedDispatcher?.onBackPressed()
    }

    private companion object {
        /** The minimum touch target. */
        const val TARGET_DP = 48

        /** Eight dp of air above and below the target. */
        const val BAR_DP = 56
    }
}
