import Foundation

/// What the heart-rate sheets say, decided apart from how they look. Port of the heart-rate half of
/// `MenuActivity`: the unpaired sheet, the live status line of the paired one, the scan's rows.
public enum HeartRateSheets {

    public static let title = "Heart rate"
    public static let subtitle = "Reads the heart rate your watch or chest strap broadcasts, and uses it "
        + "for calories. Nothing is uploaded."

    /// Said before pairing. iOS: an Apple Watch does not broadcast a standard heart rate, and nor do
    /// most smartwatches, so the Wear OS name is gone with the Android phrase it was in.
    public static let unpairedNote = "Turn on heart-rate broadcast on your watch first. Garmin: Broadcast "
        + "Heart Rate. Polar: share heart rate with other devices. Chest straps broadcast whenever they "
        + "are worn. Apple Watch and most smartwatches do not broadcast a standard heart rate."

    public static let findMyWatch = "FIND MY WATCH"
    public static let scanTitle = "Looking for heart-rate devices"
    public static let nothingYet = "Nothing yet — keep your watch on its broadcast screen"
    public static let connectingMessage = "Connecting…"
    public static let yourDetails = "Your details"
    public static let findAnother = "Find another watch"
    public static let findAnotherSubtitle = "Pair a different device"
    public static let scanAgain = "SCAN AGAIN"
    public static let forget = "FORGET"

    /// What the paired sheet's status line says for a status, and the hint it falls back to if nothing
    /// changes for a while. A status of `connected` or `off` says nothing: the reading says it.
    public struct Line: Equatable, Sendable {
        public let message: String?
        public let hint: Hint?
    }

    public struct Hint: Equatable, Sendable {
        public let text: String
        public let afterMs: Int64
    }

    public static func line(for status: HeartRateStatus) -> Line {
        switch status {
        case .connecting:
            return Line(message: connectingMessage,
                        hint: Hint(text: "Can't find it — is heart-rate broadcast on?", afterMs: 15_000))
        // Found and listening: if nothing comes, the watch is not broadcasting, and that is the one
        // thing worth saying.
        case .waiting:
            return Line(message: "Connected — waiting for heart rate…",
                        hint: Hint(text: "Connected, but no heart rate — is heart-rate broadcast on?", afterMs: 8_000))
        case .noPermission: return Line(message: "Bluetooth permission is off", hint: nil)
        case .bluetoothOff: return Line(message: "Bluetooth is off", hint: nil)
        case .notAHeartRateDevice: return Line(message: "No heart rate from it — is heart-rate broadcast on?", hint: nil)
        case .unsupported: return Line(message: "This phone has no Bluetooth LE", hint: nil)
        case .connected, .off: return Line(message: nil, hint: nil)
        }
    }

    /// The line for a reading.
    public static func reading(_ bpm: Int) -> String { "\(bpm) bpm" }

    /// "Strong" / "Good" / "Weak": the bands the scan sheet shows instead of a raw dBm figure.
    public static func signalLabel(_ rssi: Int) -> String {
        if rssi >= -60 { return "Strong" }
        if rssi >= -75 { return "Good" }
        return "Weak"
    }

    /// What a scan row says under the device's name. A device already linked to the phone says so
    /// (that is how a Garmin paired through Garmin Connect is told apart) and shows its signal too when
    /// it was also heard advertising.
    public static func foundLabel(_ found: FoundDevice) -> String {
        let signal = found.rssi.map(signalLabel)
        if found.connected { return signal.map { "Connected to this phone · \($0)" } ?? "Connected to this phone" }
        return signal ?? ""
    }

    /// The row spoken as one sentence.
    public static func spoken(_ found: FoundDevice) -> String {
        let label = foundLabel(found)
        return label.isEmpty ? found.name : "\(found.name), \(label)"
    }

    /// What pairing a device saves, and whether the details sheet follows: the formula needs an age
    /// and a sex, and a freshly paired watch is always missing them.
    public static func adopt(_ found: FoundDevice, into profile: Profile, nowYear: Int) -> Bool {
        profile.heartRateDevice = HeartRateDevice(address: found.address, name: found.name)
        return !profile.body(nowYear: nowYear).canUseHeartRate
    }

    /// The toast when a watch is paired but silent as the workout starts, or nil when a reading is
    /// recent. `lastReadingAtMs` is the monotonic clock at the last reading, 0 for none.
    public static func silentWarning(device: HeartRateDevice?, sourceRunning: Bool, nowMs: Int64,
                                     lastReadingAtMs: Int64) -> String? {
        guard sourceRunning, let device, nowMs - lastReadingAtMs > 10_000 else { return nil }
        return "No heart rate from \(device.name) yet — calories will use your reps until it arrives"
    }
}
