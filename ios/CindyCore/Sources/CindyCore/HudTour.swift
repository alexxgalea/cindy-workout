import Foundation

/// What the tour says about each control on the camera screen, in the order it says it.
///
/// The words and the order are the whole of it here; which view each `Target` is, and the spotlight
/// that is cut around it, belong to the screen (P14). A control that is hidden when the tour starts
/// is left out by the spotlight, so this list is the whole tour and never the tour as it happens to
/// run. Port of `HudTour.kt`.
public enum HudTour {

    /// The controls of the camera screen the tour can point at, named as `ActivityMainBinding` names them.
    public enum Target: String, CaseIterable, Sendable {
        case start = "btnStart"
        case status = "statusRow"
        case reps = "repBlock"
        case skip = "btnSkipExercise"
        case record = "btnRec"
        case menu = "btnMenu"
        case flip = "btnFlip"
    }

    public struct Step: Equatable, Sendable {
        public let target: Target
        public let title: String
        public let body: String

        init(_ target: Target, _ title: String, _ body: String) {
            self.target = target
            self.title = title
            self.body = body
        }
    }

    public static let steps: [Step] = [
        Step(.start, "Start", "Runs the setup check, then the 20-minute clock. Tap again to pause."),
        Step(.status, "What Cindy sees", "A green dot means the next rep will count. When it won't, this line says why."),
        Step(.reps, "Your reps", "Reps against the target. −1 and +1 either side fix a miscount."),
        Step(.skip, "Skip", "Moves on to the next movement."),
        Step(.record, "Record", "Films the workout with the count burned in, to your phone."),
        Step(.menu, "Menu", "Your movements, voice, music, progress and help — set them between workouts."),
        Step(.flip, "Flip", "Switches between the back and the front camera.")
    ]
}
