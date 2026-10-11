import Foundation

/// The slice of Android's `org.json.JSONObject` the Strava code reads, with the same answers.
///
/// Strava's replies are decoded with `JSONSerialization`, but the questions asked of them are
/// Android's: a missing key and a `null` are different things to `has` and `isNull`, `getString`
/// turns any value into text, `getLong` turns a number or a numeric string into a whole one, and
/// the ones that cannot throw `JsonError` (Android's `JSONException`), which the callers turn into
/// "worth retrying".
///
/// Where Android's parser is more forgiving than this one (single quotes, text after the closing
/// brace) a reply that Android would read is an error here. Strava sends strict JSON, so no real
/// reply tells the two apart.
struct JsonObject {

    /// Android's `JSONException`.
    struct JsonError: Error, Equatable {
        let message: String
    }

    private let values: [String: Any]

    /// Parses `text`, which must be one JSON object.
    init(parsing text: String) throws {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } catch {
            throw JsonError(message: "Not valid JSON")
        }
        guard let object = parsed as? [String: Any] else {
            throw JsonError(message: "Value is not a JSON object")
        }
        values = object
    }

    private init(values: [String: Any]) {
        self.values = values
    }

    func has(_ name: String) -> Bool { values[name] != nil }

    /// True for a missing key and for a `null`, as Android's `isNull` is.
    func isNull(_ name: String) -> Bool {
        guard let value = values[name] else { return true }
        return value is NSNull
    }

    /// Android's `getString`: the value as text, whatever it is. A `null` is the text "null".
    func getString(_ name: String) throws -> String {
        guard let value = values[name] else { throw JsonError(message: "No value for \(name)") }
        return Self.text(of: value)
    }

    /// Android's `optString(name, fallback)`: the same coercion, or `fallback` when the key is absent.
    func optString(_ name: String, _ fallback: String = "") -> String {
        values[name].map(Self.text(of:)) ?? fallback
    }

    /// Android's `getLong`: a number truncated towards zero (saturating at the ends), or a string
    /// that reads as one. A boolean, a `null`, an object and an array are not.
    func getLong(_ name: String) throws -> Int64 {
        guard let value = values[name] else { throw JsonError(message: "No value for \(name)") }
        if let number = value as? NSNumber, !Self.isBoolean(number) {
            if Self.isFloat(number) { return Self.saturatingLong(number.doubleValue) }
            return number.int64Value
        }
        if let string = value as? String, let double = Double(string.trimmingCharacters(in: .whitespaces)) {
            return Self.saturatingLong(double)
        }
        throw JsonError(message: "Value for \(name) cannot be converted to long")
    }

    /// The nested object under `name`, or nil when it is absent, `null`, or not an object.
    func optJSONObject(_ name: String) -> JsonObject? {
        (values[name] as? [String: Any]).map(JsonObject.init(values:))
    }

    // ---- Android's coercions --------------------------------------------------------------

    private static func isBoolean(_ number: NSNumber) -> Bool { String(cString: number.objCType) == "c" }

    private static func isFloat(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return type == "d" || type == "f"
    }

    /// Java's `(long) double`: towards zero, saturating, and NaN is 0.
    private static func saturatingLong(_ value: Double) -> Int64 {
        if value.isNaN { return 0 }
        if value >= 9_223_372_036_854_775_807.0 { return Int64.max }
        if value <= -9_223_372_036_854_775_808.0 { return Int64.min }
        return Int64(value)
    }

    /// `String.valueOf(value)` for what a JSON reader produces. A number written as a double is
    /// shown by Swift's shortest form, which is not always Java's `Double.toString`; only a
    /// malformed reply puts a number where Strava's text is read.
    private static func text(of value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case is NSNull:
            return "null"
        case let number as NSNumber:
            if isBoolean(number) { return number.boolValue ? "true" : "false" }
            if isFloat(number) { return "\(number.doubleValue)" }
            return "\(number.int64Value)"
        default:
            // An array or an object: its JSON text.
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
            else { return "\(value)" }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
