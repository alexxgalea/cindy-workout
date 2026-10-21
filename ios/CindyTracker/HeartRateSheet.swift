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

/// Everything heart rate (`chooseHeartRate`): pairing a watch, or, once one is paired, a live status line
/// and the age and sex the formula still needs.
///
/// One presented sheet whose panel follows the model: the main one, the scan (`openScanSheet`), "Your
/// details" (the panel the results page also opens, here a step of this sheet) and the step a blocked
/// scan stops at. CANCEL on the scan ends the sheet, as on Android, and so does every way out that is
/// not a button; the live connection and the scan end with it.
struct HeartRateSheet: View {
    @StateObject private var model: HeartRateModel
    @Environment(\.closeCindySheet) private var close

    init(profile: Profile, onChanged: @escaping () -> Void) {
        _model = StateObject(wrappedValue: HeartRateModel(profile: profile, onChanged: onChanged))
    }

    var body: some View {
        // One container, so swapping the panels is not this sheet appearing or leaving.
        ZStack {
            if let step = model.blocked, model.scanning {
                blocked(step)
            } else if model.scanning {
                scan
            } else if model.askDetails {
                HeartRateDetailsSheet(profile: model.profile, onSaved: { model.detailsChanged() },
                                      onFinished: { model.askDetails = false })
            } else if let device = model.device {
                paired(device)
            } else {
                unpaired
            }
        }
        .onChange(of: panel) { _, _ in SheetVoiceOver.panelChanged() }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
    }

    /// Which panel the sheet is showing, for telling a screen reader when it changes.
    private var panel: String {
        if model.blocked != nil, model.scanning { return "blocked" }
        if model.scanning { return "scan" }
        if model.askDetails { return "details" }
        return model.device == nil ? "unpaired" : "paired"
    }

    // MARK: the main panels

    private var unpaired: some View {
        CindyPanel(title: HeartRateSheets.title, subtitle: HeartRateSheets.subtitle,
                   primary: SheetButton(title: HeartRateSheets.findMyWatch) { model.findMyWatch() }
                       .keepingOpen { true },
                   secondary: SheetButton(title: SheetWords.cancel) {}) {
            SheetNote(HeartRateSheets.unpairedNote)
        }
    }

    private func paired(_ device: HeartRateDevice) -> some View {
        CindyPanel(title: HeartRateSheets.title, subtitle: HeartRateSheets.subtitle,
                   primary: SheetButton(title: SheetWords.done) {},
                   secondary: SheetButton(title: SheetWords.forget, tint: Palette.stateAlert) { model.forget() }) {
            VStack(alignment: .leading, spacing: 12) {
                InsetGroup([0], id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).cindy(.headline)
                        Text(model.statusText)
                            .cindy(.footnote, colour: model.isReading ? Palette.stateOk : Palette.labelSecondary)
                            .accessibilityIdentifier("heartRateStatus")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                InsetGroup(PairedRow.allCases, id: \.self) { row in
                    switch row {
                    case .details:
                        NavRow(title: HeartRateSheets.yourDetails, value: model.detailsSubtitle) { model.askDetails = true }
                    case .another:
                        NavRow(title: HeartRateSheets.findAnother, value: HeartRateSheets.findAnotherSubtitle) {
                            model.findMyWatch()
                        }
                    }
                }
            }
        }
    }

    private enum PairedRow: CaseIterable { case details, another }

    // MARK: the scan

    /// A 12-second search for nearby heart-rate broadcasters. The rows update in place as matches
    /// arrive and hold their order, so a tap lands on the device the finger was over.
    private var scan: some View {
        CindyPanel(title: HeartRateSheets.scanTitle,
                   primary: model.scanDone
                       ? SheetButton(title: HeartRateSheets.scanAgain) { model.findMyWatch() }.keepingOpen { true }
                       : SheetButton(title: SheetWords.cancel) { model.cancelScan() },
                   secondary: model.scanDone ? SheetButton(title: SheetWords.cancel) { model.cancelScan() } : nil) {
            InsetGroup(scanRows, id: \.id) { entry in
                switch entry {
                case .nothing:
                    Text(HeartRateSheets.nothingYet).cindy(.callout)
                        .padding(.leading, 18).padding(.trailing, 16).padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .device(let found):
                    NavRow(title: found.name, value: HeartRateSheets.foundLabel(found),
                           spoken: HeartRateSheets.spoken(found)) { model.adopt(found) }
                }
            }
        }
    }

    private enum ScanRow: Identifiable {
        case nothing, device(FoundDevice)

        var id: String {
            switch self {
            case .nothing: return "nothing"
            case .device(let found): return found.address
            }
        }
    }

    private var scanRows: [ScanRow] {
        model.found.isEmpty ? [.nothing] : model.found.map(ScanRow.device)
    }

    // MARK: a scan that cannot start

    @ViewBuilder private func blocked(_ step: FindWatchStep) -> some View {
        switch step {
        case .openSettings:
            CindyPanel(title: HeartRateAccess.deniedTitle, subtitle: HeartRateAccess.deniedSubtitle,
                       primary: SheetButton(title: SheetWords.openSettings) { model.openSettings() },
                       secondary: SheetButton(title: SheetWords.notNow) {})
        case .bluetoothOff:
            CindyPanel(title: HeartRateAccess.bluetoothOffTitle, subtitle: HeartRateAccess.bluetoothOffSubtitle,
                       primary: SheetButton(title: SheetWords.done) {})
        case .unsupported:
            CindyPanel(title: HeartRateSheets.title, subtitle: HeartRateAccess.unsupportedToast,
                       primary: SheetButton(title: SheetWords.done) {})
        case .scan, .askPermission, .wait:
            EmptyView()
        }
    }
}
