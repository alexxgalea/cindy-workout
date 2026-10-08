import Foundation

/// The line format a `HeartRateTrace` is saved as.
///
/// A trace is a header line, then zero or more pause lines, then zero or more sample lines:
/// ```
/// hr1|<startedAtMillis>
/// p|<atClockMs>|<lengthMs>        (zero or more)
/// <clockMs>,<bpm>                 (zero or more)
/// ```
/// Kept free of file handling on purpose, exactly like `Records`' own codec: this is the part worth
/// testing anywhere, and `HeartRateStore` is only the thin file layer around it. The bytes are
/// Android's, so a trace written by either app reads in the other.
public enum HeartRateTraces {

    private static let header = "hr1"
    private static let pause = "p"

    public static func encode(_ t: HeartRateTrace) -> String {
        var lines = ["\(header)|\(t.startedAtMillis)"]
        for p in t.pauses { lines.append("\(pause)|\(p.atClockMs)|\(p.lengthMs)") }
        for s in t.samples { lines.append("\(s.clockMs),\(s.bpm)") }
        return lines.joined(separator: "\n")
    }

    /// Nil for nil, blank, or a header line that is missing or not this format's own. Any other
    /// malformed line is skipped rather than failing the whole trace: a corrupt sample in the
    /// middle of a thousand-line file is not a reason to throw the other nine hundred away.
    public static func decode(_ raw: String?) -> HeartRateTrace? {
        guard let raw, !Records.isBlank(raw) else { return nil }
        let lines = Records.lines(raw)
        guard let first = lines.first else { return nil }
        let head = Records.fields(first, "|")
        guard head.count == 2, head[0] == header, let startedAtMillis = Records.toLong(head[1]) else { return nil }

        var pauses: [HeartRatePause] = []
        var samples: [HeartRateSample] = []
        for line in lines.dropFirst() {
            if line.unicodeScalars.starts(with: "\(pause)|".unicodeScalars) {
                let p = Records.fields(line, "|")
                if p.count == 3, let at = Records.toLong(p[1]), let length = Records.toLong(p[2]) {
                    pauses.append(HeartRatePause(atClockMs: at, lengthMs: length))
                }
            } else {
                let s = Records.fields(line, ",")
                if s.count == 2, let clock = Records.toLong(s[0]), let bpm = Records.toInt(s[1]) {
                    samples.append(HeartRateSample(clock, bpm))
                }
            }
        }
        return HeartRateTrace(startedAtMillis: startedAtMillis, samples: samples, pauses: pauses)
    }
}

/// Where one attempt's heart-rate trace lives: a file of its own, not a field on `Attempt`.
///
/// About a sample a second for twenty minutes is well over a thousand readings, and `RecordStore`
/// rewrites its whole string on every save, so a trace that size in every attempt would make each
/// new score cost writing out every score before it again. `atMillis` is the only join between a
/// record and its trace, exactly as it already is the join the results screen uses to find the
/// attempt it is showing.
public final class HeartRateStore {

    private let dir: URL

    /// `directory` is where the files live. The app passes a folder in Application Support; a test
    /// passes a temporary one. The default is Android's `filesDir/heart_rate`, on iOS.
    public init(directory: URL? = nil) {
        if let directory {
            dir = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
            dir = support.appendingPathComponent("heart_rate", isDirectory: true)
        }
    }

    private func file(_ atMillis: Int64) -> URL { dir.appendingPathComponent("\(atMillis).hr") }

    /// Writes `trace` for the attempt saved at `atMillis`, through a temporary file renamed into
    /// place (`.atomic`), so a process killed mid-write cannot leave a half-written trace where
    /// `load` would find it.
    public func save(atMillis: Int64, _ trace: HeartRateTrace) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(HeartRateTraces.encode(trace).utf8).write(to: file(atMillis), options: .atomic)
    }

    /// Nil when there is no file for `atMillis`, or when what is there does not decode.
    public func load(atMillis: Int64) -> HeartRateTrace? {
        guard let data = try? Data(contentsOf: file(atMillis)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return HeartRateTraces.decode(text)
    }

    /// Every saved trace, gone: the companion to `RecordStore`'s clear.
    public func clear() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasSuffix(".hr") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
