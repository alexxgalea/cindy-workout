package com.cindy.tracker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The athlete's photo: a small square copy in the app's own files, not a pointer into their gallery.
 *
 * A pointer would not last. A gallery URI is a grant that lapses with the picker that issued it,
 * and a picture the athlete later deletes from their camera roll should not vanish from their
 * profile. A copy also lets the file be cut to size: the original is twelve megapixels and may
 * carry a location, and neither belongs in a backup. The copy is [Avatar.SIZE_PX] square, which
 * is tens of kilobytes, in the files directory the backup rules already carry.
 *
 * What to do with the picture is decided in [Avatar]; this only does it.
 */
object AvatarStore {

    private const val FILE_NAME = "avatar.jpg"
    private const val JPEG_QUALITY = 90

    private fun file(context: Context) = File(context.filesDir, FILE_NAME)

    fun exists(context: Context): Boolean = file(context).isFile

    /** The stored photo, or null when there is none or it can no longer be read. */
    fun load(context: Context): Bitmap? =
        file(context).takeIf { it.isFile }?.let { BitmapFactory.decodeFile(it.path) }

    /** Removes the photo. True when there is none afterwards. */
    fun clear(context: Context): Boolean {
        val stored = file(context)
        return !stored.exists() || stored.delete()
    }

    /**
     * Makes the picture at [uri] the athlete's photo: decoded small, stood upright, cut to its
     * centred square and stored. True when that worked.
     *
     * When it does not, the photo that was there before is as it was: the new one is written
     * beside it and only moved into place once it is whole, so a picture the decoder chokes on
     * half way cannot leave the athlete with a corrupt file where their photo was.
     */
    suspend fun import(context: Context, uri: Uri): Boolean = withContext(Dispatchers.IO) {
        try {
            copyIn(context, uri)
        } catch (e: Exception) {
            // A picture that is gone, unreadable, or not a picture at all. All the same to the athlete.
            false
        } catch (e: OutOfMemoryError) {
            // The short side is sampled down, so only a freakishly long panorama gets here.
            false
        }
    }

    private fun copyIn(context: Context, uri: Uri): Boolean {
        val resolver = context.contentResolver

        // Asking for the size alone answers through the options and returns no bitmap at all.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        val opened = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, bounds)
            true
        } ?: false
        if (!opened || bounds.outWidth <= 0 || bounds.outHeight <= 0) return false

        val sampling = BitmapFactory.Options().apply {
            inSampleSize = Avatar.sampleSize(bounds.outWidth, bounds.outHeight)
        }
        val decoded = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, sampling)
        } ?: return false

        // A tag this phone cannot read costs the photo its rotation, not the photo.
        val tag = runCatching {
            resolver.openInputStream(uri)?.use {
                ExifInterface(it).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
                )
            }
        }.getOrNull() ?: ExifInterface.ORIENTATION_NORMAL

        val upright = Avatar.upright(tag)
        val turned = if (upright.degrees == 0 && !upright.mirrored) {
            decoded
        } else {
            val matrix = Matrix().apply {
                postRotate(upright.degrees.toFloat())
                if (upright.mirrored) postScale(-1f, 1f)
            }
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        }

        val square = Avatar.squareCrop(turned.width, turned.height)
        val out = Bitmap.createBitmap(Avatar.SIZE_PX, Avatar.SIZE_PX, Bitmap.Config.ARGB_8888)
        try {
            Canvas(out).apply {
                // A JPEG has no transparency, so a PNG's clear pixels would come out as whatever
                // colour happened to be underneath them. The app is black; so is this.
                drawColor(Color.BLACK)
                drawBitmap(
                    turned,
                    Rect(square.left, square.top, square.left + square.size, square.top + square.size),
                    Rect(0, 0, Avatar.SIZE_PX, Avatar.SIZE_PX),
                    Paint().apply { isFilterBitmap = true }
                )
            }
            return store(context, out)
        } finally {
            if (turned !== decoded) turned.recycle()
            decoded.recycle()
            out.recycle()
        }
    }

    /** Writes [photo] beside the stored one and moves it into place only once it is whole. */
    private fun store(context: Context, photo: Bitmap): Boolean {
        val target = file(context)
        val partial = File(target.parentFile, "$FILE_NAME.partial")
        val written = partial.outputStream().use {
            photo.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it)
        }
        if (!written || !partial.renameTo(target)) {
            partial.delete()
            return false
        }
        return true
    }
}
