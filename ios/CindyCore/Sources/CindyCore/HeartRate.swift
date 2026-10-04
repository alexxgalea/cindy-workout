import Foundation

/// One heart-rate reading, stamped on the workout clock.
///
/// `clockMs` is the same clock `Attempt.durationMs` and `Attempt.roundSplitsMs` already use: elapsed
/// running time with pauses excluded, so a trace and the attempt it belongs to describe one timeline
/// without any translation between them.
public struct HeartRateSample: Equatable, Sendable {
    public let clockMs: Int64
    public let bpm: Int

    public init(_ clockMs: Int64, _ bpm: Int) {
        self.clockMs = clockMs
        self.bpm = bpm
    }
}

/// The clock stood still at `atClockMs` for `lengthMs` of real time.
public struct HeartRatePause: Equatable, Sendable {
    public let atClockMs: Int64
    public let lengthMs: Int64

    public init(atClockMs: Int64, lengthMs: Int64) {
        self.atClockMs = atClockMs
        self.lengthMs = lengthMs
    }
}

/// Everything a watch or strap sent during one attempt.
///
/// Kept apart from `Attempt` itself, and from the record board's own storage: about a sample a
/// second for twenty minutes is well over a thousand readings, which would bloat the one string
/// `RecordStore` rewrites whole on every save. See `HeartRateStore` for where a trace actually lives.
public struct HeartRateTrace: Equatable, Sendable {
    /// Wall-clock epoch ms at which the workout clock started.
    public let startedAtMillis: Int64
    public let samples: [HeartRateSample]
    public let pauses: [HeartRatePause]

    public init(startedAtMillis: Int64, samples: [HeartRateSample], pauses: [HeartRatePause]) {
        self.startedAtMillis = startedAtMillis
        self.samples = samples
        self.pauses = pauses
    }
}

/// A saved watch or strap.
///
/// `name` is what the scan showed. It is kept for more than display: a device's identifier can change
/// between sessions, and `name` is the fallback a reconnect matches against when the saved `address`
/// no longer answers.
public struct HeartRateDevice: Equatable, Sendable {
    public let address: String
    public let name: String

    public init(address: String, name: String) {
        self.address = address
        self.name = name
    }
}

/// Whether the strap reports this reading as one it is actually reading skin contact for.
public enum SensorContact: Sendable { case unsupported, detected, notDetected }

public struct HeartRateReading: Equatable, Sendable {
    public let bpm: Int
    public let contact: SensorContact

    public init(_ bpm: Int, _ contact: SensorContact) {
        self.bpm = bpm
        self.contact = contact
    }
}

/// The standard Bluetooth LE Heart Rate profile: the one service every device this plan supports
/// (Garmin, Polar, Coros, and nearly every chest strap) broadcasts, so one set of UUIDs covers all of them.
public enum HeartRateGatt {
    public static let service = UUID(uuidString: "0000180d-0000-1000-8000-00805f9b34fb")!
    public static let measurement = UUID(uuidString: "00002a37-0000-1000-8000-00805f9b34fb")!
    public static let clientConfig = UUID(uuidString: "00002902-0000-1000-8000-00805f9b34fb")!
}

/// Decodes characteristic 0x2A37, the value the Heart Rate Measurement notification carries.
///
/// Free of Bluetooth types on purpose. This is the part of the watch link with actual format quirks
/// to get right (a uint8 or uint16 reading, a contact flag that can mean three different things), and
/// keeping it pure means those quirks are provable in a plain test instead of only on a device with a
/// strap in hand. Port of `HeartRateMeasurement`.
public enum HeartRateMeasurement {

    /// Below this the equation, and probably the sensor, has stopped meaning anything.
    public static let minBpm = 30

    /// A hard effort can legitimately sit near here; it is not by itself a reason to distrust it.
    public static let maxBpm = 230

    /// Parses characteristic 0x2A37. Nil when the payload is too short to hold a reading.
    public static func parse(_ value: [UInt8]) -> HeartRateReading? {
        if value.count < 2 { return nil }
        let flags = Int(value[0])
        let bpm: Int
        if flags & 0x01 != 0 {
            // Bit 0 set: the reading is a uint16, little-endian, at [1...2].
            if value.count < 3 { return nil }
            bpm = Int(value[1]) | (Int(value[2]) << 8)
        } else {
            // Otherwise it is a single uint8 at [1].
            bpm = Int(value[1])
        }
        // Bits 3 (energy expended) and 4 (RR intervals) are never read. Either would mean chasing a
        // variable-length tail this app has no use for, so parsing stops at the HR bytes.
        let contact: SensorContact
        if flags & 0x04 == 0 { contact = .unsupported }
        else if flags & 0x02 != 0 { contact = .detected }
        else { contact = .notDetected }
        return HeartRateReading(bpm, contact)
    }

    /// Worth keeping: contact not reported lost, and bpm in `minBpm...maxBpm`.
    public static func plausible(_ r: HeartRateReading) -> Bool {
        r.contact != .notDetected && (minBpm...maxBpm).contains(r.bpm)
    }
}

/// What a `HeartRateSource` is doing right now.
///
/// `waiting` is connected and subscribed with no reading yet. It is its own state because a watch with
/// its broadcast off behaves exactly so: it accepts the connection and the subscription, then says
/// nothing until the broadcast is started, which on a fenix took 35 seconds in one test. Calling that
/// "connecting" sent the athlete looking for a fault in the connection rather than on the watch.
public enum HeartRateStatus: CaseIterable, Sendable {
    case off, connecting, waiting, connected, noPermission, bluetoothOff, unsupported, notAHeartRateDevice
}

/// Callbacks from a `HeartRateSource`. Always delivered on the main thread.
public protocol HeartRateListener: AnyObject {
    /// Plausible readings only. `atElapsedMs` is the monotonic clock at receipt.
    func onHeartRate(bpm: Int, atElapsedMs: Int64)

    func onStatus(_ status: HeartRateStatus)
}

/// A live connection to one heart-rate device.
///
/// The Core Bluetooth source (P15) is the one real implementation, over the standard Bluetooth LE
/// Heart Rate profile. It stays behind a protocol so that everything downstream of a reading (the
/// recorder, the calorie estimate) can still be tested with no Bluetooth stack behind it at all.
public protocol HeartRateSource {
    /// Connect, and keep reconnecting until `stop`. Idempotent. Main thread.
    func start(listener: HeartRateListener)

    /// Disconnect and stop retrying. Idempotent. Main thread.
    func stop()
}
