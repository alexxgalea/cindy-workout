package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Where the lock is in a session. */
enum class LockState {
    /** App open, or the workout was reset. Nothing is being counted. */
    IDLE,
    /** Looking for the athlete: the crop follows a candidate, who may still change. */
    ACQUIRING,
    /** The followed candidate has done a calibration rep, so it is no longer displaced lightly. */
    CALIBRATING,
    /** The athlete is known; every frame is judged against them. */
    LOCKED,
    /** The athlete has not been confirmed for too long; nobody counts until they are found again. */
    LOST
}

/** Whether one frame's skeleton is the athlete. */
enum class Verdict {
    /** It is the athlete: the engine counts and learns from it. */
    CONFIRMED,
    /** Too little evidence either way. Neither counts nor teaches; never a permission. */
    UNCERTAIN,
    /** It is someone else, or not the candidate being followed. */
    REFUSED
}

/** An axis-aligned box in frame pixels. */
data class PoseBox(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    fun intersects(o: PoseBox): Boolean =
        left <= o.right && o.left <= right && top <= o.bottom && o.top <= bottom

    fun contains(x: Double, y: Double): Boolean = x >= left && x <= right && y >= top && y <= bottom
}

/** What the caller knows about the session that the lock cannot see in the keypoints. */
data class LockContext(
    val movement: Exercise,
    val frameWidth: Int,
    val frameHeight: Int,
    /** The engine's learned bar, which is where a pull-up athlete comes back to. */
    val barZone: BarZone.Bounds? = null,
    /** Calibration reps the setup engine has counted; one or more makes the candidate sticky. */
    val calibrationReps: Int = 0,
    val workoutRunning: Boolean = false
)

/**
 * Decides who the athlete is, and whether each frame's skeleton is them.
 *
 * ### Why this exists
 *
 * MoveNet SinglePose picks a person afresh on every frame, by a saliency score weighted towards
 * the centre of its input, and remembers nothing. The crop tracker was meant to be the memory, but
 * in the portrait framing the app recommends it is about as wide as the frame, so it excludes
 * nobody. When someone else is more salient for a frame, the skeleton lands on them. In real use a
 * wrong pick then tends to stay there, and the athlete's reps are lost with nothing to flag it,
 * because the other person's skeleton is perfectly legible.
 *
 * The lock answers two questions. Who is the athlete: chosen deliberately at setup, by start
 * position, completeness and size, and confirmed by the calibration reps. And is this frame's
 * skeleton the athlete: judged by continuity with the athlete's last confirmed torso. The engine
 * counts and learns only from frames the lock confirms.
 *
 * ### Rules this follows
 *
 * - **Acquisition before enforcement.** A lock that enforces continuity around the wrong person
 *   refuses the athlete, so the athlete is chosen with care before anything is enforced.
 * - **LOST always has a way back** that needs no appearance model: the athlete's station, their
 *   scale and a held start position.
 * - **Too little evidence is UNCERTAIN, never CONFIRMED.** A missing keypoint is not permission.
 * - **Getting back to the right person matters as much as refusing the wrong one.** A clearly
 *   refused body is remembered for a while, so the caller can black it out, and a refused frame can
 *   be looked at again with that body hidden.
 *
 * Free of Android types, like [TrackingHealthMonitor], so the rules can be tested and replayed
 * offline. The geometry is done in `Double` with `sqrt`, never `hypot`, so the Python port can
 * reproduce it bit for bit.
 *
 * Every constant below is an initial value, set by judgement or from one measurement on clean 15
 * fps footage; each says which.
 */
class AthleteLock(
    /**
     * Predict the torso centre with a constant-velocity filter, rather than holding it still.
     *
     * Off by default, because it did not pay. Replayed over a full Cindy round and seven
     * two-person composites, the constant-position gate refused no more of the athlete's frames
     * anywhere, and never confirmed a theft the filter caught. With two people doing pull-ups side
     * by side, the filter's velocity was thrown by the neighbour's frames and the athlete was
     * refused for 61% of the clip, against 2.4% without it.
     */
    private val predict: Boolean = false
) {

    companion object {
        /** MoveNet confidence below which a keypoint is treated as unseen, as in the engine. */
        const val MIN_SCORE = PoseGeometry.MIN_SCORE

        /**
         * Continuity gate, in torso lengths, between consecutive frames.
         *
         * Measured: with both shoulders and both hips required, an athlete's torso centre never
         * moved more than 0.75 torso lengths between analysed frames at 15 fps (p99 0.30), across a
         * full Cindy round. A one-sided torso is far noisier, which is why the gate is two-sided.
         */
        const val GATE_TORSOS = 0.75
        /** The frame interval the gate was measured at, so a longer gap widens it in proportion. */
        const val GATE_FRAME_MS = 70.0
        /** However long the gap, the gate never opens wider than this. Judgement. */
        const val GATE_MAX_TORSOS = 2.0
        /** The prediction stops extrapolating after this long. Judgement. */
        const val PREDICT_CAP_MS = 250.0
        /** A torso length change beyond this factor is a different body, or a different distance. */
        const val SCALE_RATIO = 1.5
        /** Alpha-beta filter gains. Judgement; alpha close to 1 keeps the gate on the measurement. */
        const val FILTER_ALPHA = 0.85
        const val FILTER_BETA = 0.3
        /**
         * The shortest interval a velocity is estimated over: one camera frame at 30 fps. Two
         * frames stamped closer than this (a confirm and the frame after it, say) would otherwise
         * divide a whole residual by a millisecond and fling the prediction across the frame.
         */
        const val MIN_VELOCITY_MS = 33.0

        /** Time without a confirmed frame before LOCKED becomes LOST. Judgement. */
        const val LOST_AFTER_MS = 1_500L
        /** How often a probe inference is wanted while acquiring or lost. Costs ~9% of frames. */
        const val PROBE_INTERVAL_MS = 500L
        /** A candidate unseen for this long is forgotten. Judgement. */
        const val CANDIDATE_EXPIRY_MS = 2_000L
        /** The start position must hold this long to count as taken up, as in the engine. */
        const val START_HOLD_MS = 500L
        /** How long a challenger must out-rank the followed candidate before it replaces them. */
        const val SWITCH_AFTER_MS = 1_000L
        /** A size-only advantage must be at least this large to count as out-ranking. */
        const val SIZE_ADVANTAGE = 1.25
        /** While calibrating, the candidate is replaced only after being unseen this long. */
        const val CALIBRATING_UNSEEN_MS = 1_500L
        /** Matching a pose to a known candidate: centre within this many of its torso lengths. */
        const val MATCH_TORSOS = 1.5

        /** Re-acquisition scale window against the remembered scale. Judgement. */
        const val REACQUIRE_SCALE_MIN = 0.67
        const val REACQUIRE_SCALE_MAX = 1.5
        /** A push-up or squat station box is grown by this many torso lengths. */
        const val STATION_GROW_TORSOS = 1.0
        /** With no station yet, the athlete must come back within this of where they were. */
        const val NO_STATION_TORSOS = 3.0
        /** Without a visible nose, the wrists must be this far above the shoulders to be overhead. */
        const val OVERHEAD_NO_NOSE_TORSOS = 0.5

        /** A refused body is remembered, for blacking out, for this long after it was last seen. */
        const val KNOWN_OTHER_MS = 2_000L
        /** A known other's box is its confident joints grown by this share of its own torso. */
        const val KNOWN_OTHER_PAD = 0.3
        /** The athlete's predicted torso box is grown by this before protecting it from blackout. */
        const val PROTECT_PAD = 0.5
        /** Second looks, at most one frame in this many over any second. Keeps ~13 fps. */
        const val SECOND_LOOK_ONE_IN = 3
        const val RATE_WINDOW_MS = 1_000L

        private val TORSO = intArrayOf(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, KP.LEFT_HIP, KP.RIGHT_HIP)
    }

    // ── public read-outs, valid after each call ──────────────────────────────

    var state = LockState.IDLE
        private set
    /** Verdict for the last primary pose (or its second look). */
    var verdict = Verdict.UNCERTAIN
        private set
    /** Short machine-readable reason for [verdict], for diagnostics and the parity trace. */
    var reason = "idle"
        private set
    /** True on the frame the followed candidate changed; the caller restarts calibration. */
    var candidateChanged = false
        private set
    /** True when two candidates were in the start position at once. */
    var ambiguous = false
        private set
    /** A pose the crop should move to, when it is not the primary. */
    var steer: Array<Keypoint>? = null
        private set
    /** Run a probe on the next frame. */
    var probeWanted = false
        private set
    /** The last primary was refused while locked, and the rate cap allows a second look. */
    var secondLookWanted = false
        private set
    /** The box of the last refused primary, which a second look must black out. */
    var refusedBox: PoseBox? = null
        private set

    // ── the athlete's track ──────────────────────────────────────────────────

    private var cx = 0.0
    private var cy = 0.0
    private var vx = 0.0
    private var vy = 0.0
    private var scale = 0.0
    private var lastConfirmedAt = 0L
    private val jointX = DoubleArray(KP.COUNT)
    private val jointY = DoubleArray(KP.COUNT)
    private val jointSeen = BooleanArray(KP.COUNT)
    private var tracking = false

    // ── acquisition ──────────────────────────────────────────────────────────

    private class Candidate(val id: Int) {
        var pose: Array<Keypoint> = emptyArray()
        var cx = 0.0
        var cy = 0.0
        var length = 0.0
        var full = false
        var complete = false
        var inStart = false
        var inStartSince = -1L
        var lastSeen = 0L
        var seenThisFrame = false
        var fromPrimary = false
    }

    private val candidates = mutableListOf<Candidate>()
    private var nextCandidateId = 1
    private var followed: Candidate? = null
    private var challenger: Candidate? = null
    private var challengeSince = 0L

    private var lastProbeAt = 0L
    private var excludeOthersNext = false
    private var movement = Exercise.PULLUP

    // ── memory for getting back ──────────────────────────────────────────────

    private class KnownOther(var box: PoseBox, var lastSeen: Long)

    private val knownOthers = mutableListOf<KnownOther>()
    private val scaleMemory = HashMap<Exercise, Double>()
    private val stations = HashMap<Exercise, DoubleArray>() // minX, minY, maxX, maxY of centres
    private val lockedFrames = ArrayDeque<Long>()
    /** The phone moved since the last lock, so neither scale nor position is evidence. */
    private var viewMoved = false
    private val secondLooks = ArrayDeque<Long>()

    // ── control ──────────────────────────────────────────────────────────────

    /** SET UP: start looking for the athlete. */
    fun beginAcquiring(now: Long) {
        clearAcquisition()
        tracking = false
        knownOthers.clear()
        state = LockState.ACQUIRING
        lastProbeAt = now
        verdict = Verdict.UNCERTAIN
        reason = "acquiring"
    }

    /** READY: the followed candidate is the athlete. */
    fun confirm(now: Long) {
        val c = followed ?: return
        lockOnto(c, now)
    }

    /**
     * The athlete may have gone, or the view changed: pause and resume ([clearStations] false), or
     * the phone was moved ([clearStations] true).
     *
     * A moved phone invalidates the athlete's scale as surely as their stations: both were
     * measured in frame pixels from where the phone used to stand. Keeping the old scale would
     * leave an athlete who is now nearer or further away unable ever to be found again, so after a
     * move they are re-acquired by a held start position with nobody else qualifying.
     */
    fun lose(now: Long, clearStations: Boolean) {
        if (state == LockState.IDLE) return
        if (clearStations) {
            stations.clear()
            scaleMemory.clear()
            viewMoved = true
        }
        goLost(now)
        lastProbeAt = now - PROBE_INTERVAL_MS
    }

    /** Back to IDLE, forgetting everything. */
    fun reset() {
        clearAcquisition()
        knownOthers.clear()
        scaleMemory.clear()
        stations.clear()
        lockedFrames.clear()
        secondLooks.clear()
        tracking = false
        viewMoved = false
        state = LockState.IDLE
        verdict = Verdict.UNCERTAIN
        reason = "idle"
        candidateChanged = false
        ambiguous = false
        steer = null
        probeWanted = false
        secondLookWanted = false
        refusedBox = null
    }

    // ── per frame ────────────────────────────────────────────────────────────

    /**
     * Judges this frame's [primary] pose. [probes] are any whole-frame probe poses the caller ran
     * this frame because [probeWanted] was set. Returns the verdict, also left in [verdict].
     */
    fun onFrame(
        primary: Array<Keypoint>,
        probes: List<Array<Keypoint>>,
        now: Long,
        ctx: LockContext
    ): Verdict {
        movement = ctx.movement
        candidateChanged = false
        ambiguous = false
        steer = null
        secondLookWanted = false
        refusedBox = null
        expireKnownOthers(now)

        when (state) {
            LockState.IDLE -> set(Verdict.UNCERTAIN, "idle")
            LockState.ACQUIRING, LockState.CALIBRATING -> acquire(primary, probes, now, ctx)
            LockState.LOCKED -> judgeLocked(primary, now, ctx)
            LockState.LOST -> reacquire(primary, probes, now, ctx)
        }

        probeWanted = false
        if (state == LockState.ACQUIRING || state == LockState.CALIBRATING || state == LockState.LOST) {
            if (now - lastProbeAt >= PROBE_INTERVAL_MS) {
                probeWanted = true
                lastProbeAt = now
            }
        }
        return verdict
    }

    /** What the next probe must black out: alternately the followed candidate, then them plus every known other. */
    fun probeExclusions(): List<PoseBox> {
        val out = mutableListOf<PoseBox>()
        followed?.let { out += boxOf(it.pose, KNOWN_OTHER_PAD, it.length) }
        if (excludeOthersNext || state == LockState.LOST) out += knownOthers()
        excludeOthersNext = !excludeOthersNext
        return out
    }

    /**
     * People recently refused by a clear margin, to black out of the next inference. Never any box
     * that touches the athlete's predicted torso: a false refusal must not hide the athlete.
     */
    fun knownOthers(): List<PoseBox> {
        if (knownOthers.isEmpty()) return emptyList()
        val protect = protectedBox() ?: return knownOthers.map { it.box }
        return knownOthers.filter { !it.box.intersects(protect) }.map { it.box }
    }

    /**
     * Judges a second look at the same frame, run with the refused body blacked out. If it passes
     * continuity it becomes this frame's CONFIRMED pose; otherwise nothing about it is learned.
     */
    fun reconsider(second: Array<Keypoint>, now: Long): Verdict {
        secondLookWanted = false
        if (state != LockState.LOCKED || verdict != Verdict.REFUSED) return verdict
        val j = judge(second, now)
        if (j.verdict == Verdict.CONFIRMED) {
            confirmFrame(second, now, j.full)
            set(Verdict.CONFIRMED, "second-look")
        }
        return verdict
    }

    // ── LOCKED ───────────────────────────────────────────────────────────────

    private fun judgeLocked(primary: Array<Keypoint>, now: Long, ctx: LockContext) {
        lockedFrames.addLast(now)
        trim(lockedFrames, now)
        trim(secondLooks, now)
        val j = judge(primary, now)
        set(j.verdict, j.reason)
        when (j.verdict) {
            Verdict.CONFIRMED -> confirmFrame(primary, now, j.full)
            Verdict.REFUSED -> {
                val t = torsoOf(primary)
                refusedBox = boxOf(primary, KNOWN_OTHER_PAD, t?.length ?: scale)
                if (j.clear) rememberOther(refusedBox!!, now)
                if ((secondLooks.size + 1) * SECOND_LOOK_ONE_IN <= lockedFrames.size) {
                    secondLookWanted = true
                    secondLooks.addLast(now)
                }
            }
            Verdict.UNCERTAIN -> Unit
        }
        if (verdict != Verdict.CONFIRMED && now - lastConfirmedAt > LOST_AFTER_MS) {
            goLost(now)
            secondLookWanted = false
        }
    }

    private class Judgement(val verdict: Verdict, val reason: String, val clear: Boolean, val full: Boolean)

    /** Continuity with the athlete's track: the rules the whole lock rests on. */
    private fun judge(k: Array<Keypoint>, now: Long): Judgement {
        val t = torsoOf(k) ?: return Judgement(Verdict.UNCERTAIN, "no-torso", false, false)
        val dt = (now - lastConfirmedAt).toDouble()
        val h = min(max(dt, 0.0), PREDICT_CAP_MS)
        val gate = min(GATE_MAX_TORSOS, GATE_TORSOS * max(1.0, dt / GATE_FRAME_MS))
        if (t.full) {
            val px = cx + vx * h
            val py = cy + vy * h
            val d = dist(t.cx, t.cy, px, py) / scale
            val ratio = t.length / scale
            val scaleOk = ratio >= 1.0 / SCALE_RATIO && ratio <= SCALE_RATIO
            if (d <= gate && scaleOk) return Judgement(Verdict.CONFIRMED, "ok", false, true)
            val clear = d > 2.0 * gate || !scaleOk
            return Judgement(Verdict.REFUSED, if (scaleOk) "jump" else "scale", clear, true)
        }
        // Part of the torso: compare each seen torso joint with the same joint in the last
        // confirmed pose, shifted by the predicted motion.
        var within = 0
        var far = false
        var over = false
        for (j in TORSO) {
            val p = k[j]
            if (p.score < MIN_SCORE || !jointSeen[j]) continue
            val d = dist(p.x.toDouble(), p.y.toDouble(), jointX[j] + vx * h, jointY[j] + vy * h) / scale
            if (d > 2.0 * gate) far = true
            if (d <= gate) within++ else over = true
        }
        if (far) return Judgement(Verdict.REFUSED, "partial-far", false, false)
        if (!over && within >= 2) return Judgement(Verdict.CONFIRMED, "partial-ok", false, false)
        return Judgement(Verdict.UNCERTAIN, "partial", false, false)
    }

    private fun confirmFrame(k: Array<Keypoint>, now: Long, full: Boolean) {
        val dt = max((now - lastConfirmedAt).toDouble(), 1.0)
        val h = min(dt, PREDICT_CAP_MS)
        if (full) {
            val t = torsoOf(k)!!
            val px = cx + vx * h
            val py = cy + vy * h
            val rx = t.cx - px
            val ry = t.cy - py
            if (predict) {
                cx = px + FILTER_ALPHA * rx
                cy = py + FILTER_ALPHA * ry
                val dv = max(dt, MIN_VELOCITY_MS)
                vx += FILTER_BETA * rx / dv
                vy += FILTER_BETA * ry / dv
            } else {
                // Constant position: the gate is centred on the last confirmed torso itself.
                cx = t.cx
                cy = t.cy
            }
            scale = t.length
        } else {
            // A partial torso refreshes the joints it saw, and moves the centre by the prediction,
            // but is not trusted for the scale.
            cx += vx * h
            cy += vy * h
        }
        storeJoints(k)
        lastConfirmedAt = now
        rememberStation()
        val mine = boxOf(k, 0.0, scale)
        knownOthers.removeAll { it.box.intersects(mine) }
    }

    // ── ACQUIRING / CALIBRATING ──────────────────────────────────────────────

    private fun acquire(primary: Array<Keypoint>, probes: List<Array<Keypoint>>, now: Long, ctx: LockContext) {
        val before = followed
        val fromPrimary = observe(primary, probes, now, ctx)
        if (state == LockState.ACQUIRING && ctx.calibrationReps >= 1 && !ctx.workoutRunning && followed != null) {
            state = LockState.CALIBRATING
        }
        val f0 = followed
        if (f0 == null) {
            // Nobody followed yet, or the followed candidate expired. Adopting someone after an
            // expiry is a switch: calibration reps from two people must never be mixed.
            val first = fromPrimary ?: candidates.firstOrNull()
            if (before != null && first != null) {
                candidateChanged = true
                state = LockState.ACQUIRING
            }
            followed = first
            challenger = null
        } else if (state == LockState.ACQUIRING) {
            considerSwitch(now, ctx)
        } else if (now - f0.lastSeen > CALIBRATING_UNSEEN_MS) {
            // Calibrating is sticky: only a candidate gone for a while is replaced.
            val next = best(candidates.filter { it !== f0 }, ctx)
            if (next != null) {
                followed = next
                candidateChanged = true
                state = LockState.ACQUIRING
            }
        }
        ambiguous = candidates.count { it.seenThisFrame && it.inStart } >= 2

        if (ctx.workoutRunning) {
            // SKIP: nothing counts until someone holds the start position.
            val held = candidates.filter { it.seenThisFrame && held(it, now) }
            val top = held.maxWithOrNull(compareBy<Candidate>({ centrality(it, ctx) }, { it.length }))
            if (top != null && top.full) {
                lockOnto(top, now)
                if (top === fromPrimary) set(Verdict.CONFIRMED, "skip-lock")
                else {
                    set(Verdict.REFUSED, "skip-lock-elsewhere")
                    steer = top.pose
                }
                return
            }
            set(if (torsoOf(primary) == null) Verdict.UNCERTAIN else Verdict.REFUSED, "skip-waiting")
            return
        }
        val f = followed
        when {
            torsoOf(primary) == null -> set(Verdict.UNCERTAIN, "no-torso")
            f != null && f === fromPrimary -> set(Verdict.CONFIRMED, "followed")
            else -> {
                set(Verdict.REFUSED, "not-followed")
                if (f != null) steer = f.pose
            }
        }
    }

    private fun considerSwitch(now: Long, ctx: LockContext) {
        val f = followed ?: return
        val rival = best(candidates.filter { it !== f && it.seenThisFrame }, ctx)
        if (rival == null || !beats(rival, f, now, ctx)) {
            challenger = null
            return
        }
        if (challenger !== rival) {
            challenger = rival
            challengeSince = now
            return
        }
        if (now - challengeSince >= SWITCH_AFTER_MS) {
            followed = rival
            challenger = null
            candidateChanged = true
        }
    }

    /** The rank key: start position held, then complete, then size weighted by centrality. */
    private fun beats(a: Candidate, b: Candidate, now: Long, ctx: LockContext): Boolean {
        val ha = held(a, now)
        val hb = held(b, now)
        if (ha != hb) return ha
        if (a.complete != b.complete) return a.complete
        return size(a, ctx) >= SIZE_ADVANTAGE * size(b, ctx)
    }

    private fun best(pool: List<Candidate>, ctx: LockContext): Candidate? {
        var top: Candidate? = null
        for (c in pool) {
            val t = top
            if (t == null) { top = c; continue }
            val hc = c.inStartSince >= 0
            val ht = t.inStartSince >= 0
            val better = when {
                hc != ht -> hc
                c.complete != t.complete -> c.complete
                else -> size(c, ctx) > size(t, ctx)
            }
            if (better) top = c
        }
        return top
    }

    private fun held(c: Candidate, now: Long) = c.inStartSince >= 0 && now - c.inStartSince >= START_HOLD_MS

    private fun centrality(c: Candidate, ctx: LockContext): Double {
        val half = ctx.frameWidth / 2.0
        return (1.0 - abs(c.cx - half) / half).coerceIn(0.0, 1.0)
    }

    private fun size(c: Candidate, ctx: LockContext) = c.length * (0.5 + 0.5 * centrality(c, ctx))

    private fun lockOnto(c: Candidate, now: Long) {
        val t = torsoOf(c.pose) ?: return
        cx = t.cx
        cy = t.cy
        vx = 0.0
        vy = 0.0
        scale = t.length
        jointSeen.fill(false)
        storeJoints(c.pose)
        lastConfirmedAt = now
        tracking = true
        viewMoved = false
        scaleMemory[movement] = scale
        state = LockState.LOCKED
        clearAcquisition()
        lockedFrames.clear()
        secondLooks.clear()
    }

    // ── LOST ─────────────────────────────────────────────────────────────────

    private fun reacquire(primary: Array<Keypoint>, probes: List<Array<Keypoint>>, now: Long, ctx: LockContext) {
        val fromPrimary = observe(primary, probes, now, ctx)
        val qualifying = candidates.filter { it.seenThisFrame && qualifies(it, now, ctx) }
        ambiguous = qualifying.size >= 2
        if (qualifying.size == 1) {
            val c = qualifying[0]
            lockOnto(c, now)
            if (c === fromPrimary) {
                set(Verdict.CONFIRMED, "reacquired")
            } else {
                set(Verdict.REFUSED, "reacquired-elsewhere")
                steer = c.pose
            }
            return
        }
        set(if (torsoOf(primary) == null) Verdict.UNCERTAIN else Verdict.REFUSED, if (ambiguous) "lost-ambiguous" else "lost")
    }

    /** Station, scale and a held start position, with no appearance model at all. */
    private fun qualifies(c: Candidate, now: Long, ctx: LockContext): Boolean {
        if (!c.full || !c.complete || !held(c, now)) return false
        if (viewMoved) return true
        val remembered = scaleMemory[ctx.movement] ?: scale
        if (remembered <= 0.0) return false
        val ratio = c.length / remembered
        if (ratio < REACQUIRE_SCALE_MIN || ratio > REACQUIRE_SCALE_MAX) return false
        val bar = ctx.barZone
        if (ctx.movement == Exercise.PULLUP && bar != null) {
            val l = c.pose[KP.LEFT_WRIST]
            val r = c.pose[KP.RIGHT_WRIST]
            return l.score >= MIN_SCORE && r.score >= MIN_SCORE &&
                l.x >= bar.left && l.x <= bar.right && r.x >= bar.left && r.x <= bar.right &&
                l.y >= bar.top && l.y <= bar.bottom && r.y >= bar.top && r.y <= bar.bottom
        }
        val st = stations[ctx.movement]
        if (st != null && ctx.movement != Exercise.PULLUP) {
            val grow = STATION_GROW_TORSOS * remembered
            return c.cx >= st[0] - grow && c.cx <= st[2] + grow && c.cy >= st[1] - grow && c.cy <= st[3] + grow
        }
        if (!tracking) return false
        return dist(c.cx, c.cy, cx, cy) <= NO_STATION_TORSOS * remembered
    }

    private fun goLost(now: Long) {
        state = LockState.LOST
        clearAcquisition()
        knownOthers.clear()
        lockedFrames.clear()
        secondLooks.clear()
        if (verdict == Verdict.CONFIRMED) set(Verdict.REFUSED, "lost")
    }

    // ── candidates ───────────────────────────────────────────────────────────

    /** Matches this frame's poses to candidates; returns the primary's candidate, if it has a torso. */
    private fun observe(primary: Array<Keypoint>, probes: List<Array<Keypoint>>, now: Long, ctx: LockContext): Candidate? {
        for (c in candidates) {
            c.seenThisFrame = false
            c.fromPrimary = false
        }
        val fromPrimary = match(primary, now, ctx, true)
        for (p in probes) match(p, now, ctx, false)
        candidates.removeAll { now - it.lastSeen > CANDIDATE_EXPIRY_MS }
        if (followed != null && followed !in candidates) followed = null
        if (challenger != null && challenger !in candidates) challenger = null
        return fromPrimary
    }

    private fun match(k: Array<Keypoint>, now: Long, ctx: LockContext, isPrimary: Boolean): Candidate? {
        val t = torsoOf(k) ?: return null
        var bestC: Candidate? = null
        var bestD = Double.MAX_VALUE
        for (c in candidates) {
            if (c.seenThisFrame) continue
            val ratio = t.length / c.length
            if (ratio < 1.0 / SCALE_RATIO || ratio > SCALE_RATIO) continue
            val d = dist(t.cx, t.cy, c.cx, c.cy) / c.length
            if (d <= MATCH_TORSOS && d < bestD) {
                bestD = d
                bestC = c
            }
        }
        val c = bestC ?: Candidate(nextCandidateId++).also { candidates += it }
        c.pose = k
        c.cx = t.cx
        c.cy = t.cy
        c.length = t.length
        c.full = t.full
        c.complete = PoseGeometry.missingJoints(k, ctx.movement).isEmpty()
        c.inStart = inStart(k, ctx.movement)
        if (!c.inStart) c.inStartSince = -1L else if (c.inStartSince < 0) c.inStartSince = now
        c.lastSeen = now
        c.seenThisFrame = true
        c.fromPrimary = isPrimary
        return c
    }

    /**
     * The movement's start position, on positive evidence only. A pull-up needs both wrists seen
     * above the head; a nose that cannot be seen is not taken as permission, so the wrists must
     * then sit well above the shoulders instead.
     */
    private fun inStart(k: Array<Keypoint>, movement: Exercise): Boolean = when (movement) {
        Exercise.PULLUP -> {
            val l = k[KP.LEFT_WRIST]
            val r = k[KP.RIGHT_WRIST]
            val t = torsoOf(k)
            if (l.score < MIN_SCORE || r.score < MIN_SCORE || t == null || !PoseGeometry.upright(k)) false
            else {
                val nose = k[KP.NOSE]
                if (nose.score >= MIN_SCORE) l.y < nose.y && r.y < nose.y
                else {
                    val sh = shoulderY(k)
                    sh != null && sh - l.y >= OVERHEAD_NO_NOSE_TORSOS * t.length &&
                        sh - r.y >= OVERHEAD_NO_NOSE_TORSOS * t.length
                }
            }
        }
        Exercise.PUSHUP -> torsoOf(k) != null && !PoseGeometry.upright(k)
        Exercise.SQUAT -> PoseGeometry.standing(k)
    }

    private fun clearAcquisition() {
        candidates.clear()
        followed = null
        challenger = null
    }

    // ── memory ───────────────────────────────────────────────────────────────

    private fun rememberOther(box: PoseBox, now: Long) {
        val existing = knownOthers.firstOrNull { it.box.intersects(box) }
        if (existing != null) {
            existing.box = box
            existing.lastSeen = now
        } else {
            knownOthers += KnownOther(box, now)
        }
    }

    private fun expireKnownOthers(now: Long) {
        knownOthers.removeAll { now - it.lastSeen > KNOWN_OTHER_MS }
    }

    private fun rememberStation() {
        if (movement == Exercise.PULLUP) return
        val s = stations[movement]
        if (s == null) stations[movement] = doubleArrayOf(cx, cy, cx, cy)
        else {
            s[0] = min(s[0], cx); s[1] = min(s[1], cy)
            s[2] = max(s[2], cx); s[3] = max(s[3], cy)
        }
        scaleMemory[movement] = scale
    }

    /** The athlete's torso box where it is predicted to be now, grown by [PROTECT_PAD] torso. */
    private fun protectedBox(): PoseBox? {
        if (!tracking) return null
        var l = Double.MAX_VALUE; var t = Double.MAX_VALUE; var r = -Double.MAX_VALUE; var b = -Double.MAX_VALUE
        var any = false
        for (j in TORSO) {
            if (!jointSeen[j]) continue
            any = true
            l = min(l, jointX[j]); r = max(r, jointX[j]); t = min(t, jointY[j]); b = max(b, jointY[j])
        }
        if (!any) return null
        val pad = PROTECT_PAD * scale
        return PoseBox((l - pad).toFloat(), (t - pad).toFloat(), (r + pad).toFloat(), (b + pad).toFloat())
    }

    private fun storeJoints(k: Array<Keypoint>) {
        for (j in 0 until KP.COUNT) {
            val p = k[j]
            if (p.score >= MIN_SCORE) {
                jointX[j] = p.x.toDouble()
                jointY[j] = p.y.toDouble()
                jointSeen[j] = true
            }
        }
    }

    private fun trim(q: ArrayDeque<Long>, now: Long) {
        while (q.isNotEmpty() && now - q.first() >= RATE_WINDOW_MS) q.removeFirst()
    }

    private fun set(v: Verdict, why: String) {
        verdict = v
        reason = why
    }

    // ── geometry ─────────────────────────────────────────────────────────────

    private class Torso(val cx: Double, val cy: Double, val length: Double, val full: Boolean)

    /** The torso from whichever shoulders and hips are seen; null without at least one of each. */
    private fun torsoOf(k: Array<Keypoint>): Torso? {
        val ls = k[KP.LEFT_SHOULDER]; val rs = k[KP.RIGHT_SHOULDER]
        val lh = k[KP.LEFT_HIP]; val rh = k[KP.RIGHT_HIP]
        val sx: Double; val sy: Double; val hx: Double; val hy: Double
        val lsOk = ls.score >= MIN_SCORE; val rsOk = rs.score >= MIN_SCORE
        val lhOk = lh.score >= MIN_SCORE; val rhOk = rh.score >= MIN_SCORE
        when {
            lsOk && rsOk -> { sx = (ls.x.toDouble() + rs.x.toDouble()) / 2.0; sy = (ls.y.toDouble() + rs.y.toDouble()) / 2.0 }
            lsOk -> { sx = ls.x.toDouble(); sy = ls.y.toDouble() }
            rsOk -> { sx = rs.x.toDouble(); sy = rs.y.toDouble() }
            else -> return null
        }
        when {
            lhOk && rhOk -> { hx = (lh.x.toDouble() + rh.x.toDouble()) / 2.0; hy = (lh.y.toDouble() + rh.y.toDouble()) / 2.0 }
            lhOk -> { hx = lh.x.toDouble(); hy = lh.y.toDouble() }
            rhOk -> { hx = rh.x.toDouble(); hy = rh.y.toDouble() }
            else -> return null
        }
        return Torso((sx + hx) / 2.0, (sy + hy) / 2.0, max(dist(sx, sy, hx, hy), 1.0), lsOk && rsOk && lhOk && rhOk)
    }

    private fun shoulderY(k: Array<Keypoint>): Double? {
        val l = k[KP.LEFT_SHOULDER]; val r = k[KP.RIGHT_SHOULDER]
        return when {
            l.score >= MIN_SCORE && r.score >= MIN_SCORE -> (l.y.toDouble() + r.y.toDouble()) / 2.0
            l.score >= MIN_SCORE -> l.y.toDouble()
            r.score >= MIN_SCORE -> r.y.toDouble()
            else -> null
        }
    }

    /** Confident joints' bounding box, grown by [pad] of [torso]. */
    private fun boxOf(k: Array<Keypoint>, pad: Double, torso: Double): PoseBox {
        var l = Double.MAX_VALUE; var t = Double.MAX_VALUE; var r = -Double.MAX_VALUE; var b = -Double.MAX_VALUE
        for (p in k) {
            if (p.score < MIN_SCORE) continue
            l = min(l, p.x.toDouble()); r = max(r, p.x.toDouble())
            t = min(t, p.y.toDouble()); b = max(b, p.y.toDouble())
        }
        if (l > r) return PoseBox(0f, 0f, 0f, 0f)
        val g = pad * torso
        return PoseBox((l - g).toFloat(), (t - g).toFloat(), (r + g).toFloat(), (b + g).toFloat())
    }

    private fun dist(ax: Double, ay: Double, bx: Double, by: Double): Double {
        val dx = ax - bx
        val dy = ay - by
        return sqrt(dx * dx + dy * dy)
    }
}
