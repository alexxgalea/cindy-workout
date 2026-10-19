import CoreBluetooth
import CindyCore

/// Core Bluetooth's words for the athlete's answer and the radio's state, in the core's. The core
/// decides what each means (`HeartRateAccess`); these only translate.
extension BluetoothAccess {
    init(_ authorization: CBManagerAuthorization) {
        switch authorization {
        case .allowedAlways: self = .allowed
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    /// What the athlete has said so far, which is a property of the app and not of any manager.
    static var current: BluetoothAccess { BluetoothAccess(CBCentralManager.authorization) }
}

extension BluetoothRadio {
    init(_ state: CBManagerState) {
        switch state {
        case .poweredOn: self = .poweredOn
        case .poweredOff: self = .poweredOff
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .resetting: self = .resetting
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}

/// The Heart Rate service and its measurement characteristic as Core Bluetooth names them.
enum HeartRateUuids {
    static let service = CBUUID(string: HeartRateGatt.service.uuidString)
    static let measurement = CBUUID(string: HeartRateGatt.measurement.uuidString)

    /// A 128-bit UUID for one an advertisement lists, which Core Bluetooth shortens to 16 or 32 bits
    /// when it is built on the Bluetooth base UUID.
    static func full(_ uuid: CBUUID) -> UUID? {
        let text = uuid.uuidString
        switch text.count {
        case 4: return UUID(uuidString: "0000\(text)-0000-1000-8000-00805F9B34FB")
        case 8: return UUID(uuidString: "\(text)-0000-1000-8000-00805F9B34FB")
        default: return UUID(uuidString: text)
        }
    }
}
