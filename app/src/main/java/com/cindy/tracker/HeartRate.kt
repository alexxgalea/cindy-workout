package com.cindy.tracker

import android.content.Context
import java.util.UUID

/**
 * One heart-rate reading, stamped on the workout clock.
 *
 * [clockMs] is the same clock [Attempt.durationMs] and [Attempt.roundSplitsMs] already use —
 * elapsed running time with pauses excluded — so a trace and the attempt it belongs to describe
 * one timeline without any translation between them.
 */
data class HeartRateSample(val clockMs: Long, val bpm: Int)

/** The clock stood still at [atClockMs] for [lengthMs] of real time. */
data class HeartRatePause(val atClockMs: Long, val lengthMs: Long)

/**
 * Everything a watch or strap sent during one attempt.
 *
 * Kept apart from [Attempt] itself, and from the record board's own storage: about a sample a
 * second for twenty minutes is well over a thousand readings, which would bloat the one
 * SharedPreferences string [RecordStore] rewrites whole on every save, and the Intent that
 * carries an attempt to the results screen. See [HeartRateStore] for where a trace actually
 * lives.
 */
data class HeartRateTrace(
    /** Wall-clock epoch ms at which the workout clock started. */
    val startedAtMillis: Long,
    val samples: List<HeartRateSample>,
    val pauses: List<HeartRatePause>
)

/**
 * A saved watch or strap.
 *
 * [name] is what the scan showed. It is kept for more than display: a watch's Bluetooth address
 * can change between sessions, and [name] is the fallback a reconnect matches against when the
 * saved [address] no longer answers.
 */
data class HeartRateDevice(val address: String, val name: String)

/** Whether the strap reports this reading as one it is actually reading skin contact for. */
enum class SensorContact { UNSUPPORTED, DETECTED, NOT_DETECTED }

data class HeartRateReading(val bpm: Int, val contact: SensorContact)

/**
 * The standard Bluetooth LE Heart Rate profile: the one service every device this plan supports —
 * Garmin, Polar, Coros, and nearly every chest strap — broadcasts, so one set of UUIDs covers all
 * of them.
 */
object HeartRateGatt {
    val SERVICE: UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
    val MEASUREMENT: UUID = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
    val CLIENT_CONFIG: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

/**
 * Decodes characteristic 0x2A37, the value the Heart Rate Measurement notification carries.
 *
 * Free of Android and Bluetooth types on purpose. This is the part of the watch link with actual
 * format quirks to get right — a uint8 or uint16 reading, a contact flag that can mean three
 * different things — and keeping it pure means those quirks are provable in a plain JVM test
 * instead of only on a device with a strap in hand.
 */
object HeartRateMeasurement {

    /** Below this the equation, and probably the sensor, has stopped meaning anything. */
    const val MIN_BPM = 30

    /** A hard effort can legitimately sit near here; it is not by itself a reason to distrust it. */
    const val MAX_BPM = 230

    /** Parses characteristic 0x2A37. Null when the payload is too short to hold a reading. */
    fun parse(value: ByteArray): HeartRateReading? {
        if (value.size < 2) return null
        val flags = value[0].toInt() and 0xFF
        val bpm = if (flags and 0x01 != 0) {
            // Bit 0 set: the reading is a uint16, little-endian, at [1..2].
            if (value.size < 3) return null
            (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        } else {
            // Otherwise it is a single uint8 at [1].
            value[1].toInt() and 0xFF
        }
        // Bits 3 (energy expended) and 4 (RR intervals) are never read. Both are parsed only to
        // be skipped by this plan, and either would mean chasing a variable-length tail this app
        // has no use for — so parsing stops at the HR bytes and goes no further.
        val contact = when {
            flags and 0x04 == 0 -> SensorContact.UNSUPPORTED
            flags and 0x02 != 0 -> SensorContact.DETECTED
            else -> SensorContact.NOT_DETECTED
        }
        return HeartRateReading(bpm, contact)
    }

    /** Worth keeping: contact not reported lost, and bpm in [MIN_BPM]..[MAX_BPM]. */
    fun plausible(r: HeartRateReading): Boolean =
        r.contact != SensorContact.NOT_DETECTED && r.bpm in MIN_BPM..MAX_BPM
}

/**
 * What a [HeartRateSource] is doing right now.
 *
 * [WAITING] is connected and subscribed with no reading yet. It is its own state because a watch
 * with its broadcast off behaves exactly so: it accepts the connection and the subscription, then
 * says nothing until the broadcast is started, which on a fenix took 35 seconds in one test. Calling
 * that "connecting" sent the athlete looking for a fault in the connection rather than on the watch.
 */
enum class HeartRateStatus {
    OFF, CONNECTING, WAITING, CONNECTED, NO_PERMISSION, BLUETOOTH_OFF, UNSUPPORTED,
    NOT_A_HEART_RATE_DEVICE
}

/** Callbacks from a [HeartRateSource]. Always delivered on the main thread. */
interface HeartRateListener {
    /** Plausible readings only. [atElapsedMs] = SystemClock.elapsedRealtime() at receipt. */
    fun onHeartRate(bpm: Int, atElapsedMs: Long)

    fun onStatus(status: HeartRateStatus)
}

/**
 * A live connection to one heart-rate device.
 *
 * [BleHeartRateSource] is the one real implementation, over the standard Bluetooth LE Heart Rate
 * profile. It stays behind an interface so that everything downstream of a reading — the
 * recorder, the calorie estimate — can still be tested on the JVM, with no Bluetooth stack behind
 * it at all.
 */
interface HeartRateSource {
    /** Connect, and keep reconnecting until [stop]. Idempotent. Main thread. */
    fun start(listener: HeartRateListener)

    /** Disconnect and stop retrying. Idempotent. Main thread. */
    fun stop()
}

object HeartRateSources {
    /**
     * The source for whichever device [profile] has saved, or null when there is none to build
     * one for.
     *
     * Null until a watch has been paired: with no device saved there is nothing to connect to.
     * Once one is, this hands back a fresh [BleHeartRateSource] for it on every call — neither
     * this object nor [Profile] holds a connection open on the caller's behalf, so whoever asked
     * for one owns starting and stopping it.
     */
    fun forProfile(context: Context, profile: Profile): HeartRateSource? =
        profile.heartRateDevice?.let { device ->
            BleHeartRateSource(
                context.applicationContext,
                device,
                onDeviceMoved = { moved -> profile.heartRateDevice = moved }
            )
        }
}
