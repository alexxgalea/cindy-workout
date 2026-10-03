package com.cindy.tracker

import android.app.Activity
import android.view.Gravity
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout

/**
 * The sheet that comes before Strava's own consent page.
 *
 * Strava's page says what Strava will let Cindy do. It does not say what Cindy will send, and
 * that is the part Google Play's user-data policy wants said in the app, in plain words, before
 * anything leaves the phone, with a choice that is not a tap on a button that does it anyway. So
 * every road that starts OAuth comes through here: the menu row, the results row's "Connect to
 * upload", and its "Reconnect to upload". Nothing is minted, stored or opened until the athlete
 * taps Strava's own "Connect with Strava" button; NOT NOW, the back gesture and a tap outside all
 * leave without having started anything.
 *
 * The list of what is sent is [StravaPayload] and [StravaActivityText] in words. If one of those
 * gains a field, this changes in the same commit, or the sheet is promising less than the upload
 * does.
 */
object StravaConsent {

    /**
     * Strava keeps heart rate behind a per-athlete switch that no API permission can turn on. The
     * connected sheet carries this too, so the two cannot drift into saying different things.
     */
    const val DATA_PERMISSIONS =
        "Heart rate reaches Strava only once you allow it there: on strava.com, open " +
            "Settings, then Data Permissions, then Allow Access. Until then Strava drops " +
            "it from every upload."

    const val CONNECT_LABEL = "Connect with Strava"
    const val COMPATIBLE_LABEL = "Compatible with Strava"

    /**
     * Strava's "Compatible with Strava" mark, for the sheet that is open while the integration is
     * in use. Small on purpose: Strava's guidelines say its name must not look more prominent than
     * the app's own, and this sits under a note, not beside a title. White for the dark sheet.
     */
    fun compatibleLogo(activity: Activity): ImageView = ImageView(activity).apply {
        setImageResource(R.drawable.logo_compatible_with_strava)
        contentDescription = COMPATIBLE_LABEL
        scaleType = ImageView.ScaleType.FIT_START
        layoutParams = LinearLayout.LayoutParams(activity.dp(200), activity.dp(17)).apply {
            topMargin = activity.dp(14)
        }
    }

    /** [onConnect] runs only after the athlete has tapped Strava's button. */
    fun show(activity: Activity, onConnect: () -> Unit) {
        val sheet = CindySheet(
            activity,
            title = "Connect to Strava",
            subtitle = "Cindy can upload each finished workout to your Strava account. " +
                "Nothing is sent until you connect."
        )

        sheet.add(activity.eyebrow("EACH WORKOUT SENDS").apply {
            setPadding(0, activity.dp(14), 0, activity.dp(6))
        })
        sheet.add(
            activity.styledText(
                R.style.Cindy_Callout,
                "Its score and every set with its reps. When it started, and how long it took " +
                    "on the clock, paused and in real time. Calories, if you have set a body " +
                    "weight. Your heart rate, if a watch recorded it. A title and a short " +
                    "description, such as the score and the pace."
            )
        )
        sheet.add(
            activity.sheetNote(
                "Never the camera picture, the video or the pose. After you connect, each " +
                    "workout uploads by itself; there is a switch for that in the Strava " +
                    "sheet, and DISCONNECT there takes the connection off the phone."
            )
        )
        sheet.add(activity.sheetNote(DATA_PERMISSIONS))

        sheet.add(ImageView(activity).apply {
            setImageResource(R.drawable.btn_strava_connect)
            describeAsButton(CONNECT_LABEL)
            setOnClickListener {
                sheet.dismiss()
                onConnect()
            }
            layoutParams = LinearLayout.LayoutParams(
                activity.dp(237), activity.dp(48)
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = activity.dp(18)
            }
        })

        // The one filled button is the safe one, the way KEEP THEM is on the delete-all sheet.
        sheet.actions(primary = "NOT NOW", onPrimary = {}).show()
    }
}
