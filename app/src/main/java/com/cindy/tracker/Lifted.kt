package com.cindy.tracker

import java.util.Locale
import kotlin.math.roundToInt

/**
 * How much the athlete's own body weight moved in a session, from the reps that were banked.
 *
 * A rep is not worth the whole of the athlete's weight: a pull-up leaves the hands and forearms on
 * the bar, and a push-up leaves the feet on the floor. So each movement is a *share* of body mass,
 * and a movement whose share cannot be stated is left out by name rather than guessed at. The
 * answer is an estimate and is only ever shown as one.
 *
 * Reps come from [StravaSets.from], the same bank the Strava upload reads, so a skipped movement
 * contributes what it actually banked and an attempt whose record cannot be trusted contributes
 * nothing. A tally rebuilt from `rounds * 30` would credit work nobody did.
 */
data class Lifted(
    /** What was counted, one entry per movement that banked reps, in the order of a round. */
    val parts: List<Part>,
    /** What was done but deliberately not counted, so the card can say so. */
    val omitted: List<Omitted>,
    /** Kilograms moved across [parts]. */
    val totalKg: Double,
    /** True when the score is a lower bound: the camera was blind for part of the session. */
    val atLeast: Boolean
) {
    /** One movement's contribution, at the variant the session was actually done with. */
    data class Part(
        val movement: Exercise,
        /** The plain name for an unchanged movement, the variant's own plural ("knee push-ups") for a changed one. */
        val label: String,
        val reps: Int,
        /** The share of body mass one rep lifts. */
        val share: Double,
        val kg: Double
    )

    /** A movement that banked reps but has no share the app can stand behind. */
    data class Omitted(
        val movement: Exercise,
        val label: String,
        val reps: Int,
        val reason: String
    )

    /** "About" or, for a lower-bound score, "At least": the word that goes before [kgNumber]. */
    val kgPrefix: String get() = if (atLeast) "At least" else "About"

    /**
     * The kilograms as a grouped number: "12,940".
     *
     * Rounded to the nearest 10 kg from 100 kg up: a figure built from a body-segment share is no
     * more exact than that, and a spurious last digit would claim it was.
     */
    val kgNumber: String
        get() {
            val rounded = if (totalKg >= 100.0) Math.round(totalKg / 10.0) * 10L else Math.round(totalKg)
            return String.format(Locale.US, "%,d", rounded)
        }

    /** "About 12,940 kg", or "At least 12,940 kg" for a lower-bound score. */
    fun kgText(): String = "$kgPrefix $kgNumber kg"

    /**
     * The small print: which shares were applied, which movements were left out and why, and
     * what kind of reps went in.
     *
     * Names only the movements that banked reps, so an adaptive session is never told about a
     * variant it did not do. [tappedIn] says some of the reps were tapped rather than seen, which
     * is real work but a different claim from camera-seen reps, so it is said rather than folded in.
     */
    fun footnote(tappedIn: Boolean): String = buildString {
        append("An estimate from your weight, counting a share of it per rep: ")
        append(parts.joinToString(", ") { "${it.label} ${(it.share * 100).roundToInt()}%" })
        append(". ")
        for (o in omitted) {
            append("${o.label.replaceFirstChar { it.uppercase() }} are left out: ${o.reason}. ")
        }
        if (tappedIn) append("Reps you tapped in count the same as the ones the camera saw. ")
        if (atLeast) append("The camera lost you for part of this session, so this is a floor. ")
    }.trim()

    /** The share of body mass one rep lifts, or why there is none. */
    private sealed interface Rule {
        data class Share(val of: Double) : Rule
        data class LeftOut(val reason: String) : Rule
    }

    companion object {
        /**
         * Everything but the hands and forearms, which stay on the bar: Winter's body-segment
         * table puts them at about 5% of body mass.
         */
        private const val PULL_UP_SHARE = 0.95

        /**
         * The share of body weight the hands carry in a push-up, from Ebben et al. (2011),
         * "Kinetic analysis of several variations of push-ups", J Strength Cond Res 25(10):
         * 64% from the toes, 49% from the knees.
         */
        private const val STANDARD_PUSH_UP_SHARE = 0.64
        private const val KNEE_PUSH_UP_SHARE = 0.49

        /**
         * The body above the knees, which is what a squat raises; the shanks and feet stay where
         * they are. The same segment table as the pull-up.
         */
        private const val SQUAT_SHARE = 0.88

        // These three are exhaustive on purpose, with no `else`: a variant added later has to be
        // placed here before the app compiles, rather than being counted at some default share
        // nobody chose.
        private fun rule(variant: PullVariant): Rule = when (variant) {
            PullVariant.STRICT_PULL_UP -> Rule.Share(PULL_UP_SHARE)
            PullVariant.BAND_ASSISTED_PULL_UP -> Rule.LeftOut("the band's share isn't known")
            PullVariant.INVERTED_ROW -> Rule.LeftOut("how much it lifts depends on the angle")
            PullVariant.FOOT_ASSISTED_PULL_UP -> Rule.LeftOut("the share your feet take isn't known")
            PullVariant.NEGATIVE_PULL_UP -> Rule.LeftOut("a negative is a lowering, not a lift")
        }

        private fun rule(variant: PushVariant): Rule = when (variant) {
            PushVariant.STANDARD_PUSH_UP -> Rule.Share(STANDARD_PUSH_UP_SHARE)
            PushVariant.KNEE_PUSH_UP -> Rule.Share(KNEE_PUSH_UP_SHARE)
            PushVariant.INCLINE_PUSH_UP -> Rule.LeftOut("it depends on the height of the bench, which isn't known")
        }

        private fun rule(variant: SquatVariant): Rule = when (variant) {
            SquatVariant.AIR_SQUAT, SquatVariant.HEELS_FLAT, SquatVariant.BOX_SQUAT ->
                Rule.Share(SQUAT_SHARE)
            SquatVariant.SUPPORTED_SQUAT -> Rule.LeftOut("the share the support takes isn't known")
        }

        /**
         * The rule and the label for [movement] as [profile] performed it.
         *
         * An unchanged movement keeps its plain name ("pull-ups"), as the rest of the app does;
         * only a movement the athlete changed is named by its variant ("knee push-ups"), so a
         * standard session never reads "strict pull-ups" for what it simply called pull-ups.
         */
        private fun ruleFor(profile: CindyProfile, movement: Exercise): Pair<Rule, String> {
            val standard = CindyProfile.STANDARD
            return when (movement) {
                Exercise.PULLUP ->
                    rule(profile.pull) to if (profile.pull == standard.pull) "pull-ups" else profile.pull.plural
                Exercise.PUSHUP ->
                    rule(profile.push) to if (profile.push == standard.push) "push-ups" else profile.push.plural
                Exercise.SQUAT ->
                    rule(profile.squat) to if (profile.squat == standard.squat) "squats" else profile.squat.plural
            }
        }

        /**
         * What [a] lifted at [bodyWeightKg], or null when that cannot be said honestly: no weight,
         * a record whose sets cannot be trusted (including every attempt from before reps were
         * counted), movements this build does not recognise, or nothing counted at all.
         *
         * Tapped-in reps are counted: they were real work, and the card says they are a different
         * claim from reps the camera saw.
         */
        fun of(a: Attempt, bodyWeightKg: Double): Lifted? {
            if (!(bodyWeightKg > 0.0)) return null
            val tally = tally(a) ?: return null
            if (tally.counted.isEmpty()) return null
            val parts = tally.counted.map { c ->
                Part(c.movement, c.label, c.reps, c.share, c.reps * c.share * bodyWeightKg)
            }
            return Lifted(
                parts = parts,
                omitted = tally.omitted,
                totalKg = parts.sumOf { it.kg },
                atLeast = a.scoreIsLowerBound
            )
        }

        /**
         * Whether [a] has something to lift, whatever the athlete weighs: what decides if the page
         * should invite them to enter a weight rather than show nothing.
         */
        fun measurable(a: Attempt): Boolean = tally(a)?.counted?.isNotEmpty() == true

        private class Counted(val movement: Exercise, val label: String, val reps: Int, val share: Double)

        private class Tally(val counted: List<Counted>, val omitted: List<Omitted>)

        private fun tally(a: Attempt): Tally? {
            // A null profile is a session from a build that knew a movement this one does not;
            // relabelling it as the standard three would be the lie CindyProfile exists to stop.
            val profile = a.profile ?: return null
            val sets = StravaSets.from(a) ?: return null
            val counted = mutableListOf<Counted>()
            val omitted = mutableListOf<Omitted>()
            for (movement in Exercise.entries) {
                val reps = sets.filter { it.exercise == movement }.sumOf { it.reps }
                if (reps == 0) continue
                val (rule, label) = ruleFor(profile, movement)
                when (rule) {
                    is Rule.Share -> counted += Counted(movement, label, reps, rule.of)
                    is Rule.LeftOut -> omitted += Omitted(movement, label, reps, rule.reason)
                }
            }
            return Tally(counted, omitted)
        }
    }
}
