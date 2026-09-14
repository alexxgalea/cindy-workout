package com.cindy.tracker

import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.os.SystemClock
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.CameraInfo

/**
 * How old a frame is by the time it reaches the screen, and the clock arithmetic that makes the
 * answer trustworthy.
 *
 * ### Why this is not a subtraction
 *
 * The obvious way to measure glass-to-overlay latency is to subtract `ImageProxy.imageInfo
 * .timestamp` from the current time. That is wrong on roughly half the Android fleet, silently.
 *
 * A camera's frame timestamps come from one of two clocks, and the device says which through
 * [CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE]:
 *
 *  - `UNKNOWN` — `CLOCK_MONOTONIC`, which stops while the device is suspended. Its Java twin is
 *    [System.nanoTime].
 *  - `REALTIME` — `CLOCK_BOOTTIME`, which keeps counting through suspend. Its Java twin is
 *    [SystemClock.elapsedRealtimeNanos].
 *
 * The two run apart by however long the phone has spent asleep since boot — on a handset that has
 * been off the charger overnight that is hours. Subtracting across the pair does not produce a
 * slightly wrong latency, it produces a wildly wrong one, and a plausible-looking number in a
 * debug readout is worse than no number because it will be believed.
 *
 * So the source is read once when the camera binds, and a reading whose domain was never resolved
 * is reported as unavailable rather than guessed at.
 */
class FrameLatency {

    /** Which clock the camera stamps its frames with, once the device has told us. */
    private enum class Domain { MONOTONIC, REALTIME, UNRESOLVED }

    @Volatile
    private var domain = Domain.UNRESOLVED

    /** True once the camera has told us which clock its timestamps are on. */
    val resolved: Boolean get() = domain != Domain.UNRESOLVED

    /**
     * Asks the bound camera which clock it stamps frames with. Safe to call on every bind; a
     * device that refuses the query simply leaves capture age unavailable, which is the honest
     * outcome and costs nothing else.
     */
    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    fun resolve(info: CameraInfo) {
        domain = try {
            val source = Camera2CameraInfo.from(info)
                .getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE)
            when (source) {
                CameraMetadata.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME -> Domain.REALTIME
                CameraMetadata.SENSOR_INFO_TIMESTAMP_SOURCE_UNKNOWN -> Domain.MONOTONIC
                else -> Domain.UNRESOLVED
            }
        } catch (t: Throwable) {
            Domain.UNRESOLVED
        }
    }

    /**
     * Milliseconds since [captureNanos] was stamped by the sensor, or null when that cannot be
     * stated honestly — either the clock domain is unknown, or the arithmetic produced something
     * impossible, which is the signature of having guessed the domain wrong.
     */
    fun sinceCapture(captureNanos: Long): Long? {
        val now = when (domain) {
            Domain.MONOTONIC -> System.nanoTime()
            Domain.REALTIME -> SystemClock.elapsedRealtimeNanos()
            Domain.UNRESOLVED -> return null
        }
        val ms = (now - captureNanos) / 1_000_000L
        // A frame cannot have been captured in the future, and one older than this arrived from a
        // clock we are not actually on. Either way the number would be a fiction.
        return if (ms < 0L || ms > IMPLAUSIBLE_MS) null else ms
    }

    private companion object {
        const val IMPLAUSIBLE_MS = 5_000L
    }
}

/**
 * A short window of recent samples, summarised by its median.
 *
 * The median rather than the mean because the thing being measured is a phone doing several jobs
 * at once: a single GC pause or a bound scheduler decision drags a mean somewhere no frame
 * actually was, and a debug readout that swings on one bad frame cannot be read off a screen from
 * across the room — which is the only way anyone will read this one.
 */
class Rolling(private val size: Int = 30) {

    private val samples = LongArray(size)
    private var count = 0
    private var next = 0

    fun add(sample: Long) {
        samples[next] = sample
        next = (next + 1) % size
        if (count < size) count++
    }

    fun reset() {
        count = 0
        next = 0
    }

    /** Median of the window, or null until anything has been recorded. */
    fun median(): Long? {
        if (count == 0) return null
        val window = samples.copyOf(count)
        window.sort()
        return window[count / 2]
    }
}

/**
 * Frames per second, counted over a rolling wall-clock window rather than derived from an
 * interval, so a stall shows up as the rate falling instead of one long gap being averaged away.
 */
class RateMeter(private val windowMs: Long = 2_000L) {

    private val stamps = ArrayDeque<Long>()

    /**
     * nanoTime rather than a wall clock: this measures durations, and it keeps the meter free of
     * Android so the readout can be tested on the JVM like everything else that decides anything.
     */
    private fun now() = System.nanoTime() / 1_000_000L

    @Synchronized
    fun mark(nowMs: Long = now()) {
        stamps.addLast(nowMs)
        while (stamps.isNotEmpty() && nowMs - stamps.first() > windowMs) stamps.removeFirst()
    }

    @Synchronized
    fun reset() = stamps.clear()

    /** Rate over the window, or null before there is enough to divide by. */
    @Synchronized
    fun perSecond(nowMs: Long = now()): Float? {
        while (stamps.isNotEmpty() && nowMs - stamps.first() > windowMs) stamps.removeFirst()
        if (stamps.size < 2) return null
        val span = stamps.last() - stamps.first()
        if (span <= 0L) return null
        return (stamps.size - 1) * 1000f / span
    }
}

/**
 * Every number needed to say where the skeleton's lag comes from, and the one line that reports
 * them.
 *
 * ### Why this is a screen readout and not a log
 *
 * There is no `adb` on the machine this was written on. The app reaches the phone as an APK over
 * HTTP and the only channel back is what the athlete can see and photograph. So the measurement
 * has to survive being read off a band at 14sp, which is why it is medians of a short window
 * rather than a stream, and why it is worded rather than packed.
 */
class LatencyProbe {

    val clock = FrameLatency()
    val analysisRate = RateMeter()

    private val age = Rolling()
    private val convert = Rolling()
    private val prep = Rolling()
    private val infer = Rolling()
    private val uiDelay = Rolling()

    private var posted = 0
    private var coalesced = 0

    fun reset() {
        age.reset(); convert.reset(); prep.reset(); infer.reset(); uiDelay.reset()
        analysisRate.reset()
        posted = 0
        coalesced = 0
    }

    /** One completed analysis pass. [captureAgeMs] is null when the clock domain is unresolved. */
    fun analysed(captureAgeMs: Long?, convertMs: Long, prepMs: Long, inferMs: Long) {
        captureAgeMs?.let(age::add)
        convert.add(convertMs)
        prep.add(prepMs)
        infer.add(inferMs)
        analysisRate.mark()
    }

    /** A snapshot handed to the main thread, and whether it replaced one not yet rendered. */
    fun posted(replacedUnrendered: Boolean) {
        posted++
        if (replacedUnrendered) coalesced++
    }

    fun uiRan(delayMs: Long) = uiDelay.add(delayMs)

    /**
     * Share of snapshots that were superseded before the main thread rendered them.
     *
     * This is the retroactive evidence for whether the old post-per-frame arrangement was
     * queueing: a high number here means the main thread could not keep up with the analysis
     * thread, which in the previous design would not have dropped anything — it would have drawn
     * every one of them, late and getting later.
     */
    private fun coalescedShare(): Int? =
        if (posted == 0) null else coalesced * 100 / posted

    /** Two lines, because one 14sp row will not hold this and still be readable. */
    fun line(model: String, drawnPerSecond: Float?): String {
        val ageText = age.median()?.let { "age ${it}ms" }
            ?: if (clock.resolved) "age —" else "age n/a (clock)"
        val analysis = analysisRate.perSecond()
        return buildString {
            append(ageText)
            append(" · cvt ").append(convert.median() ?: "—")
            append(" · pre ").append(prep.median() ?: "—")
            append(" · inf ").append(infer.median() ?: "—")
            append(" · ui ").append(uiDelay.median() ?: "—")
            append('\n')
            append(model)
            append(" · ").append(analysis?.let { "%.1f".format(it) } ?: "—").append(" in")
            append(" · ").append(drawnPerSecond?.let { "%.0f".format(it) } ?: "—").append(" drawn")
            coalescedShare()?.let { append(" · ").append(it).append("% coalesced") }
        }
    }
}
