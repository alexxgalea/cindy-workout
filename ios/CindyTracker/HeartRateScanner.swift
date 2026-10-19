import CoreBluetooth
import Foundation
import CindyCore

/// A time-boxed search for nearby heart-rate broadcasters, for the "FIND MY WATCH" flow. Port of
/// `HeartRateScanner`.
///
/// Kept apart from `CoreBluetoothHeartRateSource`, which does its own short search to chase a watch
/// that changed identifier: that one runs unattended, while this one exists to be watched: the sheet
/// shows every device as it turns up, each with how strong it comes in, so the athlete can tell their
/// own watch from a stranger's chest strap in the next room.
///
/// Two things make a Garmin easy to miss with a plain filtered scan, and this search covers both:
/// - A watch already linked to the phone (through Garmin Connect, say) may not advertise to it, but
///   can still serve heart rate over the link it has, so every peripheral already connected with the
///   Heart Rate service is listed up front, marked "Connected to this phone".
/// - Where the Heart Rate service sits in an advertisement decides whether a filtered scan sees it, so
///   the scan is unfiltered and `HeartRateAdvert.matches` does the filtering on the whole record. That
///   is only safe in the foreground, with the sheet open, which is the only place this runs.
///
/// There is no location permission and no Location-off case on iOS; what can stand in the way is
/// `FindWatchStep`, which `onBlocked` reports.
final class HeartRateScanner: NSObject, CBCentralManagerDelegate {

    private var central: CBCentralManager?
    private var onFound: (([FoundDevice]) -> Void)?
    private var onBlocked: ((FindWatchStep) -> Void)?
    private var onDone: (() -> Void)?
    private var window: DispatchWorkItem?
    private var scanning = false

    private var seen: [String: FoundDevice] = [:]
    /// The order devices were first heard in, which the list holds still in.
    private var order: [String] = []
    private var connected: [FoundDevice] = []

    /// Searches for `HeartRateReconnect.scanWindowMs`, calling `onFound` with the growing list of
    /// matches, `onBlocked` if Bluetooth stands in the way, and `onDone` once the window closes on
    /// its own. Replaces a search already running.
    func start(onFound: @escaping ([FoundDevice]) -> Void, onBlocked: @escaping (FindWatchStep) -> Void,
               onDone: @escaping () -> Void) {
        stop()
        self.onFound = onFound
        self.onBlocked = onBlocked
        self.onDone = onDone
        // Making the manager is what makes iOS ask for Bluetooth, if it has not been asked.
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    /// Ends the search, if one is running, without calling `onDone`: the callers that stop it early,
    /// a dismissed sheet and a device already picked, already know why it ended.
    func stop() {
        window?.cancel()
        window = nil
        if scanning { central?.stopScan() }
        scanning = false
        central = nil
        seen.removeAll()
        order.removeAll()
        connected = []
        onFound = nil
        onBlocked = nil
        onDone = nil
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central else { return }
        switch HeartRateAccess.next(access: .current, radio: BluetoothRadio(central.state)) {
        case .scan:
            if !scanning { beginScan(central) }
        case .askPermission, .wait:
            break
        case let step:
            let report = onBlocked
            stop()
            report?(step)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === self.central, scanning else { return }
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .compactMap(HeartRateUuids.full)
        var makers: [Int] = []
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
            // The company identifier is the first two bytes, little-endian.
            let bytes = [UInt8](data)
            makers = [Int(bytes[0]) | (Int(bytes[1]) << 8)]
        }
        guard HeartRateAdvert.matches(serviceUuids: services, manufacturerIds: makers) else { return }
        let address = peripheral.identifier.uuidString
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let previous = seen[address]
        if previous == nil { order.append(address) }
        seen[address] = HeartRateAdvert.heard(previous: previous, address: address, name: name, rssi: RSSI.intValue)
        onFound?(HeartRateAdvert.merge(connected: connected, advertising: order.compactMap { seen[$0] }))
    }

    // MARK: -

    private func beginScan(_ central: CBCentralManager) {
        scanning = true
        connected = central.retrieveConnectedPeripherals(withServices: [HeartRateUuids.service]).map {
            FoundDevice($0.identifier.uuidString, $0.name ?? "Connected device", rssi: nil, connected: true)
        }
        if !connected.isEmpty { onFound?(HeartRateAdvert.merge(connected: connected, advertising: [])) }
        // Duplicates on: a watch advertises many times a second, and a signal that only ever showed
        // its first packet would never change.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.scanning else { return }
            let done = self.onDone
            self.stop()
            done?()
        }
        window = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(HeartRateReconnect.scanWindowMs)), execute: work)
    }
}
