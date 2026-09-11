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
import android.widget.SeekBar
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

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
 * Callers: the placement guide, the movement picker, the body-weight prompt and the two audio
 * sheets behind the menu's voice and music rows.
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

        // The sheet is flush with the bottom edge, so it owns the gesture bar's space itself —
        // and the keyboard's, which is the whole reason the body-weight field became unusable.
        // A sheet pinned to the bottom of a full-screen window simply sits *behind* the IME: the
        // athlete could tap the field and then see neither what they were typing nor the SAVE
        // button underneath it. Taking the larger of the two keeps one rule for both.
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars()).bottom
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            sheet.setPadding(ctx.dp(20), ctx.dp(12), ctx.dp(20), ctx.dp(28) + maxOf(bars, ime))
            insets
        }

        dialog.setContentView(root)
        dialog.window?.apply {
            setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT
            )
            setGravity(Gravity.BOTTOM)
            // The sheet draws its own insets, so the decor must not also reserve them.
            WindowCompat.setDecorFitsSystemWindows(this, false)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            matchHostSystemBars(this)
        }
    }

    /**
     * Gives the sheet's window the same system-bar state as the screen behind it.
     *
     * A dialog opens a window of its own, and that window arrives with the *default* bar state
     * however the activity beneath it is configured. Over the camera — which hides the bars for
     * the workout, the way a camera app does — the effect was a visible fault: opening any sheet
     * brought the status and navigation bars back, which re-laid out the bands and the preview
     * under them, and MainActivity's onWindowFocusChanged then hid them again and laid the whole
     * screen out a second time. Two full relayouts in a few frames is what a tester was seeing
     * and describing as the popups going big for a moment.
     *
     * Asked of the live insets rather than passed in by the caller, so a screen that changes its
     * mind — or a new screen that never thinks about it — cannot get a different answer.
     */
    private fun matchHostSystemBars(window: android.view.Window) {
        val hostBarsVisible = ViewCompat.getRootWindowInsets(activity.window.decorView)
            ?.isVisible(WindowInsetsCompat.Type.systemBars()) ?: true
        if (hostBarsVisible) return
        WindowInsetsControllerCompat(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    /**
     * A labelled 0..1 slider, with its current value read out beside the label.
     *
     * [onChange] fires continuously while the grip is dragged, which is what makes a volume
     * audible as it is set rather than only once it is let go. [onSettled] fires once, when the
     * athlete stops — the place to start a preview, which would stutter if it were restarted on
     * every pixel of the drag.
     */
    fun slider(
        label: String,
        value: Float,
        onChange: (Float) -> Unit,
        onSettled: (Float) -> Unit = {}
    ): CindySheet {
        val ctx: Context = activity
        val readout = ctx.styledText(R.style.Cindy_Headline, percent(value)).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        val bar = SeekBar(ctx).apply {
            max = 100
            progress = (value * 100f).toInt()
            progressDrawable = ctx.getDrawable(R.drawable.track)
            thumb = ctx.getDrawable(R.drawable.slider_thumb)
            // The drawable is 20dp; the offset stops the grip from being clipped at either end.
            thumbOffset = 0
            splitTrack = false
            setPadding(ctx.dp(10), ctx.dp(12), ctx.dp(10), ctx.dp(12))
            contentDescription = label
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) {
                    val v = progress / 100f
                    readout.text = percent(v)
                    if (fromUser) onChange(v)
                }

                override fun onStartTrackingTouch(bar: SeekBar) = Unit
                override fun onStopTrackingTouch(bar: SeekBar) = onSettled(bar.progress / 100f)
            })
        }

        body.addView(LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card_small)
            setPadding(ctx.dp(16), ctx.dp(12), ctx.dp(16), ctx.dp(10))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = ctx.dp(14) }

            addView(LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(ctx.styledText(R.style.Cindy_Callout, label).apply {
                    setTextColor(ctx.getColor(R.color.label))
                    layoutParams = LinearLayout.LayoutParams(
                        0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                    )
                })
                addView(readout)
            })
            addView(bar)
        })
        return this
    }

    private fun percent(value: Float): String = "${(value * 100f).toInt()}%"

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
        onSecondary: (() -> Unit)? = null,
        /**
         * Whether the secondary button closes the sheet. False for the one kind that does not:
         * a preview, which exists to be heard *against the sliders that are still on screen* and
         * would be pointless if tapping it took them away.
         */
        secondaryDismisses: Boolean = true,
        /**
         * What the secondary is painted in. The alert colour for a destructive action, which is
         * the case where the secondary is the one that does something rather than the one that
         * gets out — see [RecordsActivity.confirmClear] for why it is arranged that way round.
         */
        secondaryTint: Int = R.color.label
    ): CindySheet {
        secondary?.let { label ->
            actions.addView(activity.glassButton(label, secondaryTint).apply {
                setOnClickListener {
                    onSecondary?.invoke()
                    if (secondaryDismisses) dialog.dismiss()
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

    /**
     * Runs [block] when the sheet closes, however it closes.
     *
     * Set on the dialog rather than on the buttons because the back gesture and a tap outside
     * are both ways out, and a preview left playing after one of those is a track the athlete
     * has no control left to stop.
     */
    fun onDismiss(block: () -> Unit): CindySheet {
        dialog.setOnDismissListener { block() }
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
