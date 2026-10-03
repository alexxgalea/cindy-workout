package com.cindy.tracker

import android.content.Context

/**
 * The licences of what Cindy is built on, and who gets the credit.
 *
 * Apache-2.0 and the SIL Open Font License both ask for a copy of the licence to travel with the
 * binary, so the full texts ship as assets and Help shows them. They live here, apart from the
 * screen that draws them, so a test can hold the two lists to each other: a credit cannot name a
 * licence whose text is not in the app.
 *
 * The texts are the licences' own, unedited, apart from the copyright block at the head of
 * `ofl-1.1.txt`, which the OFL itself says is the part to fill in with the font's real notice.
 */
object Licences {

    data class Licence(val name: String, val asset: String)

    val APACHE = Licence("Apache License 2.0", "licences/apache-2.0.txt")
    val OFL = Licence("SIL Open Font License 1.1", "licences/ofl-1.1.txt")

    /** Every licence whose full text is in the app. */
    val all = listOf(APACHE, OFL)

    data class Credit(val what: String, val by: String, val licence: Licence)

    val credits = listOf(
        Credit("MoveNet SinglePose, the model that finds your joints", "Google", APACHE),
        Credit("LiteRT, which runs that model on the phone", "Google", APACHE),
        Credit(
            "AndroidX, Material Components, CameraX and WorkManager",
            "The Android Open Source Project and Google",
            APACHE
        ),
        Credit("Kotlin and kotlinx.coroutines", "JetBrains", APACHE),
        // The font's own notice, as it is written in the font file's name table.
        Credit(
            "Manrope, the typeface",
            "Copyright 2019 The Manrope Project Authors (https://github.com/sharanda/manrope)",
            OFL
        )
    )

    /** The full text of [licence], read from the app's assets. */
    fun text(context: Context, licence: Licence): String =
        context.assets.open(licence.asset).bufferedReader().use { it.readText() }
}
