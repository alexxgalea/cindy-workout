package com.cindy.tracker

/**
 * Whether a workout is on the clock in this process, so a reminder cannot interrupt the very
 * session it was meant to prompt. A dead process has no workout, which is also the right answer.
 */
object LiveWorkout {
    @Volatile var active: Boolean = false
}
