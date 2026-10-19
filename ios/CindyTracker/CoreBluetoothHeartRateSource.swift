import CoreBluetooth
import Foundation
import CindyCore

/// A live connection to one saved heart-rate `device`, over the standard Bluetooth LE Heart Rate
/// profile. Port of `BleHeartRateSource`.
///
/// Every callback arrives on the main queue (the manager is made on it), so `listener` only ever hears
/// from this on the main thread and every call back into Core Bluetooth is made from there too.
///
/// What differs from Android, and why:
/// - A device's address is its identifier on this phone (a UUID), which `retrievePeripherals` turns
///   back into a peripheral. There is no hardware address on iOS, so the "moved to a new address"
///   fallback looks for a peripheral of the same name instead, exactly when Android's would.
/// - Android drops its cached service list and looks again when a Garmin bonded through Garmin Connect
///   shows no Heart Rate service. Core Bluetooth has no call that drops its cache. A device that shows
///   no service is reported as not sending heart rate, and turning Broadcast Heart Rate on and
///   looking again (which the sheet says) finds it, because a fresh pairing is a fresh discovery.
/// - Bluetooth being switched off or allowed mid-workout is normal on a phone, so the source keeps
///   wanting the device and connects when the radio comes back, where Android gives up.
final class CoreBluetoothHeartRateSource: NSObject, HeartRateSource {

    private var device: HeartRateDevice
    private let onDeviceMoved: (HeartRateDevice) -> Void
    private let clock: () -> Int64

    private var listener: HeartRateListener?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    /// Whether `stop` has not been called. False from construction until the first `start`.
    private var wanted = false
    /// Reconnect attempts since the last successful connection; feeds `HeartRateReconnect`.
    private var attempt = 0
    /// Consecutive failures with no successful connection between them: the trigger for looking for
    /// a moved watch.
    private var consecutiveFailures = 0
    /// So `connected` is reported once, on the first plausible reading.
    private var reportedConnected = false
    private var reconnectWork: DispatchWorkItem?
    private var lookWork: DispatchWorkItem?
    private var looking = false

    init(device: HeartRateDevice, onDeviceMoved: @escaping (HeartRateDevice) -> Void = { _ in },
         clock: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) }) {
        self.device = device
        self.onDeviceMoved = onDeviceMoved
        self.clock = clock
    }

    // MARK: HeartRateSource

    func start(listener: HeartRateListener) {
        self.listener = listener
        // Already connected, connecting, waiting to retry or chasing a moved watch: a second start
        // only changes who hears about it. Connecting again would open a second link to the same
        // device and orphan the first.
        if wanted && (peripheral != nil || looking || reconnectWork != nil) { return }
        wanted = true
        attempt = 0
        consecutiveFailures = 0
        if let central {
            connect(central)
        } else {
            // Making the manager is what makes iOS ask for Bluetooth, if it has not been asked; the
            // answer, and every later change of the radio, arrives in `centralManagerDidUpdateState`.
            central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func stop() {
        wanted = false
        cancelTimers()
        stopLooking()
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        central = nil
        report(.off)
        listener = nil
    }

    // MARK: connecting

    private func connect(_ central: CBCentralManager) {
        guard wanted else { return }
        let access = BluetoothAccess.current
        let radio = BluetoothRadio(central.state)
        if let blocked = HeartRateAccess.blocked(access: access, radio: radio) {
            report(blocked)
            // Unsupported and refused are final; a radio that is off comes back by itself.
            if blocked != .bluetoothOff { wanted = false }
            return
        }
        // Not asked yet, or the radio has not said: `centralManagerDidUpdateState` calls again.
        guard HeartRateAccess.canConnect(access: access, radio: radio) else { return }

        report(.connecting)
        reportedConnected = false
        if let old = peripheral { central.cancelPeripheralConnection(old) }
        peripheral = nil
        guard let id = UUID(uuidString: device.address),
              let remote = central.retrievePeripherals(withIdentifiers: [id]).first else {
            // A saved address this phone has no peripheral for: the watch may be known by another
            // identifier now, which is what looking by name finds.
            noteFailure()
            return
        }
        peripheral = remote
        remote.delegate = self
        central.connect(remote, options: nil)
    }

    /// The link just dropped or errored. It is closed either way, and, while still wanted, a
    /// reconnect is scheduled; after two failures in a row the schedule is replaced by a look for a
    /// watch of the same name.
    private func handleLost() {
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        guard wanted else { return }
        noteFailure()
    }

    private func noteFailure() {
        consecutiveFailures += 1
        attempt += 1
        report(.connecting)
        if consecutiveFailures >= HeartRateReconnect.failuresBeforeLooking {
            lookForMovedDevice()
        } else {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let central = self.central else { return }
            self.reconnectWork = nil
            self.connect(central)
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(HeartRateReconnect.delayMs(attempt))), execute: work)
    }

    private func lookForMovedDevice() {
        guard let central, central.state == .poweredOn else {
            scheduleReconnect()
            return
        }
        looking = true
        central.scanForPeripherals(withServices: [HeartRateUuids.service], options: nil)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.looking else { return }
            self.stopLooking()
            self.scheduleReconnect()
        }
        lookWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(HeartRateReconnect.lookWindowMs)), execute: work)
    }

    private func stopLooking() {
        lookWork?.cancel()
        lookWork = nil
        if looking { central?.stopScan() }
        looking = false
    }

    private func cancelTimers() {
        reconnectWork?.cancel()
        reconnectWork = nil
    }

    private func report(_ status: HeartRateStatus) { listener?.onStatus(status) }

    private func deliver(_ value: Data) {
        guard let reading = HeartRateMeasurement.parse([UInt8](value)), HeartRateMeasurement.plausible(reading) else { return }
        if !reportedConnected {
            reportedConnected = true
            report(.connected)
        }
        listener?.onHeartRate(bpm: reading.bpm, atElapsedMs: clock())
    }
}

// MARK: - the radio

extension CoreBluetoothHeartRateSource: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard wanted, central === self.central else { return }
        if central.state == .poweredOn {
            if peripheral == nil && !looking && reconnectWork == nil { connect(central) }
        } else {
            // The radio went, or permission did: nothing connected survives it. Say why, and wait
            // for it to come back.
            cancelTimers()
            stopLooking()
            peripheral = nil
            if let blocked = HeartRateAccess.blocked(access: .current, radio: BluetoothRadio(central.state)) {
                report(blocked)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard wanted, peripheral === self.peripheral else { return }
        consecutiveFailures = 0
        attempt = 0
        peripheral.discoverServices([HeartRateUuids.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        handleLost()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        handleLost()
    }

    func centralManager(_ central: CBCentralManager, didDiscover found: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard looking else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? found.name
        guard let name, name == device.name else { return }
        stopLooking()
        device = HeartRateDevice(address: found.identifier.uuidString, name: device.name)
        onDeviceMoved(device)
        consecutiveFailures = 0
        connect(central)
    }
}

// MARK: - the link

extension CoreBluetoothHeartRateSource: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard wanted, peripheral === self.peripheral else { return }
        if error != nil {
            handleLost()
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == HeartRateUuids.service }) else {
            // Connected, and no Heart Rate service: it is not broadcasting. Final, until the athlete
            // turns the broadcast on and looks again.
            report(.notAHeartRateDevice)
            wanted = false
            if let central { central.cancelPeripheralConnection(peripheral) }
            self.peripheral = nil
            return
        }
        peripheral.discoverCharacteristics([HeartRateUuids.measurement], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard wanted, peripheral === self.peripheral else { return }
        if error != nil {
            handleLost()
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == HeartRateUuids.measurement }) else {
            report(.notAHeartRateDevice)
            wanted = false
            if let central { central.cancelPeripheralConnection(peripheral) }
            self.peripheral = nil
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard wanted, peripheral === self.peripheral else { return }
        if error != nil {
            handleLost()
            return
        }
        // Subscribed, and nothing heard yet: see `HeartRateStatus.waiting`. A reading that raced ahead
        // of this callback has already said `connected`, which stands.
        if characteristic.isNotifying && !reportedConnected { report(.waiting) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard wanted, peripheral === self.peripheral, error == nil, let value = characteristic.value else { return }
        deliver(value)
    }
}
