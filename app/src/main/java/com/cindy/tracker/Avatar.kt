package com.cindy.tracker

import kotlin.math.min

/** The largest centred square of a picture, in that picture's own pixels. */
data class Square(val left: Int, val top: Int, val size: Int)

/**
 * What it takes to stand a stored picture upright: turn it clockwise by [degrees], then mirror it
 * left to right if [mirrored].
 *
 * In that order, because that is the order the framework's Matrix applies them in.
 */
data class Upright(val degrees: Int, val mirrored: Boolean)

/**
 * The parts of a name and a profile photo that are arithmetic rather than Android: what to call
 * someone, which letters stand in for a face, and how to cut a picture down to a square.
 *
 * Free of Android types, like [Streak], so that the rules that decide what a stranger's name or
 * a sideways photo turns into can be tested on the JVM. [AvatarStore] decodes and encodes and
 * [AvatarView] draws; neither makes a decision that is made here.
 */
object Avatar {

    /**
     * The edge of the stored square, in pixels.
     *
     * Sharp at the biggest the photo is ever drawn (88dp is 264 px on a 3x screen and 352 on a
     * 4x one) and small enough that the JPEG is tens of kilobytes, which matters because the
     * file rides along in the athlete's backup.
     */
    const val SIZE_PX = 320

    /** The longest name kept. A name here is a label in a row, not a biography. */
    const val MAX_NAME = 30

    /**
     * A name as it is kept: trimmed, with every run of whitespace as a single space, cut to
     * [MAX_NAME], or null when nothing is left.
     *
     * Tidied once on the way in, so that the menu, the profile screen and the leaderboard all
     * show the same thing and none of them has to remember to tidy it. The cut never splits a
     * surrogate pair, so a name does not end in half a character. It can still fall inside a
     * longer sequence, an emoji with a skin tone or a letter with its accent, but the field stops
     * typing at [MAX_NAME] itself, so only a name that arrived some other way gets that far.
     */
    fun cleanName(raw: String?): String? {
        if (raw == null) return null
        val words = raw.trim().split(WHITESPACE).filter { it.isNotEmpty() }
        if (words.isEmpty()) return null
        return capped(words.joinToString(" "))
    }

    /**
     * The letters that stand in for a face: the first letter of the first word and of the last,
     * in capitals. One word gives one letter, and no name gives nothing.
     *
     * A word that has no letter in it, a dash or an emoji, is skipped rather than shown, and an
     * accent that came with its letter goes with it.
     */
    fun initials(name: String?): String {
        val words = cleanName(name)?.split(' ') ?: return ""
        val picked = if (words.size == 1) words else listOf(words.first(), words.last())
        return picked.mapNotNull(::leadingLetter).joinToString("")
    }

    /** The centred square of the largest size that fits a picture [width] by [height]. */
    fun squareCrop(width: Int, height: Int): Square {
        if (width <= 0 || height <= 0) return Square(0, 0, 0)
        val side = min(width, height)
        return Square((width - side) / 2, (height - side) / 2, side)
    }

    /**
     * How much to shrink a [width] by [height] photo while decoding it, as the power of two a
     * bitmap decoder takes, keeping the short side at or above [target].
     *
     * A phone photo is twelve megapixels or more and the avatar is a hundred thousand pixels.
     * Decoding the whole picture first and shrinking it afterwards would put tens of megabytes
     * on the heap for a picture that is about to be thrown away, on the same phone that is
     * about to be asked to count squats.
     */
    fun sampleSize(width: Int, height: Int, target: Int = SIZE_PX): Int {
        val shortSide = min(width, height)
        var sample = 1
        while (shortSide / (sample * 2) >= target) sample *= 2
        return sample
    }

    /**
     * What an EXIF orientation tag asks of a picture, by the tag's number in the standard.
     *
     * A camera stores the pixels the way the sensor read them and says in the tag how the phone
     * was held; the decoder does not apply it, so a photo taken upright arrives on its side
     * unless it is turned here. Zero, one and any number the standard does not define leave the
     * picture as it is.
     */
    fun upright(exifOrientation: Int): Upright = when (exifOrientation) {
        2 -> Upright(0, true)      // mirrored
        3 -> Upright(180, false)   // upside down
        4 -> Upright(180, true)    // mirrored top to bottom
        5 -> Upright(90, true)     // transposed
        6 -> Upright(90, false)    // held upright, sensor turned: the usual portrait photo
        7 -> Upright(270, true)    // transversed
        8 -> Upright(270, false)   // held the other way up
        else -> Upright(0, false)
    }

    private val WHITESPACE = Regex("[\\s\\p{Z}]+")

    private fun capped(name: String): String {
        if (name.length <= MAX_NAME) return name
        var end = MAX_NAME
        if (Character.isHighSurrogate(name[end - 1])) end--
        return name.substring(0, end).trimEnd()
    }

    /** The first letter or digit of [word], with the accents that follow it, in capitals. */
    private fun leadingLetter(word: String): String? {
        var i = 0
        while (i < word.length) {
            val cp = word.codePointAt(i)
            val width = Character.charCount(cp)
            if (Character.isLetterOrDigit(cp)) {
                var end = i + width
                while (end < word.length && isMark(word.codePointAt(end))) {
                    end += Character.charCount(word.codePointAt(end))
                }
                return word.substring(i, end).uppercase()
            }
            i += width
        }
        return null
    }

    /** A combining accent: part of the letter before it rather than a letter of its own. */
    private fun isMark(codePoint: Int): Boolean = when (Character.getType(codePoint)) {
        Character.NON_SPACING_MARK.toInt(),
        Character.COMBINING_SPACING_MARK.toInt(),
        Character.ENCLOSING_MARK.toInt() -> true
        else -> false
    }
}
