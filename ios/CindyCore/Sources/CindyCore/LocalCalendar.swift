import Foundation

/// The days of the week as ISO numbers them, Monday 1 to Sunday 7, as `java.time.DayOfWeek` does.
///
/// Which day a week starts on is the locale's to say, and it is always passed in. Nothing here asks
/// Foundation: its locale data differs between a Mac, a phone and a Linux container, and a streak
/// that depends on it would count differently in each.
public enum DayOfWeek: Int, CaseIterable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var value: Int { rawValue }
}

/// A calendar date with no time and no zone, as `java.time.LocalDate`.
///
/// The arithmetic is a day count from 1970-01-01 (Howard Hinnant's civil-date algorithms), so it is
/// the proleptic Gregorian calendar on every platform and needs no `Calendar`.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        precondition((1...12).contains(month), "month \(month)")
        precondition((1...YearMonth.lengthOfMonth(year, month)).contains(day), "day \(day) of \(year)-\(month)")
        self.year = year
        self.month = month
        self.day = day
    }

    /// An ISO date, "2026-09-09", or nil when it is not one.
    public init?(parse iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...YearMonth.lengthOfMonth(y, m)).contains(d) else { return nil }
        self.init(y, m, d)
    }

    public init(epochDay: Int) {
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    /// Days since 1970-01-01.
    public var epochDay: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public var dayOfWeek: DayOfWeek {
        // 1970-01-01 was a Thursday.
        DayOfWeek(rawValue: Self.floorMod(epochDay + 3, 7) + 1)!
    }

    public var yearMonth: YearMonth { YearMonth(year, month) }

    public func plusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay + n) }
    public func minusDays(_ n: Int) -> LocalDate { plusDays(-n) }
    public func plusWeeks(_ n: Int) -> LocalDate { plusDays(7 * n) }
    public func minusWeeks(_ n: Int) -> LocalDate { plusDays(-7 * n) }

    /// A month on, or back, keeping the day of the month or, where that month is too short, its last
    /// day: 31 March less a month is 28 (or 29) February, as `java.time` does it.
    public func plusMonths(_ n: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + n
        let y = Self.floorDiv(index, 12), m = Self.floorMod(index, 12) + 1
        return LocalDate(y, m, min(day, YearMonth.lengthOfMonth(y, m)))
    }
    public func minusMonths(_ n: Int) -> LocalDate { plusMonths(-n) }
    public func plusYears(_ n: Int) -> LocalDate { plusMonths(12 * n) }
    public func minusYears(_ n: Int) -> LocalDate { plusMonths(-12 * n) }

    /// This day, or the latest one before it, that falls on `dayOfWeek`.
    public func previousOrSame(_ dayOfWeek: DayOfWeek) -> LocalDate {
        minusDays(Self.floorMod(self.dayOfWeek.value - dayOfWeek.value, 7))
    }

    public func isBefore(_ other: LocalDate) -> Bool { self < other }
    public func isAfter(_ other: LocalDate) -> Bool { self > other }

    public static func < (a: LocalDate, b: LocalDate) -> Bool { a.epochDay < b.epochDay }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
    static func floorMod(_ a: Int, _ b: Int) -> Int { a - floorDiv(a, b) * b }
}

/// A month of a year, as `java.time.YearMonth`.
public struct YearMonth: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(_ year: Int, _ month: Int) {
        precondition((1...12).contains(month), "month \(month)")
        self.year = year
        self.month = month
    }

    public init(of date: LocalDate) { self.init(date.year, date.month) }

    public var lengthOfMonth: Int { Self.lengthOfMonth(year, month) }

    public func atDay(_ day: Int) -> LocalDate { LocalDate(year, month, day) }

    public static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func lengthOfMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public static func < (a: YearMonth, b: YearMonth) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }
}

/// A time zone: what turns a moment into the athlete's local day and back.
///
/// Wraps Foundation's `TimeZone` for its rules, and keeps to `java.time`'s answer where a local time
/// does not map to one instant: in the hour a clock skips, the time is moved on by the length of the
/// gap; in the hour it repeats, the earlier of the two is taken.
public struct Zone: Equatable, Sendable {
    public let timeZone: TimeZone

    public init(_ identifier: String) {
        guard let tz = TimeZone(identifier: identifier) else { preconditionFailure("unknown zone \(identifier)") }
        timeZone = tz
    }

    public init(offsetSeconds: Int) {
        guard let tz = TimeZone(secondsFromGMT: offsetSeconds) else { preconditionFailure("offset \(offsetSeconds)") }
        timeZone = tz
    }

    public static let utc = Zone(offsetSeconds: 0)

    /// The offset from UTC, in seconds, at an instant.
    public func offsetSeconds(atEpochMs ms: Int64) -> Int {
        timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    /// The local day an instant falls on.
    public func localDate(epochMs ms: Int64) -> LocalDate {
        LocalDate(epochDay: Self.epochDay(epochMs: ms, offsetSeconds: offsetSeconds(atEpochMs: ms)))
    }

    /// The local time of day of an instant, in minutes since midnight.
    public func minuteOfDay(epochMs ms: Int64) -> Int {
        let local = Self.floorDiv(ms, 1000) + Int64(offsetSeconds(atEpochMs: ms))
        return Int(Self.floorMod(local, 86_400) / 60)
    }

    /// The instant a local date and time is, in this zone.
    public func epochMs(_ date: LocalDate, hour: Int = 0, minute: Int = 0) -> Int64 {
        let local = Int64(date.epochDay) * 86_400 + Int64(hour * 3_600 + minute * 60)
        let before = offsetSeconds(atEpochMs: (local - 86_400) * 1000)
        let after = offsetSeconds(atEpochMs: (local + 86_400) * 1000)
        if before == after { return (local - Int64(before)) * 1000 }
        // A change of offset is near. The time is valid under an offset when the offset really is
        // in force at the instant it implies.
        let early = (local - Int64(before)) * 1000
        let late = (local - Int64(after)) * 1000
        if offsetSeconds(atEpochMs: early) == before { return early }  // normal, or the repeated hour: the earlier
        if offsetSeconds(atEpochMs: late) == after { return late }
        return early                                                   // the skipped hour: later by the gap
    }

    static func epochDay(epochMs ms: Int64, offsetSeconds: Int) -> Int {
        Int(floorDiv(floorDiv(ms, 1000) + Int64(offsetSeconds), 86_400))
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 { a >= 0 ? a / b : -((-a + b - 1) / b) }
    static func floorMod(_ a: Int64, _ b: Int64) -> Int64 { a - floorDiv(a, b) * b }
}

/// An instant read on a zone's calendar, as `java.time.ZonedDateTime`, to the minute.
public struct ZonedDateTime: Equatable, Sendable {
    public let epochMs: Int64
    public let zone: Zone

    public init(epochMs: Int64, zone: Zone) {
        self.epochMs = epochMs
        self.zone = zone
    }

    /// A local date and time in `zone`, moved on by the gap or taken at the earlier offset where the
    /// clock skips or repeats it (see `Zone`).
    public static func of(_ date: LocalDate, hour: Int, minute: Int, zone: Zone) -> ZonedDateTime {
        ZonedDateTime(epochMs: zone.epochMs(date, hour: hour, minute: minute), zone: zone)
    }

    public var localDate: LocalDate { zone.localDate(epochMs: epochMs) }
    public var minuteOfDay: Int { zone.minuteOfDay(epochMs: epochMs) }
    public var hour: Int { minuteOfDay / 60 }
    public var minute: Int { minuteOfDay % 60 }
    public var offsetSeconds: Int { zone.offsetSeconds(atEpochMs: epochMs) }

    public func isAfter(_ other: ZonedDateTime) -> Bool { epochMs > other.epochMs }
}
