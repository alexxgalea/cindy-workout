/// `java.util.Random`, so a test that seeds one on the JVM sees the same numbers here.
///
/// The generator is a 48-bit linear congruential one, specified exactly in the Java documentation,
/// which is what makes this possible. Swift's own generators are not seedable and would give a
/// different stream.
public struct JavaRandom {
    private var seed: Int64

    private static let multiplier: Int64 = 0x5DEECE66D
    private static let addend: Int64 = 0xB
    private static let mask: Int64 = (1 << 48) - 1

    public init(seed: Int64) {
        self.seed = (seed ^ Self.multiplier) & Self.mask
    }

    private mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* Self.multiplier &+ Self.addend) & Self.mask
        return Int32(truncatingIfNeeded: seed >> (48 - bits))
    }

    /// `nextInt()`: any 32-bit value.
    public mutating func nextInt() -> Int32 { next(32) }

    /// `nextInt(bound)`: 0 up to but not including `bound`, drawn the way Java draws it.
    public mutating func nextInt(_ bound: Int32) -> Int32 {
        precondition(bound > 0, "bound must be positive")
        var r = next(31)
        let m = bound &- 1
        if bound & m == 0 {
            // A power of two takes the high bits.
            return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(r)) >> 31)
        }
        var u = r
        while true {
            r = u % bound
            // Java rejects a draw from the short bucket at the top of the range; the overflow in
            // `u - r + m` is how it notices.
            if u &- r &+ m >= 0 { return r }
            u = next(31)
        }
    }

    /// `nextFloat()`: 0 up to but not including 1, in steps of 2^-24.
    public mutating func nextFloat() -> Float {
        Float(next(24)) / Float(1 << 24)
    }
}
