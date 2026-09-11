package com.cindy.tracker

import android.content.Context

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

    /** How loud the track is, 0..1, before the voice ducks it. */
    var musicVolume: Float
        get() = prefs.getFloat(KEY_MUSIC_VOLUME, DEFAULT_MUSIC_VOLUME).coerceIn(0f, 1f)
        set(value) {
            prefs.edit().putFloat(KEY_MUSIC_VOLUME, value.coerceIn(0f, 1f)).apply()
        }

    companion object {
        private const val KEY_WEIGHT = "body_weight_kg"
        private const val KEY_MOVEMENTS = "movement_profile"
        /** The key [MainActivity] used when it owned the track, so existing choices survive. */
        private const val KEY_MUSIC = "music_uri"
        private const val KEY_MUSIC_ON = "music_on"
        /** The key the HUD chip used, so an athlete who had turned the voice off keeps it off. */
        private const val KEY_VOICE_ON = "voice_on"
        private const val KEY_VOICE_VOLUME = "voice_volume"
        private const val KEY_MUSIC_VOLUME = "music_volume"

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
    }
}
