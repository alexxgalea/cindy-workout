import Foundation

/// The low-light models a scenario can ask for, ported from `run_batch.py`'s `dim`.
///
/// `uncompensated` is `out = frame * gain`, which is deterministic and the same here as there.
/// `iso` adds sensor noise, and the noise is drawn from a seeded generator of this tool's own, so
/// it has the same strength and the same seed discipline as numpy's but is not the same noise: a
/// clip under `iso` is a statistical match for the Python run, not a pixel match.
public enum LightModel {

    /// Read noise of a phone sensor at base gain, in 8-bit counts.
    public static let readNoise = 2.0
    /// Ceiling on how far a camera will push its own gain to hold the brightness up.
    public static let isoCap = 12.0

    /// Dims a frame held as packed 4-byte pixels (BGRA or RGBA) in place. The fourth byte of each
    /// pixel is alpha and is left alone.
    public static func apply(_ light: Light, to pixels: UnsafeMutableBufferPointer<UInt8>,
                             noise: inout SeededNormal) {
        let gain = light.gain ?? 1.0
        let iso = (light.model ?? "uncompensated") == "iso"
        let boost = iso ? min(1.0 / max(gain, 1e-6), isoCap) : 1.0
        for i in 0..<pixels.count where i % 4 != 3 {
            var value = Double(pixels[i]) * gain * boost
            if iso { value += noise.next() * readNoise * boost }
            pixels[i] = UInt8(min(max(value, 0), 255))
        }
    }
}

/// A seeded source of normally distributed numbers (SplitMix64, then Box–Muller), so a fixture
/// that adds noise passes and fails for the same reasons every time it is run.
public struct SeededNormal {
    private var state: UInt64

    public init(seed: UInt64 = 7) { state = seed }

    private mutating func nextUniform() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        // 53 random bits, never exactly 0, so the logarithm below is finite.
        return (Double(z >> 11) + 0.5) / 9_007_199_254_740_992.0
    }

    public mutating func next() -> Double {
        let u1 = nextUniform(), u2 = nextUniform()
        return (-2.0 * log(u1)).squareRoot() * cos(2.0 * Double.pi * u2)
    }
}
