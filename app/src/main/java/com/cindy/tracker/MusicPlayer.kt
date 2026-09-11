package com.cindy.tracker

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log

/**
 * Loops one user-chosen track for the duration of the workout.
 *
 * The track is picked through the storage access framework rather than bundled, so the app
 * ships no audio of its own and plays whatever the athlete already owns. Choosing it is
 * [MenuActivity]'s job and remembering it is [Profile]'s; this class only plays what it is
 * handed, and [MainActivity] is the only thing that starts and stops it.
 */
class MusicPlayer(private val context: Context) {

    private var player: MediaPlayer? = null
    private var ducked = false

    /**
     * How loud the track plays, 0..1, before [duck] takes anything off it.
     *
     * Held here rather than written straight through to the player so that a volume chosen with
     * nothing loaded survives until something is, and so that ducking has a level to return to.
     */
    var volume = 1f
        set(value) {
            field = value.coerceIn(0f, 1f)
            applyVolume()
        }

    /**
     * What is loaded, so [MainActivity] can tell whether the chosen track is the one playing and
     * skip a reload — which is a decode, and a seek back to the top of a track that may be
     * playing. Null when nothing is loaded, which is also the answer to "is there any music?".
     */
    var trackUri: Uri? = null
        private set

    /** @return true if the track loaded and is ready to play. */
    fun load(uri: Uri): Boolean {
        release()
        return try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(context, uri)
                isLooping = true
                prepare()
            }
            trackUri = uri
            applyVolume()
            true
        } catch (t: Throwable) {
            Log.e("Cindy", "could not load track", t)
            release()
            false
        }
    }

    fun play() {
        player?.takeUnless { it.isPlaying }?.start()
    }

    fun pause() {
        player?.takeIf { it.isPlaying }?.pause()
    }

    fun stop() {
        player?.let {
            if (it.isPlaying) it.pause()
            it.seekTo(0)
        }
    }

    /** Drops the volume while something is being spoken over the top. */
    fun duck(on: Boolean) {
        if (ducked == on) return
        ducked = on
        applyVolume()
    }

    /**
     * Puts the chosen level, ducked or not, onto the player.
     *
     * Ducking multiplies rather than replaces: a track already turned down to a third should not
     * get *louder* because the voice started talking, which is what a fixed ducked level does.
     */
    private fun applyVolume() {
        val v = if (ducked) volume * DUCKED_SHARE else volume
        try {
            player?.setVolume(v, v)
        } catch (t: Throwable) {
            Log.w("Cindy", "volume failed", t)
        }
    }

    fun release() {
        try {
            player?.release()
        } catch (t: Throwable) {
            Log.w("Cindy", "release failed", t)
        }
        player = null
        trackUri = null
        ducked = false
    }

    companion object {
        /** What share of the chosen level survives while the voice is speaking over it. */
        private const val DUCKED_SHARE = 0.18f

        /**
         * What to call a track, without opening it.
         *
         * [MenuActivity] names the chosen track in a row subtitle and must not spin up a
         * [MediaPlayer] to do it. A null answer means the URI could not be read at all, which
         * is how a lapsed permission shows up before anything tries to play.
         */
        fun displayName(context: Context, uri: Uri): String? = try {
            context.contentResolver.query(uri, null, null, null, null)?.use { c ->
                val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (i >= 0 && c.moveToFirst()) c.getString(i).substringBeforeLast('.') else null
            }
        } catch (t: Throwable) {
            null
        }
    }
}
