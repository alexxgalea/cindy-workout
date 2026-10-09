import SwiftUI
import UIKit
import CindyCore

/// What the Heart rate sheets show and do. `HeartRateSheets` writes every word; `HeartRateAccess`
/// decides what Bluetooth permits; the source and scanner talk to the radio. This holds the state the
/// two sheets draw. Port of the heart-rate half of `MenuActivity`.
///
/// Not main-actor isolated, because `HeartRateListener` is not; every callback into it arrives on
/// the main queue (the source and the scanner make their managers on it).
final class HeartRateModel: ObservableObject, HeartRateListener {

    let profile: Profile
    private let onChanged: () -> Void

    @Published private(set) var device: HeartRateDevice?
    @Published private(set) var statusText = HeartRateSheets.connectingMessage
    @Published private(set) var isReading = false

    @Published var scanning = false
    @Published private(set) var found: [FoundDevice] = []
    @Published private(set) var scanDone = false
    @Published private(set) var blocked: FindWatchStep?
    @Published var askDetails = false

    private var source: HeartRateSource?
    private let scanner = HeartRateScanner()
    private var hint: DispatchWorkItem?

    init(profile: Profile, onChanged: @escaping () -> Void) {
        self.profile = profile
        self.onChanged = onChanged
        device = profile.heartRateDevice
    }

    var nowYear: Int { Calendar.current.component(.year, from: Date()) }

    var detailsSubtitle: String { MenuBuilder.heartRateDetailsSubtitle(profile, nowYear: nowYear) }

    // MARK: the live connection behind the paired sheet

    func appear() { startLive() }

    /// Sheet-scoped, like the voice's audition: started when the sheet opens and stopped when it
    /// closes, so a connection is never held open for a sheet nobody is looking at.
    func disappear() {
        stopLive()
        scanner.stop()
    }

    private func startLive() {
        stopLive()
        guard let saved = profile.heartRateDevice else { return }
        device = saved
        statusText = HeartRateSheets.connectingMessage
        isReading = false
        let live = CoreBluetoothHeartRateSource(device: saved, onDeviceMoved: { [profile] moved in
            profile.heartRateDevice = moved
        })
        source = live
        live.start(listener: self)
    }

    private func stopLive() {
        hint?.cancel()
        hint = nil
        source?.stop()
        source = nil
    }

    func onHeartRate(bpm: Int, atElapsedMs: Int64) {
        hint?.cancel()
        statusText = HeartRateSheets.reading(bpm)
        isReading = true
    }

    func onStatus(_ status: HeartRateStatus) {
        hint?.cancel()
        isReading = false
        let line = HeartRateSheets.line(for: status)
        if let message = line.message { statusText = message }
        if let wait = line.hint {
            let work = DispatchWorkItem { [weak self] in self?.statusText = wait.text }
            hint = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(wait.afterMs)), execute: work)
        }
    }

    // MARK: finding a watch

    func findMyWatch() {
        stopLive()
        found = []
        scanDone = false
        blocked = nil
        scanning = true
        scanner.start(
            onFound: { [weak self] devices in self?.found = devices },
            onBlocked: { [weak self] step in self?.blocked = step },
            onDone: { [weak self] in self?.scanDone = true })
    }

    /// CANCEL, or the sheet swiped away: the search ends, and a paired watch carries on.
    func cancelScan() {
        scanner.stop()
        scanning = false
        // Not after a device was just picked: that already started its connection.
        if source == nil, profile.heartRateDevice != nil { startLive() }
    }

    /// Saves the device as the paired one and shows the sheet on it, straight into "Your details"
    /// first when the formula still needs them, since that is the one thing a freshly paired watch is
    /// always missing.
    func adopt(_ chosen: FoundDevice) {
        scanner.stop()
        scanning = false
        let needsDetails = HeartRateSheets.adopt(chosen, into: profile, nowYear: nowYear)
        device = profile.heartRateDevice
        onChanged()
        startLive()
        askDetails = needsDetails
    }

    func forget() {
        stopLive()
        profile.heartRateDevice = nil
        device = nil
        onChanged()
    }

    func detailsChanged() { onChanged() }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// Everything heart rate: pairing a watch, or, once one is paired, a live status line and the age
/// and sex the formula still needs.
struct HeartRateSheet: View {
    @StateObject private var model: HeartRateModel
    @Environment(\.dismiss) private var dismiss

    init(profile: Profile, onChanged: @escaping () -> Void) {
        _model = StateObject(wrappedValue: HeartRateModel(profile: profile, onChanged: onChanged))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(HeartRateSheets.subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                if let device = model.device {
                    pairedSections(device)
                } else {
                    Section { Text(HeartRateSheets.unpairedNote).font(.footnote) }
                    Section {
                        Button(HeartRateSheets.findMyWatch) { model.findMyWatch() }
                            .accessibilityIdentifier("findMyWatch")
                    }
                }
            }
            .sheet(isPresented: $model.askDetails) {
                HeartRateDetailsSheet(profile: model.profile, onSaved: { model.detailsChanged() })
            }
            .navigationTitle(HeartRateSheets.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $model.scanning, onDismiss: { model.cancelScan() }) {
            HeartRateScanSheet(model: model)
        }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .accessibilityIdentifier("heartRateSheet")
    }

    @ViewBuilder private func pairedSections(_ device: HeartRateDevice) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name).font(.headline)
                Text(model.statusText)
                    .font(.footnote)
                    .foregroundStyle(model.isReading ? Color.green : Color.secondary)
                    .accessibilityIdentifier("heartRateStatus")
            }
            .accessibilityElement(children: .combine)
        }
        Section {
            Button { model.askDetails = true } label: {
                row(HeartRateSheets.yourDetails, model.detailsSubtitle)
            }
            Button { model.findMyWatch() } label: {
                row(HeartRateSheets.findAnother, HeartRateSheets.findAnotherSubtitle)
            }
        }
        Section {
            Button(HeartRateSheets.forget, role: .destructive) { model.forget() }
        }
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.primary)
            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// A 12-second search for nearby heart-rate broadcasters. The rows update in place as matches
/// arrive and hold their order, so a tap lands on the device the finger was over.
struct HeartRateScanSheet: View {
    @ObservedObject var model: HeartRateModel

    var body: some View {
        NavigationStack {
            Form {
                if let step = model.blocked {
                    blockedSection(step)
                } else {
                    Section {
                        if model.found.isEmpty {
                            Text(HeartRateSheets.nothingYet).foregroundStyle(.secondary)
                        } else {
                            ForEach(model.found, id: \.address) { found in
                                Button { model.adopt(found) } label: { deviceRow(found) }
                                    .accessibilityLabel(HeartRateSheets.spoken(found))
                            }
                        }
                    }
                }
            }
            .navigationTitle(HeartRateSheets.scanTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.scanning = false } }
                ToolbarItem(placement: .primaryAction) {
                    if model.scanDone || model.blocked != nil {
                        Button(HeartRateSheets.scanAgain) { model.findMyWatch() }
                    }
                }
            }
        }
        .accessibilityIdentifier("heartRateScan")
    }

    private func deviceRow(_ found: FoundDevice) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(found.name).font(.headline).foregroundStyle(.primary)
            let label = HeartRateSheets.foundLabel(found)
            if !label.isEmpty { Text(label).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func blockedSection(_ step: FindWatchStep) -> some View {
        switch step {
        case .openSettings:
            Section {
                Text(HeartRateAccess.deniedTitle).font(.headline)
                Text(HeartRateAccess.deniedSubtitle).font(.footnote).foregroundStyle(.secondary)
                Button("OPEN SETTINGS") { model.openSettings() }
            }
        case .bluetoothOff:
            Section {
                Text(HeartRateAccess.bluetoothOffTitle).font(.headline)
                Text(HeartRateAccess.bluetoothOffSubtitle).font(.footnote).foregroundStyle(.secondary)
            }
        case .unsupported:
            Section { Text(HeartRateAccess.unsupportedToast) }
        case .scan, .askPermission, .wait:
            EmptyView()
        }
    }
}
