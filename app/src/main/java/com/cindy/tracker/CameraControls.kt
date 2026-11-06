package com.cindy.tracker

/** Where the workout is, as the camera screen sees it. */
enum class WorkoutState { IDLE, SETUP, RUNNING, PAUSED, FINISHED }

/** The controls of the camera screen that the workout's state decides. */
enum class CameraControl { SWITCH_CAMERA, END, SHUTTER, MINUS, PLUS, SKIP }

/** What a control is at this moment. */
enum class Availability {
    /** Not on the screen. */
    ABSENT,

    /** On the screen, faded, and not answering a tap. */
    DIMMED,

    /** On the screen and answering a tap. */
    ENABLED
}

/** One control: whether it is there, whether it answers, and the name TalkBack speaks for it. */
data class ControlState(val availability: Availability, val name: String) {
    val present: Boolean get() = availability != Availability.ABSENT
    val enabled: Boolean get() = availability == Availability.ENABLED
}

/** Everything the camera screen needs to draw its controls for one state. */
class CameraControlPanel internal constructor(
    private val controls: Map<CameraControl, ControlState>,
    /** The state the camera screen is in once the session page has been closed, however it closed. */
    val afterSessionPage: WorkoutState
) {
    operator fun get(control: CameraControl): ControlState = controls.getValue(control)

    override fun equals(other: Any?): Boolean =
        other is CameraControlPanel && controls == other.controls && afterSessionPage == other.afterSessionPage

    override fun hashCode(): Int = 31 * controls.hashCode() + afterSessionPage.hashCode()
}

/**
 * The rules for the camera screen's controls, kept free of Android types so they can be tested
 * on their own, in one table: the activity draws what this answers and keeps no rule of its own.
 *
 * Today's rules, which the table pins:
 *  - the left slot of the action row is the camera switch until a workout is live, and END once
 *    it is. They share a position, so exactly one of the two is ever present;
 *  - the shutter is the run control and nothing else, and is inert only during the setup check;
 *  - the count editors act on a count, which only moves while the clock runs;
 *  - SKIP has a movement to leave during the check and during the workout;
 *  - a control with nothing to act on is dimmed and keeps its place, not hidden: you cannot
 *    learn where a control lives if it is only there half the time. The left slot is the
 *    exception that proves it: it never empties, it changes hands;
 *  - a finished workout is not left on the camera screen for the athlete to clear: closing the
 *    session page, by DONE, DISCARD or back, returns the screen to idle, so START is ready.
 *
 * The workout being filmed changes nothing today. It is an input so that the rules that do
 * depend on it (asking before a camera switch ends a film) have one place to go.
 */
object CameraControls {

    @Suppress("UNUSED_PARAMETER")
    fun of(state: WorkoutState, filming: Boolean): CameraControlPanel {
        val live = state == WorkoutState.RUNNING || state == WorkoutState.PAUSED
        return CameraControlPanel(
            controls = mapOf(
                CameraControl.SWITCH_CAMERA to ControlState(
                    if (live) Availability.ABSENT else Availability.ENABLED,
                    "Switch camera"
                ),
                CameraControl.END to ControlState(
                    if (live) Availability.ENABLED else Availability.ABSENT,
                    "End the workout"
                ),
                CameraControl.SHUTTER to ControlState(
                    // Inert during the check, and dimmed so that it reads as unavailable rather
                    // than broken: there is no workout yet to run or to pause.
                    if (state == WorkoutState.SETUP) Availability.DIMMED else Availability.ENABLED,
                    shutterName(state)
                ),
                CameraControl.MINUS to ControlState(
                    // Both editors refuse outside RUNNING, so a paused workout dims them too.
                    if (state == WorkoutState.RUNNING) Availability.ENABLED else Availability.DIMMED,
                    "Take back a rep"
                ),
                CameraControl.PLUS to ControlState(
                    if (state == WorkoutState.RUNNING) Availability.ENABLED else Availability.DIMMED,
                    "Add a rep"
                ),
                CameraControl.SKIP to ControlState(
                    if (state == WorkoutState.SETUP || live) Availability.ENABLED else Availability.DIMMED,
                    if (state == WorkoutState.SETUP) "Skip the setup check" else "Skip to the next movement"
                )
            ),
            // However the session page closes, the next workout is one tap on START away: the
            // clock full, round 1, the count at zero. The saved session is not touched by it.
            afterSessionPage = WorkoutState.IDLE
        )
    }

    private fun shutterName(state: WorkoutState): String = when (state) {
        WorkoutState.IDLE -> "Start the workout"
        WorkoutState.SETUP -> "Start — available once the setup check finishes"
        WorkoutState.RUNNING -> "Pause"
        WorkoutState.PAUSED -> "Resume"
        // Behind the session page, and never seen: closing it resets the screen. Named for what a
        // tap would do if it ever were seen.
        WorkoutState.FINISHED -> "Start the workout"
    }
}
