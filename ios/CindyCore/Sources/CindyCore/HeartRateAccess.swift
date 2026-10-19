import Foundation

/// The athlete's answer to Bluetooth, as Core Bluetooth reports it (`CBManagerAuthorization`).
public enum BluetoothAccess: Equatable, Sendable {
    case notDetermined, allowed, denied, restricted
}

/// What the Bluetooth radio is doing (`CBManagerState`).
public enum BluetoothRadio: Equatable, Sendable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

/// What FIND MY WATCH does next. Port of the checks `MenuActivity.findMyWatch` makes, in the order
/// that makes each one's system prompt make sense: a radio that is not there first (no permission is
/// worth asking for), then permission, then the radio's state, then the scan.
public enum FindWatchStep: Equatable, Sendable {
    /// Bluetooth is allowed and on: open the search.
    case scan
    /// Not asked yet. Making the central manager is what makes iOS ask, so the answer arrives as a
    /// change of state, and nothing here explains it first.
    case askPermission
    /// Told no, or not allowed to say yes (a restriction): only Settings can change it.
    case openSettings
    /// Allowed, and the radio is off.
    case bluetoothOff
    /// No Bluetooth LE at all.
    case unsupported
    /// The radio is resetting or has not said yet: ask again when it does.
    case wait
}

/// What "Bluetooth is allowed" means on iOS. Port of `HeartRatePermissions`.
///
/// On Android 11 and older a Bluetooth scan is tied to the location permission, so the app has to
/// explain a location prompt to someone who asked to find a watch, and send them to Location's
/// switch when it is off. None of that exists here: iOS asks for Bluetooth, in words the app gave
/// it (`NSBluetoothAlwaysUsageDescription`), and a scan is never a location lookup. There is no
/// explanation sheet, no Location-off case, and nothing in the app that mentions location.
public enum HeartRateAccess {

    /// The words iOS shows in its own Bluetooth prompt, set in the app's Info.plist.
    public static let usageDescription =
        "Cindy reads the heart rate your watch or chest strap broadcasts. Nothing is uploaded."

    public static func next(access: BluetoothAccess, radio: BluetoothRadio) -> FindWatchStep {
        if radio == .unsupported { return .unsupported }
        switch access {
        case .denied, .restricted: return .openSettings
        case .notDetermined: return .askPermission
        case .allowed: break
        }
        switch radio {
        case .poweredOn: return .scan
        case .poweredOff: return .bluetoothOff
        case .unauthorized: return .openSettings
        case .unsupported: return .unsupported
        case .resetting, .unknown: return .wait
        }
    }

    /// Whether a source may connect: allowed, and the radio on.
    public static func canConnect(access: BluetoothAccess, radio: BluetoothRadio) -> Bool {
        next(access: access, radio: radio) == .scan
    }

    /// The status a source reports when it cannot connect, or nil when it can (or must wait).
    public static func blocked(access: BluetoothAccess, radio: BluetoothRadio) -> HeartRateStatus? {
        switch next(access: access, radio: radio) {
        case .unsupported: return .unsupported
        case .openSettings, .askPermission: return .noPermission
        case .bluetoothOff: return .bluetoothOff
        case .scan, .wait: return nil
        }
    }

    public static let unsupportedToast = "This phone has no Bluetooth LE, so it cannot hear a watch"
    public static let deniedTitle = "Bluetooth is off for Cindy"
    public static let deniedSubtitle = "Turn Bluetooth on for Cindy in Settings to find your watch. "
        + "Cindy only listens for heart-rate devices, and never reads your location."
    public static let bluetoothOffTitle = "Bluetooth is off"
    public static let bluetoothOffSubtitle = "Turn Bluetooth on, then look for your watch again."
}
