import SwiftUI
import UIKit
import CindyCore

/// What this build can describe. Heart rate (P15), filming (P16), music (P17), the daily reminder
/// (P18) and Strava (P20) join as their phases land, and Help starts describing each the moment it
/// is switched on; until then it says nothing of it.
enum HelpContent {
    static let features: HelpFeatures = []

    static var versionName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var versionCode: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// The text of a licence the app ships, or nil if the file cannot be read.
    static func licenceText(_ licence: Licences.Licence) -> String? {
        guard let url = Bundle.main.url(forResource: licence.resource, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// What Cindy is, and what this app is doing while you do it. `HelpBuilder` writes every section;
/// this lays them out.
struct HelpScreen: View {
    let profile: Profile
    /// Called when the pages taken again from here end: the menu and this screen close, and the tour
    /// of the camera screen follows.
    let onReturnToCamera: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var page: HelpPage
    @State private var replaying = false
    @State private var licence: ShownLicence?
    @State private var toast: String?

    private struct ShownLicence: Identifiable {
        let licence: Licences.Licence
        var id: String { licence.resource }
    }

    init(profile: Profile, onReturnToCamera: @escaping () -> Void) {
        self.profile = profile
        self.onReturnToCamera = onReturnToCamera
        _page = State(initialValue: HelpBuilder.build(HelpInput(
            attempts: RecordStore().all(), features: HelpContent.features,
            versionName: HelpContent.versionName, versionCode: HelpContent.versionCode)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cindy").cindy(.title).padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    Text("The benchmark workout, and how this app scores it")
                        .cindy(.body).padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 16)
                    ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button { open(AppLinks.crossfitCindy) } label: {
                    HStack(spacing: 8) {
                        Text(HelpBuilder.crossfitButton)
                        // An arrow, because this one leaves the app.
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.labelSecondary)
                    }
                }
                .buttonStyle(CindyGlassButtonStyle())
                .accessibilityLabel(HelpBuilder.crossfitButtonDescription)
                Button("DONE") { dismiss() }
                    .buttonStyle(CindyPrimaryButtonStyle())
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Palette.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastView }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $replaying) {
            TutorialScreen(replay: true, profile: profile) { exit in
                replaying = false
                if exit == .returnToCamera { onReturnToCamera() }
            }
        }
        .sheet(item: $licence) { shown in
            LicenceSheet(licence: shown.licence)
        }
    }

    private func perform(_ action: HelpAction) {
        switch action {
        case .takeTour: replaying = true
        case .openLink(let url): open(url)
        case .showLicence(let licence): self.licence = ShownLicence(licence: licence)
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        openURL(url) { accepted in
            if !accepted { show("No browser to open \(address)") }
        }
    }

    private func show(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast == text { toast = nil }
        }
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast).cindy(.headline)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.black.opacity(0.8), in: Capsule())
                .padding(.bottom, 90)
        }
    }

    // MARK: blocks

    @ViewBuilder private func blockView(_ block: HelpBlock) -> some View {
        switch block {
        case .row(let row):
            insetGroup([row])
        case .rows(let rows):
            insetGroup(rows).padding(.top, 4)
        case .heading(let text):
            Text(text).cindy(.eyebrow).padding(.leading, 4).padding(.top, 24).padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(text).cindy(.body, colour: Palette.labelBody).padding(.horizontal, 4).padding(.bottom, 10)
        case .quiet(let text):
            Text(text).cindy(.footnote).padding(.horizontal, 4).padding(.top, 2).padding(.bottom, 10)
        case .quote(let text):
            quote(text)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(Palette.labelTertiary).frame(width: 5, height: 5).padding(.top, 9)
                            .accessibilityHidden(true)
                        Text(item).cindy(.body, colour: Palette.labelBody)
                    }
                    .padding(.horizontal, 4).padding(.bottom, 12)
                }
            }
        case .workoutCard(let title, let scheme, let note):
            workoutCard(title, scheme, note)
        case .scaledCard(let title, let lines, let note):
            VStack(alignment: .leading, spacing: 0) {
                Text(title).cindy(.title2)
                Text(lines).cindy(.body, colour: Palette.labelBody).padding(.top, 8)
                Text(note).cindy(.footnote).padding(.top, 12)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .padding(.bottom, 10)
        case .tiers(let tiers):
            VStack(spacing: 0) {
                ForEach(Array(tiers.enumerated()), id: \.offset) { i, tier in
                    tierRow(tier)
                    if i < tiers.count - 1 { Divider().overlay(Palette.hairline) }
                }
            }
            .glassCard()
            .padding(.bottom, 10)
        case .diagram:
            PlacementDiagram()
                .frame(height: 210)
                .padding(.top, 14).padding(.horizontal, 12).padding(.bottom, 8)
                .glassCard()
                .padding(.top, 4).padding(.bottom, 14)
        }
    }

    private func insetGroup(_ rows: [HelpRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Button { perform(row.action) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).cindy(.headline)
                            Text(row.subtitle).cindy(.footnote)
                        }
                        Spacer()
                        Image(systemName: isLink(row.action) ? "arrow.up.right" : "chevron.right")
                            .font(.system(size: 11)).foregroundStyle(Palette.labelTertiary)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.spoken)
                .accessibilityAddTraits(.isButton)
                if i < rows.count - 1 { Divider().overlay(Palette.hairline) }
            }
        }
        .glassCard()
    }

    private func isLink(_ action: HelpAction) -> Bool {
        if case .openLink = action { return true }
        return false
    }

    /// CrossFit's words, marked as theirs by attribution rather than by a coloured bar: the credit
    /// underneath says whose it is, which is both the more useful fact and the one the screen is
    /// obliged to carry.
    private func quote(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\u{201C}\(text)\u{201D}").cindy(.body, colour: Palette.labelBody).italic()
            Rectangle().fill(Palette.hairline).frame(height: Palette.hairlineWidth).padding(.top, 14)
            HStack(spacing: 7) {
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(Palette.labelTertiary)
                Text("CROSSFIT.COM").cindy(.eyebrow)
            }
            .padding(.top, 11)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.bottom, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quotation from crossfit.com: \(text)")
    }

    /// The rep scheme beside the mark whose proportions it is: the arcs are 270°, 180° and 90° of a
    /// circle, which is fifteen, ten and five. The pips repeat the arcs' own weights, so the mark on
    /// the launcher and the list in the card are visibly the same fact.
    private func workoutCard(_ title: String, _ scheme: [HelpScheme], _ note: String) -> some View {
        let weights = [Palette.label, Palette.labelSecondary, Palette.labelTertiary]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                MarkArcs().frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).cindy(.title2)
                    ForEach(Array(scheme.enumerated()), id: \.offset) { i, item in
                        HStack(spacing: 10) {
                            Circle().fill(weights[min(i, weights.count - 1)]).frame(width: 6, height: 6)
                            Text(item.count).cindy(.headline).frame(width: 22, alignment: .trailing)
                            Text(item.name).cindy(.body, colour: Palette.labelBody)
                        }
                        .padding(.top, i == 0 ? 12 : 7)
                    }
                }
            }
            Rectangle().fill(Palette.hairline).frame(height: Palette.hairlineWidth).padding(.top, 16)
            Text(note).cindy(.footnote).padding(.top, 12)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.bottom, 10)
    }

    /// One of CrossFit's score tiers, ticked when the athlete's best has reached it. The scaled
    /// tier is never ticked, and says so rather than being left ambiguously empty.
    private func tierRow(_ tier: HelpTier) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.name).cindy(.headline)
                Text(tier.detail).cindy(.footnote)
            }
            Spacer()
            if let reached = tier.reached {
                Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(reached ? Palette.stateOk : Palette.labelQuaternary)
            } else {
                Text(HelpTier.notScored).cindy(.eyebrow, colour: Palette.labelQuaternary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(tier.reached == true ? Palette.surfaceGlass : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.spoken)
    }
}

/// A licence's full text, in a sheet. The text is the licence's own, unedited.
private struct LicenceSheet: View {
    let licence: Licences.Licence
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(licence.name).cindy(.title2)
                    Text(HelpContent.licenceText(licence) ?? "The text of this licence could not be read.")
                        .cindy(.footnote)
                        .textSelection(.enabled)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("DONE") { dismiss() }
                .buttonStyle(CindyPrimaryButtonStyle())
                .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
