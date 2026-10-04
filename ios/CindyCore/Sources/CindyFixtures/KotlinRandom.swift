/// `kotlin.random.Random(seed)`, so a Kotlin test that seeds one sees the same numbers here.
///
/// Kotlin's default seeded generator is the xorwow one (Marsaglia, 2003), which is specified by its
/// source and not by its name: five 32-bit words and an addend, seeded from an `Int` as
/// `(seed, seed >> 31, 0, 0, ~seed, (seed << 10) ^ (seed >>> 4 of the second word))` and warmed up
/// by 64 draws. The range draws (`nextInt(from, until)`, `nextLong(from, until)`) are Kotlin's own
/// rejection loops, not a modulo of one draw, so they are written out the same way.
public struct KotlinRandom {
    private var x: Int32, y: Int32, z: Int32 = 0, w: Int32 = 0, v: Int32, addend: Int32

    public init(seed: Int32) {
        let seed2 = seed >> 31
        x = seed
        y = seed2
        v = ~seed
        addend = (seed << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        for _ in 0..<64 { _ = nextInt() }
    }

    /// `nextInt()`: any 32-bit value.
    public mutating func nextInt() -> Int32 {
        var t = x
        t ^= Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362437
        return t &+ addend
    }

    /// `nextLong()`: any 64-bit value, high word first.
    public mutating func nextLong() -> Int64 {
        let high = Int64(nextInt()) << 32
        return high &+ Int64(nextInt())
    }

    private mutating func nextBits(_ count: Int) -> Int32 {
        let upper = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> UInt32(32 - count))
        return upper & (Int32(-count) >> 31)
    }

    private static func log2(_ value: Int32) -> Int { 31 - value.leadingZeroBitCount }

    /// `nextInt(from, until)`.
    public mutating func nextInt(_ from: Int32, _ until: Int32) -> Int32 {
        precondition(until > from, "empty range")
        let n = until &- from
        if n > 0 {
            if n & -n == n { return from &+ nextBits(Self.log2(n)) }
            var bits: Int32, r: Int32
            repeat {
                bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
                r = bits % n
            } while bits &- r &+ (n &- 1) < 0
            return from &+ r
        }
        // The range is wider than an Int can hold: draw whole words until one lands inside.
        while true {
            let r = nextInt()
            if r >= from && r < until { return r }
        }
    }

    /// `nextInt(until)`.
    public mutating func nextInt(_ until: Int32) -> Int32 { nextInt(0, until) }

    /// `nextLong(from, until)`.
    public mutating func nextLong(_ from: Int64, _ until: Int64) -> Int64 {
        precondition(until > from, "empty range")
        let n = until &- from
        precondition(n > 0, "ranges wider than a Long are not ported")
        if n & -n == n {
            let low = Int32(truncatingIfNeeded: n)
            let high = Int32(truncatingIfNeeded: n >> 32)
            let r: Int64
            if low != 0 {
                r = Int64(nextBits(Self.log2(low))) & 0xFFFF_FFFF
            } else if high == 1 {
                r = Int64(nextInt()) & 0xFFFF_FFFF
            } else {
                r = (Int64(nextBits(Self.log2(high))) << 32) &+ (Int64(nextInt()) & 0xFFFF_FFFF)
            }
            return from &+ r
        }
        var bits: Int64, r: Int64
        repeat {
            bits = Int64(bitPattern: UInt64(bitPattern: nextLong()) >> 1)
            r = bits % n
        } while bits &- r &+ (n &- 1) < 0
        return from &+ r
    }
}
