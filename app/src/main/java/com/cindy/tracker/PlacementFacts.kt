package com.cindy.tracker

import android.content.Context
import android.content.res.ColorStateList
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout

/**
 * Three facts about where the phone goes, one line each, rather than a paragraph nobody reads on
 * the way to a bar.
 *
 * Shared by the sheet that opens before the first setup check and by the first-launch pages, so
 * that the two cannot drift into giving different advice about the one thing the athlete has to
 * get right.
 */
fun Context.placementFacts(): LinearLayout = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
    )
    listOf(
        R.drawable.ic_phone_stand to "Stand the phone up rather than laying it flat.",
        R.drawable.ic_frame to "Keep your head and your feet both in shot.",
        R.drawable.ic_dont_move to
            "Then leave it there — moving it mid-workout resets what it has learned."
    ).forEachIndexed { index, (icon, text) ->
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, if (index == 0) dp(18) else dp(13), 0, 0)
            addView(ImageView(context).apply {
                setImageResource(icon)
                imageTintList = ColorStateList.valueOf(
                    getColor(
                        if (icon == R.drawable.ic_dont_move) R.color.state_caution
                        else R.color.label_tertiary
                    )
                )
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(17), dp(17)).apply { topMargin = dp(2) })
            addView(styledText(R.style.Cindy_Callout, text).apply {
                setTextColor(getColor(R.color.label_body))
                setPadding(dp(11), 0, 0, 0)
            })
        })
    }
}
