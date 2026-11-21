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
    val afterSessionPage: WorkoutState,
    /**
     * Whether a camera switch must ask first: true while a film is recording, because a switch
     * ends it. With no film running a switch happens at once.
     */
    val switchAsksFirst: Boolean
) {
    operator fun get(control: CameraControl): ControlState = controls.getValue(control)

    override fun equals(other: Any?): Boolean =
        other is CameraControlPanel && controls == other.controls && afterSessionPage == other.afterSessionPage &&
            switchAsksFirst == other.switchAsksFirst

    override fun hashCode(): Int =
        31 * (31 * controls.hashCode() + afterSessionPage.hashCode()) + switchAsksFirst.hashCode()
}

/**
 * The rules for the camera screen's controls, kept free of Android types so they can be tested
 * on their own, in one table: the activity draws what this answers and keeps no rule of its own.
 *
 * The rules, which the table pins:
 *  - the camera switch answers before the start and on a pause, where nothing is being counted
 *    and the phone may be turned or moved. While the check or the clock runs it is dimmed, not
 *    hidden, so it still teaches where it lives and cannot be knocked mid-set. It does not
 *    answer on a finished workout either: the session page has the last word there;
 *  - END has the left slot of the action row to itself, and is there while a workout is live;
 *  - the shutter is the run control and nothing else, and is inert only during the setup check;
 *  - the count editors act on a count, which only moves while the clock runs;
 *  - SKIP has a movement to leave during the check and during the workout;
 *  - a control with nothing to act on is dimmed and keeps its place, not hidden: you cannot
 *    learn where a control lives if it is only there half the time. END is the one
 *    exception: it exists only while there is a workout to leave;
 *  - a finished workout is not left on the camera screen for the athlete to clear: closing the
 *    session page, by its top bar, DISCARD or back, returns the screen to idle, so START is ready.
 *
 * Whether a film is recording changes no control. It only decides [CameraControlPanel.switchAsksFirst]:
 * a switch ends the film, so while one is recording the switch asks before it acts.
 */
object CameraControls {

    /**
     * What the status line says while the workout is idle. It names the shutter, which is what
     * starts the setup check, and is worded as a statement, not an invitation: the line itself
     * does nothing when it is touched.
     */
    const val IDLE_LINE = "Press the shutter to start the setup check"

    /**
     * The idle line with the chosen workout's name in front of it, "Cindy · Press the shutter to
     * start the setup check", so the athlete reads what the shutter will start before pressing it.
     * Written as text in the line the screen already has, not as a chip on the HUD.
     */
    fun idleLine(workout: Workout?): String = when {
        workout == null -> IDLE_LINE
        isFreestyle(workout) -> "${workout.name} · $IDLE_LINE_FREESTYLE"
        else -> "${workout.name} · $IDLE_LINE"
    }

    /** Freestyle's idle line: its shutter starts the clock at once, so there is no check to name. */
    const val IDLE_LINE_FREESTYLE = "Press the shutter to start"

    /** Whether [workout] is counted by recognition with no setup check: the free structure. */
    fun isFreestyle(workout: Workout?): Boolean = workout?.structure == Structure.FREE

    /** The state START leads to: Freestyle goes straight to running, Cindy to the setup check. */
    fun stateAfterStart(workout: Workout?): WorkoutState =
        if (isFreestyle(workout)) WorkoutState.RUNNING else WorkoutState.SETUP

    /**
     * The controls for [state], for the [workout] the shutter will start. Null, or Cindy, gives
     * the panels the camera screen always had. In Freestyle STOP stands in END's place and
     * SKIP is absent in every state, so its place stays empty and the shutter stays centred.
     */
    fun of(state: WorkoutState, filming: Boolean, workout: Workout? = null): CameraControlPanel {
        val freestyle = isFreestyle(workout)
        val live = state == WorkoutState.RUNNING || state == WorkoutState.PAUSED
        return CameraControlPanel(
            controls = mapOf(
                CameraControl.SWITCH_CAMERA to ControlState(
                    if (state == WorkoutState.IDLE || state == WorkoutState.PAUSED) {
                        Availability.ENABLED
                    } else {
                        Availability.DIMMED
                    },
                    "Switch camera"
                ),
                CameraControl.END to ControlState(
                    if (live) Availability.ENABLED else Availability.ABSENT,
                    if (freestyle) "Stop the workout" else "End the workout"
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
                    when {
                        freestyle -> Availability.ABSENT
                        state == WorkoutState.SETUP || live -> Availability.ENABLED
                        else -> Availability.DIMMED
                    },
                    if (state == WorkoutState.SETUP) "Skip the setup check" else "Skip to the next movement"
                )
            ),
            // However the session page closes, the next workout is one tap on START away: the
            // clock full, round 1, the count at zero. The saved session is not touched by it.
            afterSessionPage = WorkoutState.IDLE,
            switchAsksFirst = filming
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
