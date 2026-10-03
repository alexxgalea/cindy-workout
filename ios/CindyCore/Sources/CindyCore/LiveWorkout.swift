import Foundation

/// Whether a workout is on the clock in this process, so a reminder cannot interrupt the very
/// session it was meant to prompt. A dead process has no workout, which is also the right answer.
public enum LiveWorkout {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var flag = false

    /// Read from a notification callback and written from the workout screen, on different
    /// threads, so every access takes the lock.
    public static var active: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); defer { lock.unlock() }; flag = newValue }
    }
}
