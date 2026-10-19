import Foundation

/// One device the search turned up: its address, its best guess at a name, and how strong it came in.
///
/// `address` is what Core Bluetooth calls a peripheral's identifier, a UUID that is stable on this
/// phone and meaningless on any other (iOS never shows a hardware address). `rssi` is nil for a device
/// that was only found through its existing connection to this phone (see `HeartRateScanner`) and
/// never heard advertising, so there is no signal figure to show. `connected` is true whenever the
/// phone already holds a link to it: a Garmin paired through Garmin Connect, typically.
public struct FoundDevice: Equatable, Sendable {
    public let address: String
    public let name: String
    public let rssi: Int?
    public let connected: Bool

    public init(_ address: String, _ name: String, rssi: Int?, connected: Bool = false) {
        self.address = address
        self.name = name
        self.rssi = rssi
        self.connected = connected
    }

    public func with(rssi: Int?) -> FoundDevice { FoundDevice(address, name, rssi: rssi, connected: connected) }
    public func with(name: String) -> FoundDevice { FoundDevice(address, name, rssi: rssi, connected: connected) }
    public func with(connected: Bool) -> FoundDevice { FoundDevice(address, name, rssi: rssi, connected: connected) }
}

/// Which advertisements are worth showing, kept free of Core Bluetooth so it can be tested as it is.
/// Port of `HeartRateAdvert` in `HeartRateScanner.kt`.
///
/// The Heart Rate service UUID is the real signal. The Garmin manufacturer ID is the fallback for a
/// watch that advertises its broadcast without listing the service up front: connecting to it is what
/// settles the question, and the source already reports a device that turns out not to send heart rate.
public enum HeartRateAdvert {

    /// Bluetooth SIG company identifier for Garmin International.
    public static let garminCompanyId = 0x0087

    public static func matches(serviceUuids: [UUID]?, manufacturerIds: [Int]) -> Bool {
        serviceUuids?.contains(HeartRateGatt.service) == true || manufacturerIds.contains(garminCompanyId)
    }

    /// The list the sheet shows: devices already connected to the phone first (that is almost always
    /// the athlete's own watch), then everything heard advertising, in the order it was first heard. A
    /// connected device that was also heard advertising is listed once, keeping its signal.
    ///
    /// Not sorted by signal. A watch broadcasting heart rate advertises many times a second and its
    /// signal jitters by several dBm between packets, so two devices at a similar distance would trade
    /// places under the athlete's finger, and a tap could land on the wrong one. The signal is still on
    /// every row; the order just holds still.
    public static func merge(connected: [FoundDevice], advertising: [FoundDevice]) -> [FoundDevice] {
        var heard: [String: FoundDevice] = [:]
        for device in advertising { heard[device.address] = device }
        let linked = connected.map { c in heard[c.address].map { c.with(rssi: $0.rssi) } ?? c }
        let linkedAddresses = Set(linked.map { $0.address })
        return linked + advertising.filter { !linkedAddresses.contains($0.address) }
    }

    /// What a row is called until something names the device.
    public static let unnamed = "Heart-rate sensor"

    /// The row for one more advertisement from `address`, given the row it had before.
    ///
    /// A name, once heard, is kept. A device can name itself in one packet and not the next (the name
    /// often rides only in the scan response), and a row that flipped between its name and `unnamed`
    /// would be rebuilt on every other packet, which is exactly what `sameRows` exists to prevent.
    public static func heard(previous: FoundDevice?, address: String, name: String?, rssi: Int) -> FoundDevice {
        FoundDevice(address, name ?? previous?.name ?? unnamed, rssi: rssi)
    }

    /// Whether `next` lists the same devices as `shown`, under the same names and in the same order, so
    /// that the rows on screen can be relabelled where they stand rather than rebuilt.
    ///
    /// Rebuilding is what made the list untappable on Android: a tap is cancelled when the view under
    /// the finger is removed, and a rebuild on every advertisement removes it several times a second.
    /// Only a signal changes between most updates, and a signal is a label.
    public static func sameRows(shown: [FoundDevice], next: [FoundDevice]) -> Bool {
        shown.count == next.count && zip(shown, next).allSatisfy { a, b in
            a.address == b.address && a.name == b.name && a.connected == b.connected
        }
    }
}

/// How long to wait before the `attempt`th reconnect. Port of `BleHeartRateSource.reconnectDelayMs`.
public enum HeartRateReconnect {

    /// 1 s, 2 s, 4 s, 8 s, then capped at 10 s. `attempt` is 1 for the first retry.
    public static func delayMs(_ attempt: Int) -> Int64 {
        switch attempt {
        case ...1: return 1_000
        case 2: return 2_000
        case 3: return 4_000
        case 4: return 8_000
        default: return 10_000
        }
    }

    /// Consecutive failures with no successful connection between them before the source stops
    /// retrying the saved address and looks for a watch of the same name. One dropped connection is
    /// normal and no reason to suspect the watch changed address.
    public static let failuresBeforeLooking = 2

    /// How long the unattended search for a moved watch lasts.
    public static let lookWindowMs: Int64 = 10_000

    /// How long the sheet's search for a watch lasts.
    public static let scanWindowMs: Int64 = 12_000
}
