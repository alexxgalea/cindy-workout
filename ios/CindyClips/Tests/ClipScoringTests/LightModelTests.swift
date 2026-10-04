import XCTest
import ClipScoring

final class LightModelTests: XCTestCase {

    /// `count` pixels of one grey, opaque.
    private func grey(_ value: UInt8, pixels count: Int) -> [UInt8] {
        var out: [UInt8] = []
        for _ in 0..<count { out.append(contentsOf: [value, value, value, 255]) }
        return out
    }

    private func colourChannels(_ pixels: [UInt8]) -> [Double] {
        var out: [Double] = []
        for (i, byte) in pixels.enumerated() where i % 4 != 3 { out.append(Double(byte)) }
        return out
    }

    private func dimmed(_ pixels: [UInt8], _ light: Light, seed: UInt64 = 7) -> [UInt8] {
        var copy = pixels
        var noise = SeededNormal(seed: seed)
        copy.withUnsafeMutableBufferPointer { LightModel.apply(light, to: $0, noise: &noise) }
        return copy
    }

    /// out = frame * gain, truncated, with alpha left alone
    func testUncompensatedIsAGainAndAlphaIsUntouched() {
        let out = dimmed([200, 100, 51, 255,   10, 0, 255, 128], Light(gain: 0.5, model: "uncompensated"))
        XCTAssertEqual(out, [100, 50, 25, 255,   5, 0, 127, 128])
    }

    func testAGainOfOneChangesNothingAndTheModelDefaultsToUncompensated() {
        let pixels: [UInt8] = [1, 2, 3, 4, 250, 251, 252, 253]
        XCTAssertEqual(dimmed(pixels, Light(gain: 1.0, model: nil)), pixels)
        XCTAssertEqual(dimmed(pixels, Light(gain: nil, model: nil)), pixels)
    }

    func testBrighteningClipsAtTheTop() {
        XCTAssertEqual(dimmed([200, 255, 10, 7], Light(gain: 3, model: "uncompensated")), [255, 255, 30, 7])
    }

    /// iso raises the gain to hold the brightness (capped at 12x) and adds noise of 2 counts at that gain
    func testIsoHoldsTheBrightnessUpAndAddsNoise() {
        let out = dimmed(grey(100, pixels: 20000), Light(gain: 0.25, model: "iso"))   // boost 4x: 0.25 * 4 = 1, noise sigma 8
        let colour = colourChannels(out)
        let mean = colour.reduce(0, +) / Double(colour.count)
        let variance = colour.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(colour.count)
        XCTAssertEqual(mean, 99.5, accuracy: 0.5)                           // truncation takes half a count off
        XCTAssertEqual(variance.squareRoot(), 8, accuracy: 0.3)
        for (i, byte) in out.enumerated() where i % 4 == 3 { XCTAssertEqual(byte, 255) }
    }

    func testIsoGainIsCappedAtTwelve() {
        let out = dimmed(grey(10, pixels: 20000), Light(gain: 0.001, model: "iso"))   // 1/gain is 1000, capped to 12
        let colour = colourChannels(out)
        let mean = colour.reduce(0, +) / Double(colour.count)
        // 10 * 0.001 * 12 = 0.12 of signal; noise of sigma 24 clips at zero, so the mean sits well above it.
        XCTAssertGreaterThan(mean, 5)
        XCTAssertLessThan(mean, 14)
    }

    func testTheSameSeedMakesTheSameNoise() {
        let pixels = [UInt8](repeating: 128, count: 400)
        let light = Light(gain: 0.1, model: "iso")
        XCTAssertEqual(dimmed(pixels, light, seed: 7), dimmed(pixels, light, seed: 7))
        XCTAssertNotEqual(dimmed(pixels, light, seed: 7), dimmed(pixels, light, seed: 8))
    }

    func testTheNoiseIsNormal() {
        var noise = SeededNormal(seed: 7)
        let draws = (0..<200_000).map { _ in noise.next() }
        let mean = draws.reduce(0, +) / Double(draws.count)
        let variance = draws.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(draws.count)
        XCTAssertEqual(mean, 0, accuracy: 0.01)
        XCTAssertEqual(variance, 1, accuracy: 0.02)
        let within = Double(draws.filter { abs($0) < 1 }.count) / Double(draws.count)
        XCTAssertEqual(within, 0.6827, accuracy: 0.005)
        XCTAssertTrue(draws.allSatisfy { $0.isFinite })
    }
}
