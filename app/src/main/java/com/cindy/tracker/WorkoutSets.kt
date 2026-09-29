package com.cindy.tracker

/**
 * What one movement of one round actually banked.
 *
 * This is the unit Strava's JSON `sets` array wants, and the only one honest to give it:
 * [reps] is what [WorkoutEngine.sets] says was banked, never a movement's target. [round] counts
 * from 1, matching how the app already talks about rounds everywhere else.
 */
data class WorkoutSet(val round: Int, val exercise: Exercise, val reps: Int)
