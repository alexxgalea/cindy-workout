package com.cindy.tracker

import android.content.Context
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat

/**
 * The app's typeface, for the views that draw their own text on a Canvas or restyle one word.
 *
 * Everything that goes through a TextView takes its font from a style in `type.xml`; these are
 * the same files for the places a style cannot reach. They are the only code that names a font
 * resource, so changing the family means changing the files in `res/font` and this one object.
 * Figures drawn here that can change (a countdown, a round number) still set
 * `fontFeatureSettings = "tnum"` on their Paint, as the numeric styles do.
 */
object CindyType {

    fun regular(context: Context): Typeface = load(context, R.font.inter_regular)
    fun semiBold(context: Context): Typeface = load(context, R.font.inter_semibold)
    fun bold(context: Context): Typeface = load(context, R.font.inter_bold)
    fun extraBold(context: Context): Typeface = load(context, R.font.inter_extrabold)

    private fun load(context: Context, font: Int): Typeface =
        ResourcesCompat.getFont(context, font) ?: Typeface.DEFAULT
}
