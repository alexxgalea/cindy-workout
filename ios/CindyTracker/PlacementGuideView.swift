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

/// The demonstrator: what the start position of the movement the athlete cannot start is, in the
/// movement's own words. Shown once the movement has stayed un-startable for a moment, so a gate
/// that flickers between reps never brings it up.
struct CoachCard: View {
    let exercise: Exercise

    var body: some View {
        VStack(spacing: 4) {
            Text(exercise.label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accent)
            Text(exercise.startCue)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("coachCard")
    }
}
