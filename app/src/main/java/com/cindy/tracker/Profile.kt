package com.cindy.tracker

import android.content.Context

/**
 * The one thing about the athlete the app needs and cannot see: their body weight.
 *
 * Kept deliberately empty until they enter it. A default would let [Calories] produce a
 * confident-looking number that is wrong by however far the default missed, and a wrong calorie
 * figure is worse than no calorie figure.
 */
class Profile(context: Context) {

    private val prefs = context.getSharedPreferences("cindy", Context.MODE_PRIVATE)

    /** Kilograms, or 0.0 when the athlete has not said. */
    var bodyWeightKg: Double
        get() = prefs.getFloat(KEY_WEIGHT, 0f).toDouble()
        set(value) {
            prefs.edit().putFloat(KEY_WEIGHT, value.toFloat().coerceIn(0f, MAX_KG)).apply()
        }

    val hasBodyWeight: Boolean get() = bodyWeightKg > 0.0

    companion object {
        private const val KEY_WEIGHT = "body_weight_kg"
        /** Above the heaviest recorded human, so typos are caught but nobody real is refused. */
        const val MAX_KG = 400f
        const val MIN_KG = 20f
    }
}
