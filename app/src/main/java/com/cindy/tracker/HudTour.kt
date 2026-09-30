package com.cindy.tracker

import com.cindy.tracker.databinding.ActivityMainBinding

/**
 * What the tour says about each control on the camera screen, in the order it says it.
 *
 * Kept apart from [MainActivity] so that the same list can be laid against the inflated HUD in a
 * test, which is what catches a control that has been renamed or moved out from under its caption.
 * A control that is hidden when the tour starts is left out by [SpotlightView], so this list is the
 * whole tour and never the tour as it happens to run.
 */
object HudTour {

    fun steps(hud: ActivityMainBinding): List<SpotlightView.Step> = listOf(
        SpotlightView.Step(
            hud.btnStart, "Start",
            "Runs the setup check, then the 20-minute clock. Tap again to pause."
        ),
        SpotlightView.Step(
            hud.statusRow, "What Cindy sees",
            "A green dot means the next rep will count. When it won't, this line says why."
        ),
        SpotlightView.Step(
            hud.repBlock, "Your reps",
            "Reps against the target. −1 and +1 either side fix a miscount."
        ),
        SpotlightView.Step(
            hud.btnSkipExercise, "Skip",
            "Moves on to the next movement."
        ),
        SpotlightView.Step(
            hud.btnRec, "Record",
            "Films the workout with the count burned in, to your phone."
        ),
        SpotlightView.Step(
            hud.btnMenu, "Menu",
            "Your movements, voice, music, progress and help — set them between workouts."
        ),
        SpotlightView.Step(
            hud.btnFlip, "Flip",
            "Switches between the back and the front camera."
        )
    )
}
