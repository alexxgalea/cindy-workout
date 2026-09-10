package com.cindy.tracker

import android.content.Context

/**
 * What the athlete has told the app about themselves and about how they intend to train.
 *
 * Two settings, both edited from [MenuActivity] and both stored here rather than at their point
 * of use, so that a preference key has exactly one owner. They were separate before the menu
 * existed: body weight lived on the results screen and the movement profile on [MainActivity],
 * and a second reader of either would have meant a second copy of its key string.
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

    companion object {
        private const val KEY_WEIGHT = "body_weight_kg"
        private const val KEY_MOVEMENTS = "movement_profile"
        /** Above the heaviest recorded human, so typos are caught but nobody real is refused. */
        const val MAX_KG = 400f
        const val MIN_KG = 20f
    }
}
