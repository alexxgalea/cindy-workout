package com.cindy.tracker

/** A [ClipPlayer] that remembers what it played and was told. */
class FakeClipPlayer : ClipPlayer {

    data class Played(val clip: CountClip, val volume: Float)

    val played = mutableListOf<Played>()
    var stops = 0
    var released = false

    /** Whether [play] succeeds. */
    var works = true

    override fun play(clip: CountClip, volume: Float): Boolean {
        if (!works) return false
        played += Played(clip, volume)
        return true
    }

    override fun stop() {
        stops++
    }

    override fun release() {
        released = true
    }
}
