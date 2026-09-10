package com.cindy.tracker

import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import com.cindy.tracker.databinding.ActivityMenuBinding
import java.util.Locale

/**
 * Everything the athlete does not need while they are on the bar.
 *
 * The camera HUD had grown to six chips — voice, music, rec, records, help and moves — which at
 * a 48dp minimum touch target plus margins wanted more width than a 360dp phone has, so the row
 * ran off the edge of the screen. The split is not by importance but by *when*: voice, music and
 * recording change state mid-set and stay on the HUD; navigation and configuration are things
 * you settle before the clock starts, and they live here.
 *
 * This is deliberately not a home screen. The app still opens straight to the camera — a screen
 * between the launcher and the workout would cost a tap before every session and throw away
 * CameraX warm-up time. The menu is a place you go, not a place you land.
 *
 * Each row carries its current value as a subtitle, so the answer to "what am I set to?" does
 * not require opening the row to find out.
 */
class MenuActivity : AppCompatActivity() {

    companion object {
        /**
         * Whether a workout is live. The movement picker is refused while one is, because the
         * movements have to mean one thing for the whole score — and only [MainActivity] knows.
         */
        private const val EXTRA_WORKOUT_LIVE = "workout_live"

        fun intent(context: Context, workoutLive: Boolean): Intent =
            Intent(context, MenuActivity::class.java)
                .putExtra(EXTRA_WORKOUT_LIVE, workoutLive)
    }

    private lateinit var binding: ActivityMenuBinding
    private lateinit var profile: Profile
    private lateinit var records: RecordStore
    private var workoutLive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMenuBinding.inflate(layoutInflater)
        setContentView(binding.root)

        profile = Profile(this)
        records = RecordStore(this)
        workoutLive = intent.getBooleanExtra(EXTRA_WORKOUT_LIVE, false)

        binding.btnBack.setOnClickListener { finish() }
        render()
    }

    /**
     * Rebuilt rather than patched, because a row's subtitle is derived from state a dialog may
     * just have changed, and there are four rows.
     */
    private fun render() {
        binding.rows.removeAllViews()

        val movements = profile.movements
        row(
            title = "MOVEMENTS",
            value = movements.label()
        ) {
            if (workoutLive) {
                toast("Reset the workout first to change movements")
            } else {
                chooseMovements(movements) { chosen ->
                    profile.movements = chosen
                    toast(chosen.label())
                    render()
                }
            }
        }

        val sessions = records.all().size
        row(
            title = "RECORDS",
            value = when (sessions) {
                0 -> "No sessions yet"
                1 -> "1 session"
                else -> "$sessions sessions"
            }
        ) { startActivity(Intent(this, RecordsActivity::class.java)) }

        row(
            title = "BODY WEIGHT",
            value = if (profile.hasBodyWeight) {
                "%.0f kg".format(Locale.US, profile.bodyWeightKg)
            } else {
                "Not set — calories need it"
            }
        ) { askBodyWeight(profile) { render() } }

        row(
            title = "HELP",
            value = "What Cindy is, how it is scored, and where to stand"
        ) { startActivity(Intent(this, HelpActivity::class.java)) }
    }

    /**
     * A tappable row: what it is, what it is currently set to, and a chevron.
     *
     * The subtitle is part of the row's name for a screen reader as well as for the eye —
     * announcing only "body weight" would hide the very thing the row exists to report.
     */
    private fun row(
        title: String,
        value: String,
        onTap: () -> Unit
    ) {
        val text = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(TextView(context).apply {
                this.text = title
                letterSpacing = 0.12f
                setTextColor(getColor(R.color.on_surface))
                textSize = 15f
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(context).apply {
                this.text = value
                setTextColor(getColor(R.color.on_surface_dim))
                textSize = 12f
                setPadding(0, dp(3), 0, 0)
            })
        }

        val chevron = TextView(this).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            this.text = "›"
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 22f
            setPadding(dp(12), 0, 0, 0)
        }

        binding.rows.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundResource(R.drawable.bg_row)
            minimumHeight = dp(64)
            setPadding(dp(16), dp(12), dp(16), dp(12))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }
            addView(text)
            addView(chevron)
            isClickable = true
            isFocusable = true
            contentDescription = "$title, $value"
            setOnClickListener { onTap() }
            // A styled LinearLayout draws like a button and is silent to a screen reader. Its
            // own children are hidden above, so the row arrives as one node rather than three.
            ViewCompat.setAccessibilityDelegate(this, object : AccessibilityDelegateCompat() {
                override fun onInitializeAccessibilityNodeInfo(
                    host: View,
                    info: AccessibilityNodeInfoCompat
                ) {
                    super.onInitializeAccessibilityNodeInfo(host, info)
                    info.className = Button::class.java.name
                }
            })
        })
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
