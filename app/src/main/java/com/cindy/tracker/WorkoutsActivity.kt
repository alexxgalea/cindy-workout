package com.cindy.tracker

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityWorkoutsBinding

/**
 * Workouts: the catalog, one row per workout, with the chosen one checked.
 *
 * Each row is the workout's name over its format and its one line ("20-minute AMRAP · Rounds of
 * 5 pull-ups, 10 push-ups and 15 squats, as many as you can."). A tap gives the row its check and
 * is saved there and then, as on [MovementsActivity]: there is no SAVE, and the page is left from
 * its top bar or with back.
 *
 * Opened from the menu's Workout row, and by itself from the camera screen at first launch and
 * when an update brings a workout the athlete has not seen, once the catalog has more than one
 * ([Onboarding.shouldShowWorkouts]). Opening it, by either way, is seeing the whole catalog, so it
 * marks every workout seen.
 *
 * The menu refuses to open this while a workout is live, and the camera screen takes the choice up
 * when it resumes, so the page itself holds no rule about either.
 */
class WorkoutsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityWorkoutsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityWorkoutsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        val profile = Profile(this)
        FirstRun(this).workoutsSeen = Workouts.catalog.map { it.id }.toSet()

        binding.choices.addView(choiceSection(
            "WORKOUTS", Workouts.catalog, profile.workout, { it.name }, ::detail
        ) { profile.workout = it })

        // What choosing does to the score, said where the choice is.
        binding.choices.addView(
            styledText(
                R.style.Cindy_Footnote,
                "Records, levels and badges are kept per workout, so a session of one never " +
                    "moves another's. Your streaks count every session."
            ).apply { setPadding(dp(4), dp(14), dp(4), 0) },
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }

    companion object {
        /** "20-minute AMRAP · Rounds of 5 pull-ups, 10 push-ups and 15 squats, as many as you can." */
        fun detail(workout: Workout): String = "${workout.format} · ${workout.description}"

        fun intent(context: Context): Intent = Intent(context, WorkoutsActivity::class.java)
    }
}
