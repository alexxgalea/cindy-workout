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
