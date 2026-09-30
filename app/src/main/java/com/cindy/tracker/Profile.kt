package com.cindy.tracker

import android.content.Context
import java.util.Calendar

/**
 * What the athlete has told the app about themselves and about how they intend to train.
 *
 * Every setting here is edited from [MenuActivity] and stored here rather than at its point of
 * use, so that a preference key has exactly one owner. They were separate before the menu
 * existed: body weight lived on the results screen, the movement profile and the music track on
 * [MainActivity], and a second reader of any of them would have meant a second copy of its key
 * string. The music settings in particular now have two readers — the menu writes them and the
 * camera screen acts on them — which is precisely why they belong here.
 */
class Profile(context: Context) {

    private val prefs = context.getSharedPreferences("cindy", Context.MODE_PRIVATE)

    /**
     * Kilograms, or 0.0 when the athlete has not said.
     *
     * Kept deliberately empty until they enter it. A default would let [Calories] produce a
     * confident-looking number that is wrong by however far the default missed, and a wrong
     * calorie figure is worse than no calorie figure.
     */
    var bodyWeightKg: Double
        get() = prefs.getFloat(KEY_WEIGHT, 0f).toDouble()
        set(value) {
            prefs.edit().putFloat(KEY_WEIGHT, value.toFloat().coerceIn(0f, MAX_KG)).apply()
        }

    val hasBodyWeight: Boolean get() = bodyWeightKg > 0.0

    /**
     * The movements this Cindy is made of — standard, or whichever adaptations were chosen.
     *
     * An unrecognised value decodes back to the standard three, because a preference makes no
     * claim about a workout that has not happened yet. The same is emphatically not true of a
     * *recorded* attempt, which decodes to an unknown profile instead: see [Records].
     */
    var movements: CindyProfile
        get() = Variations.decode(prefs.getString(KEY_MOVEMENTS, null))
        set(value) {
            prefs.edit().putString(KEY_MOVEMENTS, Variations.encode(value)).apply()
        }

    /**
     * Whether an air-squat session may switch itself to Adaptive Cindy when the squats turn out
     * to be heels flat.
     *
     * Off until real sessions have shown it was the right call: a counter that changes its own
     * mind about a movement has to be asked for before it is trusted. It does not change
     * [movements], which stays what the athlete chose; it only lets the engine notice one of
     * them. Edited together with [movements], in the same sheet, and refused while a workout is
     * live for the same reason.
     */
    var smartSquats: Boolean
        get() = prefs.getBoolean(KEY_SMART_SQUATS, false)
        set(value) {
            prefs.edit().putBoolean(KEY_SMART_SQUATS, value).apply()
        }

    /**
     * The chosen track, as a content URI string, or null for none.
     *
     * A string rather than a `Uri` because that is what a preference holds and what both readers
     * compare; parsing is the caller's business. Clearing it is how a track is removed, and the
     * camera screen clears it by itself if the grant behind it has lapsed — a URI the app can no
     * longer open is not a track the menu should keep offering to play.
     */
    var musicTrack: String?
        get() = prefs.getString(KEY_MUSIC, null)
        set(value) {
            val edit = prefs.edit()
            if (value == null) edit.remove(KEY_MUSIC) else edit.putString(KEY_MUSIC, value)
            edit.apply()
        }

    val hasMusic: Boolean get() = musicTrack != null

    /**
     * Whether the chosen track plays during the workout.
     *
     * Separate from [musicTrack] so that turning the music off for one session does not throw
     * away the choice of track, which is the slow part to redo.
     */
    var musicOn: Boolean
        get() = prefs.getBoolean(KEY_MUSIC_ON, true)
        set(value) {
            prefs.edit().putBoolean(KEY_MUSIC_ON, value).apply()
        }

    /**
     * Whether the voice counts reps out loud.
     *
     * Owned here rather than by the camera screen, which is where it used to live as a HUD chip.
     * It moved for the same reason the music did: it is one of two audio settings that only make
     * sense beside each other, and neither is a decision anyone makes mid-set.
     */
    var voiceOn: Boolean
        get() = prefs.getBoolean(KEY_VOICE_ON, true)
        set(value) {
            prefs.edit().putBoolean(KEY_VOICE_ON, value).apply()
        }

    /**
     * How loud the voice is, 0..1.
     *
     * Separate from the phone's own media volume, and not a replacement for it. The two mix
     * against each other on purpose: the athlete is across the room from the phone, and getting
     * the count audible over the music by turning *everything* up is not the same adjustment as
     * getting it audible over the music.
     */
    var voiceVolume: Float
        get() = prefs.getFloat(KEY_VOICE_VOLUME, DEFAULT_VOICE_VOLUME).coerceIn(0f, 1f)
        set(value) {
            prefs.edit().putFloat(KEY_VOICE_VOLUME, value.coerceIn(0f, 1f)).apply()
        }

    /**
     * The language the voice speaks, as a [VoicePacks] tag: `en` until the athlete picks another.
     *
     * Stored as the bare tag and read back through [VoicePacks.of], so a value for a language
     * this version does not have — a preference from a newer build, restored from a backup — is
     * English rather than an error. Choosing a language the phone has no voice for is allowed:
     * the speaker then counts in English and says so, and switches over when the voice arrives.
     */
    var voiceLanguage: String
        get() = VoicePacks.of(prefs.getString(KEY_VOICE_LANGUAGE, null)).tag
        set(value) {
            prefs.edit().putString(KEY_VOICE_LANGUAGE, VoicePacks.of(value).tag).apply()
        }

    /** How loud the track is, 0..1, before the voice ducks it. */
    var musicVolume: Float
        get() = prefs.getFloat(KEY_MUSIC_VOLUME, DEFAULT_MUSIC_VOLUME).coerceIn(0f, 1f)
        set(value) {
            prefs.edit().putFloat(KEY_MUSIC_VOLUME, value.coerceIn(0f, 1f)).apply()
        }

    /** Whether the daily reminder is on. Off until the athlete asks for it. */
    var reminderOn: Boolean
        get() = prefs.getBoolean(KEY_REMINDER_ON, false)
        set(value) {
            prefs.edit().putBoolean(KEY_REMINDER_ON, value).apply()
        }

    /** Minutes after local midnight the reminder is due, 0..1439. */
    var reminderMinute: Int
        get() = prefs.getInt(KEY_REMINDER_MINUTE, Reminder.DEFAULT_MINUTE_OF_DAY).coerceIn(0, 1439)
        set(value) {
            prefs.edit().putInt(KEY_REMINDER_MINUTE, value.coerceIn(0, 1439)).apply()
        }

    /**
     * The year the athlete was born, or 0 when they have not said.
     *
     * A year rather than an age, for the same reason [bodyWeightKg] is asked for directly rather
     * than guessed: an age goes stale the moment it is typed, and nobody reopens a settings
     * screen once a year to keep a number current. A birth year never goes stale, and [age]
     * derives the current figure from it whenever [Calories] actually needs one.
     */
    var birthYear: Int
        get() = prefs.getInt(KEY_BIRTH_YEAR, 0)
        set(value) {
            prefs.edit().putInt(KEY_BIRTH_YEAR, value).apply()
        }

    /**
     * Which of the Keytel equations the heart-rate estimate should use, or null when the athlete
     * has not chosen.
     *
     * The two published fits — one per sex — diverge enough that picking one for someone who
     * has not said would be its own kind of wrong number, which is why there is a third choice,
     * [Sex.UNSTATED], rather than only the two the equation itself offers: it averages the pair
     * instead of guessing between them.
     */
    var sex: Sex?
        get() = prefs.getString(KEY_SEX, null)?.let { name ->
            // An unknown name — a build that knew a sex this one does not, or corrupted prefs —
            // decodes to null rather than a guessed default, exactly as an unrecognised movement
            // name already does in Records.
            Sex.entries.firstOrNull { it.name == name }
        }
        set(value) {
            val edit = prefs.edit()
            if (value == null) edit.remove(KEY_SEX) else edit.putString(KEY_SEX, value.name)
            edit.apply()
        }

    /**
     * The watch or strap paired for heart rate, or null when none is.
     *
     * The two keys behind it are only ever written or cleared together: an address without the
     * name that goes with it is not something a reconnect could fall back to, and a name without
     * an address is not something it could connect to in the first place.
     */
    var heartRateDevice: HeartRateDevice?
        get() {
            val address = prefs.getString(KEY_HR_ADDRESS, null) ?: return null
            val name = prefs.getString(KEY_HR_NAME, null) ?: return null
            return HeartRateDevice(address, name)
        }
        set(value) {
            val edit = prefs.edit()
            if (value == null) {
                edit.remove(KEY_HR_ADDRESS).remove(KEY_HR_NAME)
            } else {
                edit.putString(KEY_HR_ADDRESS, value.address)
                edit.putString(KEY_HR_NAME, value.name)
            }
            edit.apply()
        }

    /**
     * What the athlete wants to be called, or null when they have not said.
     *
     * Null is meaningful: the app goes on saying "You", as it did before it had a name to use.
     * Tidied on the way in and again on the way out (see [Avatar.cleanName]), so that a value a
     * backup restored from some other build still shows the same way on every screen. It is a
     * label for this phone's screens and is not part of anything the app sends to Strava.
     */
    var displayName: String?
        get() = Avatar.cleanName(prefs.getString(KEY_DISPLAY_NAME, null))
        set(value) {
            val clean = Avatar.cleanName(value)
            val edit = prefs.edit()
            if (clean == null) edit.remove(KEY_DISPLAY_NAME) else edit.putString(KEY_DISPLAY_NAME, clean)
            edit.apply()
        }

    /** The athlete's age in [nowYear], or null when [birthYear] has never been said. */
    fun age(nowYear: Int = Calendar.getInstance().get(Calendar.YEAR)): Int? =
        if (birthYear == 0) null else nowYear - birthYear

    /**
     * Everything [Calories] needs about the athlete, gathered from the settings above.
     *
     * A single call rather than three separate reads, so a caller cannot accidentally read
     * [bodyWeightKg], [age] and [sex] at three different moments and hand [Calories] a body that
     * was never really true all at once.
     */
    fun body(nowYear: Int = Calendar.getInstance().get(Calendar.YEAR)): Body =
        Body(weightKg = bodyWeightKg, age = age(nowYear), sex = sex)

    companion object {
        private const val KEY_WEIGHT = "body_weight_kg"
        private const val KEY_MOVEMENTS = "movement_profile"
        private const val KEY_SMART_SQUATS = "smart_squats"
        /** The key [MainActivity] used when it owned the track, so existing choices survive. */
        private const val KEY_MUSIC = "music_uri"
        private const val KEY_MUSIC_ON = "music_on"
        /** The key the HUD chip used, so an athlete who had turned the voice off keeps it off. */
        private const val KEY_VOICE_ON = "voice_on"
        private const val KEY_VOICE_VOLUME = "voice_volume"
        private const val KEY_VOICE_LANGUAGE = "voice_language"
        private const val KEY_MUSIC_VOLUME = "music_volume"
        private const val KEY_REMINDER_ON = "reminder_on"
        private const val KEY_REMINDER_MINUTE = "reminder_minute"
        private const val KEY_BIRTH_YEAR = "birth_year"
        private const val KEY_SEX = "sex"
        private const val KEY_HR_ADDRESS = "hr_device_address"
        private const val KEY_HR_NAME = "hr_device_name"
        private const val KEY_DISPLAY_NAME = "display_name"

        /**
         * The voice starts at full and the music below it.
         *
         * Not symmetrical, and deliberately so: the count is information and the track is
         * atmosphere, so the default mix is the one where a rep is never missed because of a
         * setting the athlete has not found yet.
         */
        const val DEFAULT_VOICE_VOLUME = 1f
        const val DEFAULT_MUSIC_VOLUME = 0.7f
        /** Above the heaviest recorded human, so typos are caught but nobody real is refused. */
        const val MAX_KG = 400f
        const val MIN_KG = 20f
        /** Bounds for the age the heart-rate formula is given, wide enough to be a typo check only. */
        const val MIN_AGE = 13
        const val MAX_AGE = 100
    }
}
