import SwiftUI
import CindyCore

extension View {
    /// Where to stand, asked before the first setup check, as `MainActivity.showPlacementGuide` asks
    /// it: a Cindy sheet over the live preview, not a system sheet.
    ///
    /// Placement is the one thing the athlete has to get right and the one thing the app cannot fix
    /// for them, so it is said before the camera is on the athlete, once. START SETUP carries on to
    /// the check, and keeps "Don't show this again" if it was switched on. NOT NOW, a tap on the dim,
    /// a swipe down and the escape gesture all do nothing, and the switch is not kept: the guide is
    /// back at the next START. It is an overlay and not a cover, so the camera and the workout
    /// beneath it carry on.
    func placementGuide(isPresented: Binding<Bool>, onStart: @escaping () -> Void) -> some View {
        modifier(PlacementGuideModifier(isPresented: isPresented, onStart: onStart))
    }
}

private struct PlacementGuideModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onStart: () -> Void

    @State private var dontShowAgain = false
    /// Kept across launches. It is also evidence that the athlete has used the app before, which is
    /// why `Onboarding` owns the key.
    @AppStorage(Onboarding.keyPlacementSeen) private var placementSeen = false

    func body(content base: Content) -> some View {
        base.cindySheet(isPresented: $isPresented,
                        title: PlacementWords.title,
                        subtitle: PlacementWords.subtitle,
                        primary: SheetButton(title: PlacementWords.start) {
                            if dontShowAgain { placementSeen = true }
                            onStart()
                        },
                        secondary: SheetButton(title: PlacementWords.notNow) {},
                        onDismiss: { dontShowAgain = false },
                        content: { guide })
    }

    /// The diagram in a small glass card 200 high (`glass_card_small`: radius 18, padding 14, 12, 8),
    /// the three facts, and the switch.
    private var guide: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacementDiagram()
                .padding(.top, 14).padding(.horizontal, 12).padding(.bottom, 8)
                .frame(height: 200)
                .glassCard(radius: 18)
            PlacementFactRows()
            SheetToggle(PlacementWords.dontShowAgain, isOn: $dontShowAgain)
        }
    }
}
