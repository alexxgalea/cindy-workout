import Foundation

extension Exercise {
    /// The name a record is written with: the Kotlin enum constant's, because the line format is
    /// shared byte for byte.
    public var name: String {
        switch self {
        case .pullup: return "PULLUP"
        case .pushup: return "PUSHUP"
        case .squat: return "SQUAT"
        }
    }

    /// The movement a record names, or `nil` for one this build does not know.
    public init?(name: String) {
        guard let found = Exercise.allCases.first(where: { $0.name == name }) else { return nil }
        self = found
    }
}

/// One movement block of a round: how long it took on the clock, and what it scored.
public struct SetSplit: Equatable, Sendable {
    public let movement: Exercise
    public let ms: Int64
    public let reps: Int
    public let manualReps: Int

    public init(_ movement: Exercise, _ ms: Int64, _ reps: Int, _ manualReps: Int) {
        self.movement = movement
        self.ms = ms
        self.reps = reps
        self.manualReps = manualReps
    }

    /// Reached its target rather than being skipped.
    public var complete: Bool { reps >= movement.target }

    /// Complete, and every rep in it seen by the camera: a time the app can stand behind.
    public var measured: Bool { complete && manualReps == 0 }
}

/// Times each set on the workout clock, pauses excluded, and unwinds across an undo.
///
/// A set runs from the end of the one before to the end of its own, so it includes getting into
/// position — as a round split does.
public final class SplitBook {
    private var done: [SetSplit] = []
    private var starts: [Int64] = []
    private var manualStarts: [Int] = []
    private var setStartMs: Int64 = 0
    private var manualAtStart = 0

    public init() {}

    public var sets: [SetSplit] { done }

    public func start(atMs: Int64 = 0) {
        done.removeAll(); starts.removeAll(); manualStarts.removeAll()
        setStartMs = atMs
        manualAtStart = 0
    }

    public func movementDone(_ movement: Exercise, atMs: Int64, reps: Int, manualTotal: Int) {
        starts.append(setStartMs)
        manualStarts.append(manualAtStart)
        done.append(SetSplit(movement, max(atMs - setStartMs, 0), reps,
                             max(manualTotal - manualAtStart, 0)))
        setStartMs = atMs
        manualAtStart = manualTotal
    }

    /// An undo stepped back into the previous movement: reopen its set from where it began.
    public func stepBack() {
        guard !done.isEmpty else { return }
        done.removeLast()
        setStartMs = starts.removeLast()
        manualAtStart = manualStarts.removeLast()
    }
}
