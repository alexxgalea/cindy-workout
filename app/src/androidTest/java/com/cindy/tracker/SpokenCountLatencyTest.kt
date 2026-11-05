package com.cindy.tracker

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaRecorder
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * How long a rep count takes to be heard once the app asks for it, on this phone's own engine.
 *
 * The engine trace only sees `onStart`, which Android sends before synthesis begins, so it cannot
 * tell when the sound comes out. This says each count the way [Speaker] does (QUEUE_FLUSH, the
 * phrasebook's words, the athlete's volume) and listens through the microphone for it, so the
 * answer includes synthesis, the engine's own leading silence and the speaker's output path.
 *
 * Needs the phone, its speaker, and a quiet room. Off unless asked for:
 *
 *     adb shell pm grant com.cindy.tracker.debug android.permission.RECORD_AUDIO
 *     ./gradlew :app:connectedDebugAndroidTest \
 *         -Pandroid.testInstrumentationRunnerArguments.class=com.cindy.tracker.SpokenCountLatencyTest \
 *         -Pandroid.testInstrumentationRunnerArguments.voiceLatency=true
 *
 * Results go to logcat under the `CindyVoiceLatency` tag.
 */
@RunWith(AndroidJUnit4::class)
class SpokenCountLatencyTest {

    private class Said(val askedNs: Long) {
        @Volatile var startNs = 0L
        @Volatile var firstAudioNs = 0L
        @Volatile var leadingSilenceMs = -1.0
    }

    @Test
    fun aCountIsHeardSoonAfterItIsAskedFor() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("set voiceLatency=true to run", args.getString("voiceLatency") == "true")
        val maxMs = args.getString("voiceLatencyMaxMs")?.toDouble() ?: MAX_MEDIAN_MS
        val context = InstrumentationRegistry.getInstrumentation().targetContext

        val ready = CountDownLatch(1)
        var status = TextToSpeech.ERROR
        val tts = TextToSpeech(context) { status = it; ready.countDown() }
        assertTrue("engine did not connect", ready.await(10, TimeUnit.SECONDS))
        assertTrue("engine failed to connect", status == TextToSpeech.SUCCESS)
        tts.language = Locale.US
        Log.i(TAG, "engine ${tts.defaultEngine}, voice ${tts.voice?.name}")

        val said = ConcurrentHashMap<String, Said>()
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String) {
                said[id]?.startNs = System.nanoTime()
            }

            override fun onBeginSynthesis(id: String, sampleRateInHz: Int, audioFormat: Int, channelCount: Int) {
                rates[id] = sampleRateInHz * channelCount
            }

            override fun onAudioAvailable(id: String, audio: ByteArray) {
                val s = said[id] ?: return
                if (s.firstAudioNs == 0L) s.firstAudioNs = System.nanoTime()
                // Leading silence across chunks: count samples until the first loud one.
                if (s.leadingSilenceMs < 0 || s.leadingSilenceMs == Double.MAX_VALUE) {
                    val rate = rates[id] ?: return
                    val loud = firstLoudSample(audio)
                    val before = silentSamples.getOrDefault(id, 0)
                    if (loud >= 0) {
                        s.leadingSilenceMs = (before + loud) * 1000.0 / rate
                    } else {
                        silentSamples[id] = before + audio.size / 2
                        s.leadingSilenceMs = Double.MAX_VALUE
                    }
                }
            }

            override fun onDone(id: String) = Unit

            @Deprecated("required by the base class")
            override fun onError(id: String) = Unit
        })

        val mic = Microphone()
        mic.start()
        Thread.sleep(1_000) // the room's noise floor
        val counts = 1..COUNTS
        for (n in counts) {
            val id = "count-$n"
            val words = VoicePacks.english.phrasebook.say(VoiceLine.Count(n))
            val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1f) }
            said[id] = Said(System.nanoTime())
            tts.speak(words, TextToSpeech.QUEUE_FLUSH, params, id)
            Thread.sleep(GAP_MS)
        }
        Thread.sleep(500)
        mic.stop()
        tts.shutdown()

        val heard = mutableListOf<Double>()
        Log.i(TAG, "count  ask>start  ask>audio  lead-silence  ask>heard (ms)")
        for (n in counts) {
            val s = said.getValue("count-$n")
            val onsetNs = mic.onsetAfter(s.askedNs, s.askedNs + GAP_MS * 1_000_000L)
            val h = onsetNs?.let { (it - s.askedNs) / 1e6 }
            h?.let(heard::add)
            Log.i(TAG, "%5d  %9s  %9s  %12s  %9s".format(Locale.US, n,
                ms(s.startNs, s.askedNs), ms(s.firstAudioNs, s.askedNs),
                if (s.leadingSilenceMs in 0.0..10_000.0) "%.0f".format(Locale.US, s.leadingSilenceMs) else "-",
                h?.let { "%.0f".format(Locale.US, it) } ?: "-"))
        }
        assertTrue("heard ${heard.size} of ${counts.count()} counts", heard.size >= counts.count() / 2)
        val median = heard.sorted()[heard.size / 2]
        Log.i(TAG, "median ask>heard %.0f ms over %d counts (limit %.0f)".format(Locale.US, median, heard.size, maxMs))
        assertTrue("a count is heard a median %.0f ms after it is asked for".format(Locale.US, median),
            median <= maxMs)
    }

    /**
     * Probe, not a guard: where the half second after `onStart` goes. Renders one count to a file,
     * then plays it untrimmed and trimmed of its leading silence, on an ordinary track and on a
     * low-latency one, plus a click that measures the speaker-to-microphone path alone.
     */
    @Test
    fun whereTheDelayAfterStartGoes() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("set voiceLatency=true to run", args.getString("voiceLatency") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext

        val ready = CountDownLatch(1)
        val tts = TextToSpeech(context) { ready.countDown() }
        assertTrue(ready.await(10, TimeUnit.SECONDS))
        tts.language = Locale.US
        val file = java.io.File(context.cacheDir, "count-5.wav")
        val done = CountDownLatch(1)
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String) = Unit
            override fun onDone(id: String) = done.countDown()
            @Deprecated("required by the base class")
            override fun onError(id: String) = done.countDown()
        })
        tts.synthesizeToFile(VoicePacks.english.phrasebook.say(VoiceLine.Count(5)), Bundle(), file, "file")
        assertTrue("rendering timed out", done.await(10, TimeUnit.SECONDS))
        tts.shutdown()

        val (rate, pcm) = readWav(file)
        val lead = pcm.indexOfFirst { abs(it.toInt()) > LOUD_SAMPLE }.coerceAtLeast(0)
        Log.i(TAG, "rendered 'five': %d Hz, %.0f ms, leading silence %.0f ms".format(Locale.US,
            rate, pcm.size * 1000.0 / rate, lead * 1000.0 / rate))
        val trimmed = pcm.copyOfRange(lead, pcm.size)
        val click = ShortArray(rate / 100) { i -> (if ((i / (rate / 2000)) % 2 == 0) 20000 else -20000).toShort() }

        val mic = Microphone()
        mic.start()
        Thread.sleep(1_000)
        val results = linkedMapOf<String, MutableList<Double>>()
        fun play(name: String, samples: ShortArray, lowLatency: Boolean) {
            val track = staticTrack(samples, rate, lowLatency)
            val list = results.getOrPut(name) { mutableListOf() }
            repeat(PROBE_PLAYS) {
                track.stop()
                track.reloadStaticData()
                val at = System.nanoTime()
                track.play()
                Thread.sleep(GAP_MS)
                mic.onsetAfter(at, at + GAP_MS * 1_000_000L)?.let { list += (it - at) / 1e6 }
            }
            track.release()
        }
        play("untrimmed, ordinary track", pcm, lowLatency = false)
        play("trimmed, ordinary track", trimmed, lowLatency = false)
        play("untrimmed, low-latency track", pcm, lowLatency = true)
        play("trimmed, low-latency track", trimmed, lowLatency = true)
        play("click, low-latency track", click, lowLatency = true)
        mic.stop()

        for ((name, v) in results) {
            val s = v.sorted()
            Log.i(TAG, "%-30s play>heard median %4s ms  (%d of %d heard: %s)".format(Locale.US, name,
                if (s.isEmpty()) "-" else "%.0f".format(Locale.US, s[s.size / 2]), s.size, PROBE_PLAYS,
                v.joinToString(" ") { "%.0f".format(Locale.US, it) }))
        }
    }

    private fun staticTrack(samples: ShortArray, rate: Int, lowLatency: Boolean): android.media.AudioTrack {
        val builder = android.media.AudioTrack.Builder()
            .setAudioAttributes(android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(rate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(android.media.AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(samples.size * 2)
        if (lowLatency) builder.setPerformanceMode(android.media.AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        val track = builder.build()
        track.write(samples, 0, samples.size)
        Log.i(TAG, "track lowLatency=$lowLatency got performanceMode=${track.performanceMode}")
        return track
    }

    /** A 16-bit PCM WAV's sample rate and first channel. */
    private fun readWav(file: java.io.File): Pair<Int, ShortArray> {
        val b = java.nio.ByteBuffer.wrap(file.readBytes()).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        var rate = 0
        var channels = 1
        var p = 12
        while (p + 8 <= b.limit()) {
            val id = String(ByteArray(4) { b.get(p + it) })
            val size = b.getInt(p + 4)
            if (id == "fmt ") {
                channels = b.getShort(p + 10).toInt()
                rate = b.getInt(p + 12)
            }
            if (id == "data") {
                val n = minOf(size, b.limit() - p - 8) / 2 / channels
                return rate to ShortArray(n) { b.getShort(p + 8 + it * 2 * channels) }
            }
            p += 8 + size + (size and 1)
        }
        error("no data chunk in $file")
    }

    private val rates = ConcurrentHashMap<String, Int>()
    private val silentSamples = ConcurrentHashMap<String, Int>()

    private fun firstLoudSample(pcm16: ByteArray): Int {
        var i = 0
        while (i + 1 < pcm16.size) {
            val v = (pcm16[i].toInt() and 0xff) or (pcm16[i + 1].toInt() shl 8)
            if (abs(v.toShort().toInt()) > LOUD_SAMPLE) return i / 2
            i += 2
        }
        return -1
    }

    private fun ms(at: Long, from: Long) = if (at == 0L) "-" else "%.0f".format(Locale.US, (at - from) / 1e6)

    /** Records the room, keeping each 10 ms window's loudness with the moment it was captured. */
    private class Microphone {
        private val rate = 16_000
        private val window = rate / 100
        private val record = AudioRecord(MediaRecorder.AudioSource.UNPROCESSED, rate,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            maxOf(AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT), window * 2 * 8))
        private val times = ArrayList<Long>()
        private val levels = ArrayList<Double>()
        @Volatile private var running = false
        private var thread: Thread? = null

        fun start() {
            check(record.state == AudioRecord.STATE_INITIALIZED) { "microphone unavailable; grant RECORD_AUDIO" }
            running = true
            record.startRecording()
            thread = Thread {
                val buf = ShortArray(window)
                val ts = AudioTimestamp()
                var framesRead = 0L
                while (running) {
                    val n = record.read(buf, 0, window)
                    if (n <= 0) continue
                    // When the window's first frame was captured, from the recorder's own clock.
                    val at = if (record.getTimestamp(ts, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS) {
                        ts.nanoTime + (framesRead - ts.framePosition) * 1_000_000_000L / rate
                    } else {
                        System.nanoTime() - n * 1_000_000_000L / rate
                    }
                    framesRead += n
                    var sum = 0.0
                    for (i in 0 until n) sum += buf[i].toDouble() * buf[i]
                    synchronized(this) {
                        times += at
                        levels += kotlin.math.sqrt(sum / n)
                    }
                }
            }.also { it.start() }
        }

        fun stop() {
            running = false
            thread?.join()
            record.stop()
            record.release()
        }

        /** The first window between [from] and [to] clearly louder than the room. */
        @Synchronized
        fun onsetAfter(from: Long, to: Long): Long? {
            val floor = levels.take(80).sorted().let { it[it.size / 2] }
            val threshold = maxOf(floor * 6, floor + 300)
            for (i in times.indices) {
                if (times[i] in from..to && levels[i] > threshold) return times[i]
            }
            return null
        }
    }

    private companion object {
        const val TAG = "CindyVoiceLatency"
        const val COUNTS = 12
        const val PROBE_PLAYS = 8
        const val GAP_MS = 1_200L
        const val LOUD_SAMPLE = 500
        const val MAX_MEDIAN_MS = 250.0
    }
}
