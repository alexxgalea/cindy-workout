import Foundation

/// The largest centred square of a picture, in that picture's own pixels.
public struct Square: Equatable, Sendable {
    public let left: Int
    public let top: Int
    public let size: Int

    public init(_ left: Int, _ top: Int, _ size: Int) {
        self.left = left
        self.top = top
        self.size = size
    }
}

/// What it takes to stand a stored picture upright: turn it clockwise by `degrees`, then mirror it
/// left to right if `mirrored`. In that order, because that is the order a matrix applies them in.
public struct Upright: Hashable, Sendable {
    public let degrees: Int
    public let mirrored: Bool

    public init(_ degrees: Int, _ mirrored: Bool) {
        self.degrees = degrees
        self.mirrored = mirrored
    }
}

/// The parts of a name and a profile photo that are arithmetic rather than a platform: what to call
/// someone, which letters stand in for a face, and how to cut a picture down to a square.
///
/// Port of `Avatar.kt`. Strings are walked as Unicode scalars and counted in UTF-16 units, as the
/// Kotlin does, never as Swift `Character`s: a grapheme cluster would glue a combining mark to the
/// space before it, and `String ==` treats "é" and "e" with an accent as the same string, which a
/// rule about what a name is made of cannot afford.
public enum Avatar {

    /// The edge of the stored square, in pixels.
    ///
    /// Sharp at the biggest the photo is ever drawn (88 points is 264 px on a 3x screen and 352 on
    /// a 4x one) and small enough that the JPEG is tens of kilobytes, which matters because the file
    /// rides along in the athlete's backup.
    public static let sizePx = 320

    /// The longest name kept. A name here is a label in a row, not a biography.
    public static let maxName = 30

    /// A name as it is kept: trimmed, with every run of whitespace as a single space, cut to
    /// `maxName`, or nil when nothing is left.
    ///
    /// The cut never splits a surrogate pair, so a name does not end in half a character. It can
    /// still fall inside a longer sequence, an emoji with a skin tone or a letter with its accent,
    /// but the field stops typing at `maxName` itself, so only a name that arrived some other way
    /// gets that far.
    public static func cleanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var scalars = Array(raw.unicodeScalars)
        while let first = scalars.first, isTrimSpace(first) { scalars.removeFirst() }
        while let last = scalars.last, isTrimSpace(last) { scalars.removeLast() }

        var words: [[Unicode.Scalar]] = []
        var word: [Unicode.Scalar] = []
        for s in scalars {
            if isSplitSpace(s) {
                if !word.isEmpty { words.append(word); word = [] }
            } else {
                word.append(s)
            }
        }
        if !word.isEmpty { words.append(word) }
        if words.isEmpty { return nil }

        var joined = String.UnicodeScalarView()
        for (i, w) in words.enumerated() {
            if i > 0 { joined.append(" ") }
            joined.append(contentsOf: w)
        }
        return capped(String(joined))
    }

    /// The letters that stand in for a face: the first letter of the first word and of the last, in
    /// capitals. One word gives one letter, and no name gives nothing.
    ///
    /// A word that has no letter in it, a dash or an emoji, is skipped rather than shown, and an
    /// accent that came with its letter goes with it.
    public static func initials(_ name: String?) -> String {
        guard let cleaned = cleanName(name) else { return "" }
        let words = splitOnSpace(Array(cleaned.unicodeScalars))
        let picked = words.count == 1 ? words : [words.first!, words.last!]
        return picked.compactMap(leadingLetter).joined()
    }

    /// The centred square of the largest size that fits a picture `width` by `height`.
    public static func squareCrop(_ width: Int, _ height: Int) -> Square {
        if width <= 0 || height <= 0 { return Square(0, 0, 0) }
        let side = min(width, height)
        return Square((width - side) / 2, (height - side) / 2, side)
    }

    /// How much to shrink a `width` by `height` photo while decoding it, as the power of two a
    /// bitmap decoder takes, keeping the short side at or above `target`.
    ///
    /// A phone photo is twelve megapixels or more and the avatar is a hundred thousand pixels.
    /// Decoding the whole picture first and shrinking it afterwards would put tens of megabytes on
    /// the heap for a picture that is about to be thrown away.
    public static func sampleSize(_ width: Int, _ height: Int, target: Int = sizePx) -> Int {
        let shortSide = min(width, height)
        var sample = 1
        while shortSide / (sample * 2) >= target { sample *= 2 }
        return sample
    }

    /// What an EXIF orientation tag asks of a picture, by the tag's number in the standard.
    ///
    /// A camera stores the pixels the way the sensor read them and says in the tag how the phone was
    /// held; a decoder does not apply it, so a photo taken upright arrives on its side unless it is
    /// turned here. Zero, one and any number the standard does not define leave the picture as it is.
    public static func upright(_ exifOrientation: Int) -> Upright {
        switch exifOrientation {
        case 2: return Upright(0, true)      // mirrored
        case 3: return Upright(180, false)   // upside down
        case 4: return Upright(180, true)    // mirrored top to bottom
        case 5: return Upright(90, true)     // transposed
        case 6: return Upright(90, false)    // held upright, sensor turned: the usual portrait photo
        case 7: return Upright(270, true)    // transversed
        case 8: return Upright(270, false)   // held the other way up
        default: return Upright(0, false)
        }
    }

    // MARK: what is a space, a letter, a mark

    /// What Kotlin's `Char.isWhitespace` trims: the separators (Zs, Zl, Zp), the ASCII spacing
    /// controls, and the four information separators.
    private static func isTrimSpace(_ s: Unicode.Scalar) -> Bool {
        if (0x09...0x0D).contains(s.value) || (0x1C...0x1F).contains(s.value) || s.value == 0x20 { return true }
        return isSeparator(s)
    }

    /// What the regex `[\s\p{Z}]` splits on: ASCII `\s` and every separator.
    private static func isSplitSpace(_ s: Unicode.Scalar) -> Bool {
        if (0x09...0x0D).contains(s.value) || s.value == 0x20 { return true }
        return isSeparator(s)
    }

    private static func isSeparator(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    /// `Character.isLetterOrDigit`: a letter of any case or script, or a decimal digit.
    private static func isLetterOrDigit(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// A combining accent: part of the letter before it rather than a letter of its own.
    private static func isMark(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    private static func splitOnSpace(_ scalars: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        var out: [[Unicode.Scalar]] = [[]]
        for s in scalars {
            if s == " " { out.append([]) } else { out[out.count - 1].append(s) }
        }
        return out
    }

    /// Cut to `maxName` UTF-16 units, backing off one if that would leave half a surrogate pair,
    /// and losing the space the cut may have left at the end.
    private static func capped(_ name: String) -> String {
        let units = Array(name.utf16)
        if units.count <= maxName { return name }
        var end = maxName
        if UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
        var kept = Array(String(decoding: units[0..<end], as: UTF16.self).unicodeScalars)
        while let last = kept.last, isTrimSpace(last) { kept.removeLast() }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: kept)
        return String(out)
    }

    /// The first letter or digit of `word`, with the accents that follow it, in capitals.
    private static func leadingLetter(_ word: [Unicode.Scalar]) -> String? {
        var i = 0
        while i < word.count {
            if isLetterOrDigit(word[i]) {
                var end = i + 1
                while end < word.count && isMark(word[end]) { end += 1 }
                var view = String.UnicodeScalarView()
                view.append(contentsOf: word[i..<end])
                return String(view).uppercased()
            }
            i += 1
        }
        return nil
    }
}
