package com.cindy.tracker

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * The app's own bottom sheet, in place of [android.app.AlertDialog].
 *
 * A platform alert is the one surface here that cannot be brought into the design: its title, its
 * buttons, its checkbox and its square corners come from the Material theme and ignore everything
 * in `type.xml`. That mattered most on the very first screen a new athlete ever saw — the
 * placement guide — where a carefully drawn diagram sat inside a dialog belonging to a different
 * application.
 *
 * It also sits *over the live preview* rather than over a grey scrim, which the placement guide
 * in particular wants: you can see your own room while you read where to stand in it.
 *
 * Three callers: the placement guide, the movement picker and the body-weight prompt.
 */
class CindySheet(
    private val activity: Activity,
    title: String,
    subtitle: String? = null
) {

    private val dialog = Dialog(activity, R.style.Theme_Cindy_Sheet)
    private val sheet: LinearLayout
    private val body: LinearLayout
    private val actions: LinearLayout

    /** Views added here become the sheet's content, between the subtitle and the buttons. */
    val content: LinearLayout get() = body

    init {
        val ctx: Context = activity

        body = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        actions = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = ctx.dp(18) }
        }

        // Capped rather than free: a long sheet must not push its own buttons off the screen.
        val scroller = object : ScrollView(ctx) {
            private val maxHeight = (ctx.resources.displayMetrics.heightPixels * 0.60f).toInt()
            override fun onMeasure(widthSpec: Int, heightSpec: Int) {
                super.onMeasure(
                    widthSpec,
                    MeasureSpec.makeMeasureSpec(maxHeight, MeasureSpec.AT_MOST)
                )
            }
        }.apply {
            isFillViewport = false
            overScrollMode = View.OVER_SCROLL_NEVER
            addView(
                body,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }

        sheet = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_sheet)
            setPadding(ctx.dp(20), ctx.dp(12), ctx.dp(20), ctx.dp(28))

            addView(View(ctx).apply {
                setBackgroundResource(R.drawable.sheet_handle)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(ctx.dp(38), ctx.dp(4)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = ctx.dp(20)
            })

            addView(ctx.styledText(R.style.Cindy_Title2, title))
            subtitle?.let {
                addView(ctx.styledText(R.style.Cindy_Callout, it).apply {
                    setPadding(0, ctx.dp(5), 0, 0)
                })
            }
            addView(scroller, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = ctx.dp(18) })
            addView(actions)
        }

        val root = FrameLayout(ctx).apply {
            addView(sheet, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.BOTTOM })
        }

        // The sheet is flush with the bottom edge, so it owns the gesture bar's space itself.
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bottom = insets.getInsets(WindowInsetsCompat.Type.systemBars()).bottom
            sheet.setPadding(ctx.dp(20), ctx.dp(12), ctx.dp(20), ctx.dp(28) + bottom)
            insets
        }

        dialog.setContentView(root)
        dialog.window?.apply {
            setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT
            )
            setGravity(Gravity.BOTTOM)
        }
    }

    /** A switch row, in place of a Material checkbox. */
    fun toggle(label: String, checked: Boolean, onChange: (Boolean) -> Unit): CindySheet {
        val ctx: Context = activity
        var on = checked

        val thumb = View(ctx).apply { setBackgroundResource(R.drawable.toggle_thumb) }
        val track = FrameLayout(ctx).apply {
            setBackgroundResource(
                if (on) R.drawable.toggle_track_on else R.drawable.toggle_track_off
            )
            addView(thumb, FrameLayout.LayoutParams(ctx.dp(23), ctx.dp(23)).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = ctx.dp(2)
            })
        }
        thumb.translationX = if (on) ctx.dpf(20f) else 0f

        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundResource(R.drawable.glass_card_small)
            minimumHeight = ctx.dp(52)
            setPadding(ctx.dp(16), ctx.dp(8), ctx.dp(12), ctx.dp(8))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = ctx.dp(20) }

            addView(ctx.styledText(R.style.Cindy_Callout, label).apply {
                setTextColor(ctx.getColor(R.color.label))
                layoutParams = LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                )
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            })
            addView(track, LinearLayout.LayoutParams(ctx.dp(47), ctx.dp(28)))

            setOnClickListener {
                on = !on
                track.setBackgroundResource(
                    if (on) R.drawable.toggle_track_on else R.drawable.toggle_track_off
                )
                thumb.animate().translationX(if (on) ctx.dpf(20f) else 0f)
                    .setDuration(160).start()
                stateDescription(this, label, on)
                onChange(on)
            }
        }
        stateDescription(row, label, on)
        row.describeAsButton()
        body.addView(row)
        return this
    }

    private fun stateDescription(row: View, label: String, on: Boolean) {
        row.contentDescription = "$label, ${if (on) "on" else "off"}"
    }

    /**
     * The buttons. [primary] is the filled one and there is never more than a single one of those.
     */
    fun actions(
        primary: String,
        onPrimary: () -> Unit,
        secondary: String? = null,
        onSecondary: (() -> Unit)? = null
    ): CindySheet {
        secondary?.let { label ->
            actions.addView(activity.glassButton(label).apply {
                setOnClickListener {
                    onSecondary?.invoke()
                    dialog.dismiss()
                }
            })
        }
        actions.addView(activity.primaryButton(primary).apply {
            setOnClickListener {
                onPrimary()
                dialog.dismiss()
            }
        })
        return this
    }

    /** Adds a view to the content area and returns the sheet, for chaining. */
    fun add(view: View): CindySheet {
        body.addView(view)
        return this
    }

    fun show() = dialog.show()

    fun dismiss() = dialog.dismiss()
}
