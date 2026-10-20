import SwiftUI
import CindyCore

/// The three facts about where the phone goes, shown before the first setup check.
///
/// Said before the camera is on, because placement is the one thing the athlete has to get right and
/// the one thing the app cannot fix for them. "Don't show this again" is kept, so it is a courtesy
/// to a newcomer and not a toll on everyone else.
struct PlacementGuideView: View {
    @Binding var dontShowAgain: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where to put the phone")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            ForEach(PlacementFacts.all, id: \.text) { fact in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: fact.symbol)
                        .foregroundStyle(fact.warning ? Color.warn : Color.dim)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(fact.text)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            Toggle("Don't show this again", isOn: $dontShowAgain)
                .font(.system(size: 14))
                .tint(.accent)
                .foregroundStyle(Color.dim)
            Button("CONTINUE", action: onContinue)
                .buttonStyle(PrimaryButton())
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .presentationDetents([.medium])
        .accessibilityIdentifier("placementGuide")
    }
}
