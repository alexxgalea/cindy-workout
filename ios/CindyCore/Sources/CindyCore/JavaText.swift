import Foundation

/// The few things `String.format(Locale.US, …)` and `kotlin.math` do that Swift's own do not.
///
/// They are spelled out here, once, so that a figure on the progress screen is the one the Android
/// build shows and not the nearest thing Foundation offers on whichever platform runs it.
public enum JavaText {

    /// `String.format(Locale.US, "%,d", n)`: groups of three digits, a comma between, a minus sign in front.
    public static func grouped(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    /// Kotlin's `Double.roundToInt()`: halves round up, towards positive infinity (so -2.5 is -2),
    /// and NaN is 0. Not `Double.rounded()`, which sends -2.5 to -3.
    public static func roundToInt(_ x: Double) -> Int {
        if x.isNaN { return 0 }
        if x >= Double(Int32.max) { return Int(Int32.max) }
        if x <= Double(Int32.min) { return Int(Int32.min) }
        let floor = x.rounded(.down)
        return Int(x - floor >= 0.5 ? floor + 1 : floor)
    }

    /// `Math.round(x)` for a `Double`: the same rule with a 64-bit result.
    public static func roundToLong(_ x: Double) -> Int64 {
        if x.isNaN { return 0 }
        if x >= Double(Int64.max) { return Int64.max }
        if x <= Double(Int64.min) { return Int64.min }
        let floor = x.rounded(.down)
        return Int64(x - floor >= 0.5 ? floor + 1 : floor)
    }

    /// Stable, as Kotlin's `sortedBy` is: equal keys stay in the order they came in.
    static func sortedStably<T, K: Comparable>(_ items: [T], by key: (T) -> K, descending: Bool = false) -> [T] {
        items.enumerated()
            .map { (offset: $0.offset, key: key($0.element), item: $0.element) }
            .sorted { a, b in
                if a.key != b.key { return descending ? a.key > b.key : a.key < b.key }
                return a.offset < b.offset
            }
            .map { $0.item }
    }
}

/// A day the way every screen writes one: "9 Sep" or "12 Mar 2026", in English whatever the phone
/// speaks (`DateTimeFormatter.ofPattern("d MMM", Locale.US)`).
public enum DateText {
    public static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "d MMM": "9 Sep".
    public static func short(_ date: LocalDate) -> String { "\(date.day) \(months[date.month - 1])" }

    /// "d MMM yyyy": "9 Sep 2026".
    public static func long(_ date: LocalDate) -> String { "\(short(date)) \(date.year)" }
}
