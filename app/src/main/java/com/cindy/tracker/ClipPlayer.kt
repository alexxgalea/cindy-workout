package com.cindy.tracker

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log

/** Plays a [CountClip] now, cutting off the one before. Main thread. */
interface ClipPlayer {
    /** False if the clip could not be played, so the caller can say it another way. */
    fun play(clip: CountClip, volume: Float): Boolean

    fun stop()

    fun release()
}

/**
 * A [ClipPlayer] on a static [AudioTrack], on the same stream and as the same kind of sound as
 * the engine's speech, so the media volume and the music's ducking treat a clip as they treat
 * the voice.
 *
 * One track per clip, made when it is first played and kept, since making one costs more than
 * the few kilobytes it holds; the least recently played go once [KEPT] are held, because a
 * process gets only so many tracks. Only one plays at a time.
 */
class AudioTrackClipPlayer : ClipPlayer {

    private val tracks = object : LinkedHashMap<CountClip, AudioTrack>(KEPT, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<CountClip, AudioTrack>): Boolean {
            if (size <= KEPT) return false
            eldest.value.release()
            return true
        }
    }
    private var playing: AudioTrack? = null

    override fun play(clip: CountClip, volume: Float): Boolean = try {
        stop()
        val track = tracks.getOrPut(clip) { trackFor(clip) }
        track.setVolume(volume)
        track.reloadStaticData()
        track.play()
        playing = track
        true
    } catch (e: Exception) {
        Log.w(TAG, "could not play a count", e)
        false
    }

    override fun stop() {
        playing?.let { runCatching { it.stop() } }
        playing = null
    }

    override fun release() {
        stop()
        tracks.values.forEach { it.release() }
        tracks.clear()
    }

    private fun trackFor(clip: CountClip): AudioTrack {
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(clip.sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(clip.samples.size * 2)
            .build()
        track.write(clip.samples, 0, clip.samples.size)
        return track
    }

    private companion object {
        const val TAG = "Cindy"
        const val KEPT = 16
    }
}
