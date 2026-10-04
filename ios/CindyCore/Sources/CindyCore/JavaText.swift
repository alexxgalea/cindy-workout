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

    /// `String.format(Locale.US, "%.Nf", value)`.
    ///
    /// Java does not round the exact binary value, as C's `printf` does. `Formatter` takes the
    /// *shortest* decimal digits that identify the double (the ones `Double.toString` shows) and
    /// rounds those half up, so 0.95 is "1.0" in Java (its digits are 95) and "0.9" in C (the double
    /// is 0.9499999999999999556), and 1.45 is "1.5" against C's "1.4". This is that rounding, step
    /// for step as `FormattedFloatingDecimal.applyPrecision` and `fillDecimal` do it.
    public static func fixed(_ value: Double, _ decimals: Int) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        let sign = value.sign == .minus ? "-" : ""
        var (digits, exp) = shortestDigits(abs(value))

        if digits.isEmpty {   // zero
            return sign + "0" + (decimals > 0 ? "." + String(repeating: "0", count: decimals) : "")
        }

        // applyPrecision: round half up at `decExp + decimals` digits.
        let prec = exp + decimals
        if prec >= digits.count || prec < 0 {
            // No rounding necessary: every digit is within the precision, or none is.
        } else if prec == 0 {
            // The precision excludes every significant digit: the result is 0 or one unit of the last place.
            if digits[0] >= 5 {
                digits = [1] + Array(repeating: 0, count: digits.count - 1)
                exp += 1
            } else {
                digits = Array(repeating: 0, count: digits.count)
            }
        } else if digits[prec] >= 5 {
            var i = prec - 1
            var q = digits[i]
            if q == 9 {
                while q == 9 && i > 0 { i -= 1; q = digits[i] }
                if q == 9 {
                    // Carry out of the top: a one and zeros, one place up.
                    digits = [1] + Array(repeating: 0, count: digits.count - 1)
                    exp += 1
                    return layout(sign, digits, exp, decimals)
                }
            }
            digits[i] = q + 1
            for j in (i + 1)..<digits.count { digits[j] = 0 }
        } else {
            for j in prec..<digits.count { digits[j] = 0 }
        }
        return layout(sign, digits, exp, decimals)
    }

    /// The digits of `0.d1d2d3… × 10^exp`, written with `decimals` places after the point.
    private static func layout(_ sign: String, _ digits: [Int], _ exp: Int, _ decimals: Int) -> String {
        func digit(_ i: Int) -> Character {
            i >= 0 && i < digits.count ? Character(String(digits[i])) : "0"
        }
        var whole = ""
        if exp > 0 { for i in 0..<exp { whole.append(digit(i)) } } else { whole = "0" }
        var fraction = ""
        for i in 0..<decimals { fraction.append(digit(exp + i)) }
        return sign + whole + (decimals > 0 ? "." + fraction : "")
    }

    /// The shortest digits that identify `value` and where the point goes: `value = 0.d1d2… × 10^exp`.
    /// Empty digits for zero. Taken from Swift's `description`, which is the shortest round-trip form.
    private static func shortestDigits(_ value: Double) -> ([Int], Int) {
        if value == 0 { return ([], 0) }
        let text = value.description          // "123.456", "1e-05", "1.2345e+20"
        let parts = text.split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = String(parts[0])
        var exp10 = parts.count > 1 ? Int(parts[1])! : 0
        let pieces = mantissa.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let whole = pieces[0]
        let fraction = pieces.count > 1 ? pieces[1] : ""
        var digits = (whole + fraction).map { Int(String($0))! }
        exp10 += whole.count
        while digits.first == 0 { digits.removeFirst(); exp10 -= 1 }
        while digits.last == 0 { digits.removeLast() }
        return (digits, exp10)
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
