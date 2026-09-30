package com.cindy.tracker

import java.util.Locale

/**
 * A language the voice can speak: what to call it, which voice it prefers, and its words.
 *
 * "Pack" because the athlete adds it: the phrases ship with the app (a few kilobytes each), and
 * what has to be fetched, on request, is the phone's own voice for the language.
 */
data class VoicePack(
    /** The language tag, such as `es`. It is also the [Phrasebook]'s tag and what is stored. */
    val tag: String,
    /** The language in itself, as the picker's row is headed: "Español". */
    val nativeName: String,
    /** And in English, for the line beneath it: "Spanish". */
    val englishName: String,
    /**
     * The region whose voice is preferred when the phone offers more than one for the language,
     * as an ISO 3166 code: `ES` for Spanish, `BR` for Portuguese.
     */
    val defaultCountry: String,
    val phrasebook: Phrasebook
) {
    init {
        require(tag == phrasebook.tag) { "$tag pack carries the ${phrasebook.tag} phrasebook" }
    }

    /** The voice this pack asks the phone for first. */
    val defaultLocale: Locale get() = Locale.forLanguageTag("$tag-$defaultCountry")
}

/**
 * Every language the voice speaks, in the order the picker lists them.
 *
 * English first, because it is the default and what the voice falls back to; the rest in the
 * order the app was asked for. Adding a language is a phrasebook, a row here, and the tests that
 * hold for every pack.
 */
object VoicePacks {

    val english = VoicePack("en", "English", "English", "US", PhrasebookEn)

    val all: List<VoicePack> = listOf(
        english,
        VoicePack("es", "Español", "Spanish", "ES", PhrasebookEs),
        VoicePack("fr", "Français", "French", "FR", PhrasebookFr),
        VoicePack("de", "Deutsch", "German", "DE", PhrasebookDe),
        VoicePack("it", "Italiano", "Italian", "IT", PhrasebookIt),
        VoicePack("pt", "Português (Brasil)", "Portuguese (Brazil)", "BR", PhrasebookPt),
        VoicePack("nl", "Nederlands", "Dutch", "NL", PhrasebookNl),
        VoicePack("pl", "Polski", "Polish", "PL", PhrasebookPl),
        VoicePack("ro", "Română", "Romanian", "RO", PhrasebookRo),
        VoicePack("tr", "Türkçe", "Turkish", "TR", PhrasebookTr),
        VoicePack("ru", "Русский", "Russian", "RU", PhrasebookRu)
    )

    /**
     * The pack for a stored [tag], or English for one nobody has, such as a language removed in a
     * later version. A preference makes no claim the app has to honour; an unknown one is
     * English, not a crash.
     */
    fun of(tag: String?): VoicePack = all.firstOrNull { it.tag == tag } ?: english
}
