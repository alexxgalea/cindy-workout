import Foundation

/// The line format a session's `RepMark`s are saved as.
///
/// A header line, then one line per mark, oldest first:
/// ```
/// reps1
/// <clockMs>,<MOVEMENT_NAME>,<c|m>        (zero or more)
/// ```
/// The format is the part worth testing anywhere, and `RepTimesStore` is only the thin
/// file-handling layer around it. It is Android's, byte for byte.
public enum RepTimes {

    private static let header = "reps1"
    private static let manual = "m"
    private static let camera = "c"

    public static func encode(_ marks: [RepMark]) -> String {
        var lines = [header]
        for mark in marks {
            lines.append("\(mark.clockMs),\(mark.movement.name),\(mark.manual ? manual : camera)")
        }
        return lines.joined(separator: "\n")
    }

    /// `nil` for nil, blank, or a header line that is missing or not this format's own. Any other
    /// malformed line is skipped rather than failing the whole file — one bad line is not a reason
    /// to throw an otherwise-good session's marks away.
    public static func decode(_ raw: String?) -> [RepMark]? {
        guard let raw, !Records.isBlank(raw) else { return nil }
        let lines = Records.lines(raw)
        guard lines.first == header else { return nil }

        var marks: [RepMark] = []
        for line in lines.dropFirst() {
            let f = Records.fields(line, ",")
            guard f.count == 3, let clockMs = Records.toLong(f[0]),
                  let movement = Exercise(name: f[1]) else { continue }
            switch f[2] {
            case manual: marks.append(RepMark(clockMs, movement, manual: true))
            case camera: marks.append(RepMark(clockMs, movement, manual: false))
            default: continue
            }
        }
        return marks
    }

    /// Whether `marks` are honestly `attempt`'s: the same count as what it actually counted, in
    /// order, and never later than the clock it ran to.
    ///
    /// `Attempt.countedReps` nil means the record predates this file existing — nothing to
    /// validate against, so nothing can be valid. A mark count that disagrees with it is treated no
    /// more gently: a consumer must fall back to per-set data rather than draw a chart that implies
    /// precision this file does not have. The bound is `durationMs + 1_000` rather than
    /// `durationMs` exactly, because the last rep and the clock stopping are two separate reads a
    /// frame or two apart.
    public static func validFor(_ marks: [RepMark], _ attempt: Attempt) -> Bool {
        guard let counted = attempt.countedReps, marks.count == counted else { return false }
        for (i, mark) in marks.enumerated() {
            if mark.clockMs > attempt.durationMs + 1_000 { return false }
            if i > 0 && mark.clockMs < marks[i - 1].clockMs { return false }
        }
        return true
    }
}

/// Where one attempt's rep marks live: a file of its own, beside the heart-rate trace's and for
/// the same reason — `RecordStore` rewrites its whole string on every save, and a line per rep in
/// every attempt would make each new score cost rewriting every rep that came before it.
public final class RepTimesStore {

    private let dir: URL

    /// `directory` is where the files live. The app passes a folder in Application Support; a
    /// test passes a temporary one. The default is Android's `filesDir/rep_times`, on iOS.
    public init(directory: URL? = nil) {
        if let directory {
            dir = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
            dir = support.appendingPathComponent("rep_times", isDirectory: true)
        }
    }

    private func file(_ atMillis: Int64) -> URL { dir.appendingPathComponent("\(atMillis).reps") }

    /// Writes `marks` for the attempt saved at `atMillis`.
    ///
    /// Written through a temporary file that is renamed into place (`.atomic` does exactly that),
    /// so a process killed mid-write cannot leave a half-written file where `load` would find it.
    public func save(atMillis: Int64, _ marks: [RepMark]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(RepTimes.encode(marks).utf8).write(to: file(atMillis), options: .atomic)
    }

    /// `nil` when there is no file for `atMillis`, or when what is there does not decode.
    public func load(atMillis: Int64) -> [RepMark]? {
        guard let data = try? Data(contentsOf: file(atMillis)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return RepTimes.decode(text)
    }

    /// Every saved file, gone — the companion to the heart-rate store's `clear`.
    public func clear() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasSuffix(".reps") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
