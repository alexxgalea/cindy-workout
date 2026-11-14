package com.cindy.tracker

/**
 * What the camera screen's bottom band writes under its controls when the athlete is at the
 * phone: the word under each enabled control, and in idle the one line under the shutter.
 *
 * These are labels only. What a screen reader says for a control is still the name
 * [CameraControls] gives it, so a label is never a second stop for TalkBack. While the clock runs
 * the athlete is at the bar, where small text cannot be read, so nothing is written.
 *
 * Kept free of Android types so the table can be tested on its own, like [CameraControls].
 */
data class ControlNames(
    val end: String?,
    val shutter: String?,
    val skip: String?,
    /** The line under the shutter in idle: the screen's one line of text, in the shutter's place. */
    val idleLine: String?
) {

    companion object {
        /**
         * The names for [state], from the controls [panel] says are enabled: a dimmed or absent
         * control has no name. A finished workout sits behind the session page and is drawn as
         * idle, so it reads the same.
         */
        fun of(state: WorkoutState, panel: CameraControlPanel): ControlNames = when (state) {
            WorkoutState.RUNNING -> ControlNames(null, null, null, null)
            WorkoutState.IDLE, WorkoutState.FINISHED -> ControlNames(null, null, null, CameraControls.IDLE_LINE)
            WorkoutState.SETUP, WorkoutState.PAUSED -> ControlNames(
                end = "END".takeIf { panel[CameraControl.END].enabled },
                shutter = "RESUME".takeIf { state == WorkoutState.PAUSED && panel[CameraControl.SHUTTER].enabled },
                skip = "SKIP".takeIf { panel[CameraControl.SKIP].enabled },
                idleLine = null
            )
        }

        /**
         * Whether the coaching pill is on the picture. Setup and a pause show it with their
         * lines. Idle does not: its one line is under the shutter, so the pill appears there only
         * for something the athlete has to be told (the camera is unavailable, say), which is
         * what [statusBlank] false means. A finished workout is drawn as idle.
         */
        fun pillShown(state: WorkoutState, statusBlank: Boolean): Boolean = when (state) {
            WorkoutState.SETUP, WorkoutState.RUNNING, WorkoutState.PAUSED -> true
            WorkoutState.IDLE, WorkoutState.FINISHED -> !statusBlank
        }
    }
}
