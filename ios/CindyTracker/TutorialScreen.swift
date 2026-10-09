import SwiftUI
import UIKit
import CindyCore

/// Five pages that show a new athlete around before the camera opens. `TutorialModel` decides the
/// pages, the buttons, the swipe and what ending does; this draws what it returns.
///
/// The same pages are taken again from Help. On a first run they end at the camera's permission
/// prompt (the camera screen asks once this has been dismissed); on a replay they go back to the
/// camera screen, closing the menu and the help above it.
struct TutorialScreen: View {
    let profile: Profile
    /// Whether this build has Strava at all. Nothing on the pages mentions it otherwise.
    let stravaAvailable: Bool
    /// Called once, when the pages end however they ended.
    let onExit: (TutorialExit) -> Void

    @State private var model: TutorialModel
    @State private var chooseMovements = false
    @State private var toast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let firstRun = FirstRun()

    init(replay: Bool, profile: Profile, stravaAvailable: Bool = false, onExit: @escaping (TutorialExit) -> Void) {
        self.profile = profile
        self.stravaAvailable = stravaAvailable
        self.onExit = onExit
        _model = State(initialValue: TutorialModel(replay: replay))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: finish) {
                    Text("SKIP").cindy(.eyebrow, colour: Palette.labelSecondary)
                        .frame(minWidth: 48, minHeight: 48)
                }
                .accessibilityLabel(TutorialModel.skipDescription)
                .accessibilityIdentifier("tutorialSkip")
            }
            .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.page(stravaAvailable: stravaAvailable).blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                // One page at a time: a new identity makes the scroll start from the top again.
                .id(model.index)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: model.forward ? 24 : -24)),
                                        removal: .opacity))
            }

            dots.padding(.vertical, 14)

            HStack(spacing: 12) {
                if let back = model.backLabel {
                    Button(back) { turn { model.back() } }
                        .buttonStyle(CindyGlassButtonStyle())
                        .accessibilityIdentifier("tutorialBack")
                }
                Button(model.nextLabel) { next() }
                    .buttonStyle(CindyPrimaryButtonStyle())
                    .accessibilityIdentifier("tutorialNext")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Palette.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastView }
        // A sideways swipe turns the page. It is judged when the finger lifts, and only a sideways
        // drag counts, so that a scroll up or down is never mistaken for one.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { drag in
                turn { model.swipe(dx: Float(drag.translation.width), dy: Float(drag.translation.height)) }
            }
        )
        // The two-finger Z, which is what "back" is to a screen reader: back a page, and out of
        // the first one ends the pages as skipping does.
        .accessibilityAction(.escape) {
            if model.systemBack() != nil { finish() }
        }
        .onChange(of: model.index) { _, _ in
            UIAccessibility.post(notification: .announcement, argument: model.announcement)
        }
        .sheet(isPresented: $chooseMovements) {
            MovementsSheet(profile: profile) { chosen in
                show(TutorialModel.choose(chosen, in: profile))
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("tutorial")
    }

    // MARK: moving

    private func turn(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.2)) { change() }
        }
    }

    private func next() {
        var exit: TutorialExit?
        turn { exit = model.next() }
        if exit != nil { finish() }
    }

    /// However the pages end, they do not come back by themselves, and the tour of the camera
    /// screen is next.
    private func finish() { onExit(model.finish(firstRun)) }

    private func show(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: the pieces

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<TutorialModel.pageCount, id: \.self) { i in
                Circle()
                    .fill(i == model.index ? Palette.label : Palette.labelQuaternary)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(model.dotsDescription)
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .cindy(.headline)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.black.opacity(0.8), in: Capsule())
                .padding(.bottom, 120)
                .accessibilityIdentifier("toast")
        }
    }

    @ViewBuilder private func blockView(_ block: TutorialBlock) -> some View {
        switch block {
        case .mark:
            MarkArcs().frame(width: 96, height: 96).padding(.top, 8).padding(.bottom, 24)
        case .title(let text):
            Text(text).cindy(.title).padding(.horizontal, 4).padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)
        case .body(let text):
            Text(text).cindy(.body, colour: Palette.labelBody).padding(.horizontal, 4).padding(.bottom, 14)
        case .footnote(let text):
            Text(text).cindy(.footnote).padding(.horizontal, 4).padding(.top, 2).padding(.bottom, 10)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(Palette.labelTertiary).frame(width: 5, height: 5).padding(.top, 9)
                Text(text).cindy(.body, colour: Palette.labelBody)
            }
            .padding(.horizontal, 4).padding(.bottom, 14)
        case .movements(let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    movementRow(row)
                    if i < rows.count - 1 { Divider().overlay(Palette.hairline) }
                }
            }
            .glassCard()
            .padding(.bottom, 12)
        case .callout(let text):
            Text(text).cindy(.callout, colour: Palette.labelBody)
                .padding(.horizontal, 20).padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
                .padding(.bottom, 10)
        case .chooseMovements:
            Button("CHOOSE MY MOVEMENTS") { chooseMovements = true }
                .buttonStyle(CindyGlassButtonStyle())
                .padding(.top, 6)
        case .placementDiagram:
            PlacementDiagram()
                .frame(height: 200)
                .padding(.top, 14).padding(.horizontal, 12).padding(.bottom, 8)
                .glassCard()
                .padding(.bottom, 14)
        case .placementFacts:
            PlacementFactRows().padding(.horizontal, 4)
        }
    }

    /// One movement and what the app does with it: counted in green, because green is the colour of
    /// what will count, or left for the athlete to tap in. Read as a single sentence.
    private func movementRow(_ row: TutorialMovement) -> some View {
        HStack {
            Text(row.label).cindy(.body, colour: Palette.labelBody)
            Spacer(minLength: 12)
            Text(row.status).cindy(.headline, colour: row.counted ? Palette.stateOk : Palette.labelSecondary)
        }
        .padding(.leading, 18).padding(.trailing, 16).padding(.vertical, 10)
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}
