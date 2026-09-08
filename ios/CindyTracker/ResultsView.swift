import SwiftUI
import CindyCore

/// What just happened: score, rank, pace, and how the rounds actually went.
struct ResultsView: View {
    let attempt: Attempt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(attempt.scoreLabel)
                    .font(.system(size: 68, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("\(attempt.totalReps) reps in \(formatDuration(attempt.durationMs)) of clock")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dim)

                VStack(alignment: .leading, spacing: 8) {
                    Text(attempt.level.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.accent)
                    Text(attempt.level.blurb)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dim)
                    ProgressView(value: Double(Level.progress(attempt.rounds)))
                        .tint(Color.accent)
                    if let need = Level.roundsToNext(attempt.rounds),
                       let next = Level.next(after: attempt.level) {
                        Text("\(need) more round\(need == 1 ? "" : "s") to \(next.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dim)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                stat("Rounds completed", "\(attempt.rounds)")
                stat("Workout time", formatDuration(attempt.durationMs))
                if attempt.pausedMs > 0 {
                    // The clock stops when you pause; the day does not.
                    stat("Paused", formatDuration(attempt.pausedMs))
                    stat("Real time", formatDuration(attempt.realTimeMs))
                }
                if let avg = attempt.avgRoundMs { stat("Average round", formatDuration(avg)) }
                if let fastest = attempt.fastestRoundMs { stat("Fastest round", formatDuration(fastest)) }

                if !attempt.roundSplitsMs.isEmpty {
                    Text("ROUND SPLITS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.dim)
                        .padding(.top, 8)
                    splits
                    Text("Taller is slower." + (attempt.pausedMs > 0 ? " Splits exclude paused time." : ""))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dim)
                }

                Button("DONE") { dismiss() }
                    .buttonStyle(PrimaryButton())
                    .padding(.top, 16)
            }
            .padding(20)
        }
        .background(Color.appBackground)
    }

    private var splits: some View {
        let values = attempt.roundSplitsMs
        let peak = max(values.max() ?? 1, 1)
        let fastest = values.firstIndex(of: values.min() ?? 0)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i == fastest ? Color.accent : Color.white.opacity(0.28))
                    .frame(height: max(4, 130 * CGFloat(values[i]) / CGFloat(peak)))
            }
        }
        .frame(height: 130)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.dim)
            Spacer()
            Text(value).font(.system(size: 16, design: .monospaced)).foregroundStyle(.white)
        }
    }
}

/// Lets the finished attempt drive a `.sheet(item:)`.
extension Attempt: Identifiable {
    public var id: Int64 { atMillis }
}
