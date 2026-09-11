package com.cindy.tracker

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
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

        binding.actions.addView(primaryButton("DONE").apply {
            setOnClickListener { finish() }
        })
        render()
    }

    /**
     * Rebuilt rather than patched, because a row's subtitle is derived from state a dialog may
     * just have changed, and there are four rows.
     */
    private fun render() {
        binding.rows.removeAllViews()

        val movements = profile.movements
        val sessions = records.all().size

        binding.rows.addView(insetGroup {
            row(navRow("Movements", movements.label()) {
                if (workoutLive) {
                    toast("Reset the workout first to change movements")
                } else {
                    chooseMovements(movements) { chosen ->
                        profile.movements = chosen
                        toast(chosen.label())
                        render()
                    }
                }
            })
            row(navRow(
                "Records",
                when (sessions) {
                    0 -> "No sessions yet"
                    1 -> "1 session"
                    else -> "$sessions sessions"
                }
            ) { startActivity(Intent(this@MenuActivity, RecordsActivity::class.java)) })
            row(navRow(
                "Body weight",
                if (profile.hasBodyWeight) {
                    "%.0f kg".format(Locale.US, profile.bodyWeightKg)
                } else {
                    "Not set — calories need it"
                }
            ) { askBodyWeight(profile) { render() } })
            row(navRow(
                "Help",
                "What Cindy is, how it is scored, and where to stand"
            ) { startActivity(Intent(this@MenuActivity, HelpActivity::class.java)) })
        })

        // Said here rather than only when the row is tapped, because it explains why the row
        // will refuse rather than reporting the refusal after the fact.
        if (workoutLive) {
            binding.rows.addView(
                styledText(
                    R.style.Cindy_Footnote,
                    "Movements can only be changed between workouts — they have to mean one " +
                        "thing for the whole score."
                ).apply { setPadding(dp(4), dp(14), dp(4), 0) }
            )
        }
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
