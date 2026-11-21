package com.cindy.tracker

/** The movement's line before recognition has confirmed one: the workout's name and its format. */
const val FREESTYLE_IDLE_LINE = "Freestyle · Count up"

/**
 * What the Freestyle scoreboard reads.
 *
 * [figure] is the reps since the movement last changed: no target, no slash, and a rest inside one
 * movement never resets it. [line] is "PUSH-UPS · 42 total", or [FREESTYLE_IDLE_LINE] before the
 * first confirmation. [adjustable] is whether − and + may act: false until a movement is
 * recognised, and while the clock is stopped.
 */
data class FreestyleReadout(
    val figure: Int,
    val movement: Movement?,
    val movementTotal: Int,
    val adjustable: Boolean
) {
    /** Built on read, so a frame whose readout is never drawn builds no string. */
    val line: String get() = if (movement == null) FREESTYLE_IDLE_LINE else "${movement.label} · $movementTotal total"
}

/** A change to what is banked. Banked is banked: the figure, the totals and the session record follow these. */
sealed interface FreestyleEvent {
    /** [reps] reps of [movement] were banked at once: 2 at a confirmation, 1 after, 1 for a tap of +. */
    data class Banked(
        val movement: Movement,
        val reps: Int,
        val figure: Int,
        val total: Int,
        val manual: Boolean = false
    ) : FreestyleEvent

    /** One rep was taken back with −. */
    data class TakenBack(val movement: Movement, val figure: Int, val total: Int) : FreestyleEvent
}

/** What the voice is to say. Never dropped by the caller: a count is an event, not state. */
sealed interface FreestyleVoice {
    /** The movement's name and its count, as one: "Push-ups. Two." */
    data class Confirmed(val movement: Movement, val count: Int) : FreestyleVoice

    /** The figure, said as Cindy's counts are. */
    data class Count(val count: Int) : FreestyleVoice
}

/** What one input gave back: the readout as it now stands, and what happened to bring it there. */
data class FreestyleFrame(
    val readout: FreestyleReadout,
    val events: List<FreestyleEvent> = emptyList(),
    val voice: List<FreestyleVoice> = emptyList()
)

/**
 * What STOP files: the clock time (pauses excluded), the pause time, the totals per movement, how
 * many reps were tapped in, and when each rep banked. The sets are worked out from [marks] at STOP.
 */
data class FiledSession(
    val durationMs: Long,
    val pausedMs: Long,
    val totals: Map<Exercise, Int>,
    val manualReps: Int,
    val marks: List<RepMark>,
    /** Clock time the camera could not read the athlete, as Cindy files it: a floor under the total, not an exact count. */
    val untrackedMs: Long = 0L,
    /** The sets worked out from [marks] at STOP ([FreestyleSets.derive]). */
    val sets: List<FreestyleSet> = FreestyleSets.derive(marks).sets
) {
    val totalReps: Int get() = totals.values.sum()
}

/**
 * Counts a Freestyle (ADR 0010): recognition names the movement and counts its reps, and this
 * banks what recognition counts. There is no target, no round and no setup check. The workout
 * engine and Cindy's counting are not touched; [Recogniser] drives its own engines.
 *
 * Inputs: [onFrame] (keypoints, the frame's time, whether identity is stable), [start], [pause],
 * [resume], [stop], [minus] and [plus]. Every time is the same millisecond clock the frames carry.
 * Outputs: a [FreestyleFrame] (readout, banked-rep events, voice), and from [stop] a
 * [FiledSession], or null when no rep was banked, so an empty session files nothing.
 *
 * A movement is confirmed at its 2nd counted rep and both reps are banked then; a lone rep banks
 * and shows nothing. − and + act on the recognised movement. Frames while paused or before START
 * count nothing.
 *
 * Threads: the camera thread calls [onFrame] and the main thread the rest, so every call is
 * synchronised.
 */
class FreestyleEngine(private val profile: CindyProfile = CindyProfile.STANDARD) {

    private var recogniser = Recogniser(profile)
    private var started = false
    private var startedAt = 0L
    private var pausedMs = 0L
    private var pausedAt: Long? = null

    private var seen: Map<Movement, Int> = Recognition.NO_REPS
    private var shown: Movement? = null
    private var figure = 0
    private val banked = Movement.entries.associateWithTo(mutableMapOf()) { 0 }
    private val marks = mutableListOf<RepMark>()
    private var manual = 0

    /**
     * How well the camera reads the athlete in the position that is entered: the same monitor and
     * the same rule as Cindy's. Only the time lost is kept, for the filed session. Its advice and
     * the coach's hints are not Freestyle's (ticket #190), and no frame is judged while no
     * position is entered, because nothing says what should be legible.
     */
    private var health = TrackingHealthMonitor()

    private var lastRecognition = Recognition.NONE

    @Synchronized
    fun start(now: Long) {
        recogniser = Recogniser(profile)
        health = TrackingHealthMonitor()
        lastRecognition = Recognition.NONE
        started = true
        startedAt = now
        pausedMs = 0L
        pausedAt = null
        seen = Recognition.NO_REPS
        shown = null
        figure = 0
        banked.keys.forEach { banked[it] = 0 }
        marks.clear()
        manual = 0
    }

    @Synchronized
    fun pause(now: Long) {
        if (started && pausedAt == null) pausedAt = now
    }

    @Synchronized
    fun resume(now: Long) {
        val at = pausedAt ?: return
        pausedMs += now - at
        pausedAt = null
    }

    /**
     * The phone or the athlete has moved, or the clock was stopped long enough for either to: the
     * recogniser's bar, push-up and squat baselines are forgotten, as Cindy's are on the same
     * occasions. What is banked, the figure and the movement shown are kept.
     */
    @Synchronized
    fun recalibrate() {
        recogniser.recalibrate()
        health.reframe()
    }

    /**
     * What recognition made of the last counted frame: the verdict the engine banked from, for the
     * debug line to show instead of running a second recogniser that could disagree with it.
     */
    @Synchronized
    fun recognition(): Recognition = lastRecognition

    @Synchronized
    fun current(): FreestyleReadout = readout()

    /** Every rep banked so far, of every movement. Zero means STOP would file nothing. */
    @Synchronized
    fun totalReps(): Int = banked.values.sum()

    @Synchronized
    fun onFrame(
        k: Array<Keypoint>,
        now: Long,
        identityStable: Boolean = true,
        softGain: Float = 0f
    ): FreestyleFrame {
        if (!counting()) return FreestyleFrame(readout())
        val recognition = recogniser.onFrame(k, now, identityStable)
        lastRecognition = recognition
        recogniser.countingMovement?.let { health.update(it.exercise, recogniser.countingLegible, softGain, now) }
        val events = mutableListOf<FreestyleEvent>()
        val voice = mutableListOf<FreestyleVoice>()
        for (movement in Movement.entries) {
            val delta = recognition.tally.getValue(movement) - seen.getValue(movement)
            if (delta <= 0) continue
            val confirmed = recognition.movement != shown
            if (confirmed) {
                shown = recognition.movement
                figure = 0
            }
            bank(movement, delta, now, manual = false)
            events += FreestyleEvent.Banked(movement, delta, figure, banked.getValue(movement))
            voice += if (confirmed) FreestyleVoice.Confirmed(movement, figure) else FreestyleVoice.Count(figure)
        }
        seen = recognition.tally
        return FreestyleFrame(readout(), events, voice)
    }

    /** One rep added by hand to the recognised movement; null while − and + are dimmed. */
    @Synchronized
    fun plus(now: Long): FreestyleFrame? {
        val movement = shown?.takeIf { counting() } ?: return null
        bank(movement, 1, now, manual = true)
        manual++
        return FreestyleFrame(
            readout(),
            listOf(FreestyleEvent.Banked(movement, 1, figure, banked.getValue(movement), manual = true)),
            listOf(FreestyleVoice.Count(figure))
        )
    }

    /** The latest rep of the recognised movement taken back; null while dimmed or with none to take. */
    @Synchronized
    fun minus(now: Long): FreestyleFrame? {
        val movement = shown?.takeIf { counting() } ?: return null
        val index = marks.indexOfLast { it.movement == movement.exercise }
        if (index < 0) return null
        if (marks.removeAt(index).manual) manual--
        banked[movement] = banked.getValue(movement) - 1
        figure = (figure - 1).coerceAtLeast(0)
        return FreestyleFrame(
            readout(),
            listOf(FreestyleEvent.TakenBack(movement, figure, banked.getValue(movement))),
            listOf(FreestyleVoice.Count(figure))
        )
    }

    /** Ends the session. The filed session, or null when nothing was banked. */
    @Synchronized
    fun stop(now: Long): FiledSession? {
        if (!started) return null
        resume(now)
        started = false
        if (banked.values.sum() == 0) return null
        return FiledSession(
            durationMs = (now - startedAt - pausedMs).coerceAtLeast(0L),
            pausedMs = pausedMs,
            totals = Movement.entries.filter { banked.getValue(it) > 0 }
                .associate { it.exercise to banked.getValue(it) },
            manualReps = manual,
            marks = marks.toList(),
            untrackedMs = health.lostMs
        )
    }

    private fun counting() = started && pausedAt == null

    private fun clockAt(now: Long) = (now - startedAt - pausedMs).coerceAtLeast(0L)

    private fun bank(movement: Movement, reps: Int, now: Long, manual: Boolean) {
        banked[movement] = banked.getValue(movement) + reps
        figure += reps
        repeat(reps) { marks += RepMark(clockAt(now), movement.exercise, manual) }
    }

    private fun readout(): FreestyleReadout {
        val movement = shown
        val total = movement?.let { banked.getValue(it) } ?: 0
        return FreestyleReadout(
            figure = figure,
            movement = movement,
            movementTotal = total,
            adjustable = movement != null && counting()
        )
    }
}
