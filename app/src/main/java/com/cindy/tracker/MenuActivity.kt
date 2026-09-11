package com.cindy.tracker

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityMenuBinding
import java.util.Locale

/**
 * Everything the athlete does not need while they are on the bar.
 *
 * The camera HUD had grown to six chips — voice, music, rec, records, help and moves — which at
 * a 48dp minimum touch target plus margins wanted more width than a 360dp phone has, so the row
 * ran off the edge of the screen. The split is not by importance but by *when*: what changes
 * state mid-set stays on the HUD; navigation and configuration are things you settle before the
 * clock starts, and they live here.
 *
 * Music moved down to this side of that line first. On the HUD a tap toggled it and only a *long
 * press* reached the track picker, which is a gesture with nothing on screen to advertise it —
 * the one control in the app whose main job was hidden behind a hold. Choosing a track is a
 * before-the-clock decision like every other row here, and as a row it can say which track is
 * chosen instead of leaving that to be discovered.
 *
 * The voice followed it, which leaves REC alone on the HUD. It had been kept up there as live
 * state, and that was true of the switch on its own; it stopped being true once the voice grew a
 * volume. A switch and a level are one setting in two parts and only read as one where they sit
 * together, and neither is an adjustment anyone makes between two pull-ups. Both audio rows now
 * offer a listen, because a volume set against silence is a number, not a decision.
 *
 * This is deliberately not a home screen. The app still opens straight to the camera — a screen
 * between the launcher and the workout would cost a tap before every session and throw away
 * CameraX warm-up time. The menu is a place you go, not a place you land.
 *
 * Each row carries its current value as a subtitle, so the answer to "what am I set to?" does
 * not require opening the row to find out.
 */
class MenuActivity : AppCompatActivity() {

    companion object {
        /**
         * Whether a workout is live. The movement picker is refused while one is, because the
         * movements have to mean one thing for the whole score — and only [MainActivity] knows.
         */
        private const val EXTRA_WORKOUT_LIVE = "workout_live"

        fun intent(context: Context, workoutLive: Boolean): Intent =
            Intent(context, MenuActivity::class.java)
                .putExtra(EXTRA_WORKOUT_LIVE, workoutLive)

        /** How long each row waits behind the one above it as the list settles in. */
        private const val ROW_STAGGER_MS = 34L
    }

    private lateinit var binding: ActivityMenuBinding
    private lateinit var profile: Profile
    private lateinit var records: RecordStore
    private var workoutLive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMenuBinding.inflate(layoutInflater)
        setContentView(binding.root)

        profile = Profile(this)
        records = RecordStore(this)
        workoutLive = intent.getBooleanExtra(EXTRA_WORKOUT_LIVE, false)

        binding.actions.addView(primaryButton("DONE").apply {
            setOnClickListener { finish() }
        })
        render()
        settleRowsIn()
    }

    /**
     * Brings the rows in one after another, once, on the way in.
     *
     * The screen used to appear finished — the system's default cross-fade, and a list already
     * at rest. Dealing the rows out gives the eye an order to read them in and makes the travel
     * of the screen itself legible as arriving rather than cutting.
     *
     * Only on the way in, deliberately. [render] runs again after every sheet is dismissed, and
     * a list that re-deals itself each time you change a volume would be a screen that cannot
     * keep still.
     */
    private fun settleRowsIn() {
        val group = binding.rows.getChildAt(0) as? InsetGroup ?: return
        for (i in 0 until group.childCount) {
            val row = group.getChildAt(i)
            row.alpha = 0f
            row.translationY = dp(14).toFloat()
            row.animate()
                .alpha(1f)
                .translationY(0f)
                .setStartDelay(i * ROW_STAGGER_MS)
                .setDuration(240L)
                .start()
        }
    }

    /**
     * Down the way it came, rather than whatever the system would have chosen.
     *
     * Overridden here rather than at the two call sites that leave this screen — DONE and the
     * back gesture — because they are both this screen ending, and one of them is not a call
     * site at all.
     */
    override fun finish() {
        super.finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(R.anim.hold, R.anim.menu_exit)
    }

    /**
     * Rebuilt rather than patched, because a row's subtitle is derived from state a sheet may
     * just have changed, and there are six rows.
     */
    private fun render() {
        binding.rows.removeAllViews()

        val movements = profile.movements
        val sessions = records.all().size

        binding.rows.addView(insetGroup {
            row(navRow("Movements", movements.label()) {
                if (workoutLive) {
                    toast("Reset the workout first to change movements")
                } else {
                    chooseMovements(movements) { chosen ->
                        profile.movements = chosen
                        toast(chosen.label())
                        render()
                    }
                }
            })
            row(navRow(
                "Records",
                when (sessions) {
                    0 -> "No sessions yet"
                    1 -> "1 session"
                    else -> "$sessions sessions"
                }
            ) { startActivity(Intent(this@MenuActivity, RecordsActivity::class.java)) })
            row(navRow(
                "Body weight",
                if (profile.hasBodyWeight) {
                    "%.0f kg".format(Locale.US, profile.bodyWeightKg)
                } else {
                    "Not set — calories need it"
                }
            ) { askBodyWeight(profile) { render() } })
            row(navRow("Voice", voiceSubtitle()) { chooseVoice() })
            row(navRow("Music", musicSubtitle()) { chooseMusic() })
            row(navRow(
                "Help",
                "What Cindy is, how it is scored, and where to stand"
            ) { startActivity(Intent(this@MenuActivity, HelpActivity::class.java)) })
        })

        // Said here rather than only when the row is tapped, because it explains why the row
        // will refuse rather than reporting the refusal after the fact.
        if (workoutLive) {
            binding.rows.addView(
                styledText(
                    R.style.Cindy_Footnote,
                    "Movements can only be changed between workouts — they have to mean one " +
                        "thing for the whole score."
                ).apply { setPadding(dp(4), dp(14), dp(4), 0) }
            )
        }
    }

    // ── voice ─────────────────────────────────────────────────────────────────

    /**
     * The preview voice, built only when the athlete opens the voice row.
     *
     * A text-to-speech connection is a bound service and takes a moment to become ready, so it
     * is started when the sheet opens rather than when HEAR IT is tapped — the first tap would
     * otherwise be the one that does nothing. Shut down with the screen.
     */
    private var preview: Speaker? = null

    private fun voiceSubtitle(): String =
        if (profile.voiceOn) "On · ${percent(profile.voiceVolume)}" else "Off"

    /**
     * Whether the voice counts, and how loud.
     *
     * The switch was a HUD chip until now, tapped between sets. It moves here for the reason the
     * music did: with a volume beside it, it is one setting in two parts, and the two are only
     * legible next to each other. Nothing about it needs to be reachable mid-rep — an athlete
     * who wants silence wants it for the session, not for one pull-up.
     */
    private fun chooseVoice() {
        val speaker = preview ?: Speaker(this).also { preview = it }
        var on = profile.voiceOn
        var volume = profile.voiceVolume
        speaker.volume = volume

        val sheet = CindySheet(
            this,
            title = "Voice",
            subtitle = "Counts each rep out loud, calls the movement changes, and says when " +
                "you are in a position that will score."
        )
        sheet.toggle("Count reps out loud", on) { on = it }
        sheet.slider(
            "Volume",
            volume,
            onChange = { volume = it; speaker.volume = it },
            // Spoken only once the grip is let go: restarting the utterance on every pixel of
            // the drag would stutter rather than demonstrate.
            onSettled = { speaker.preview("Three") }
        )
        sheet.add(
            sheetNote(
                "Mixes against the phone's own media volume rather than replacing it. The track " +
                    "drops out of the way whenever the voice speaks."
            )
        )
        sheet.actions(
            primary = "SAVE",
            onPrimary = {
                profile.voiceOn = on
                profile.voiceVolume = volume
                render()
            },
            secondary = "HEAR IT",
            onSecondary = { speaker.preview("Three. Four. Five. Push ups.") },
            secondaryDismisses = false
        )
        sheet.onDismiss { speaker.stop() }.show()
    }

    private fun percent(value: Float): String = "${(value * 100f).toInt()}%"

    // ── music ─────────────────────────────────────────────────────────────────

    /**
     * The track picker, as a field because a launcher has to be registered before the activity
     * is started rather than at the moment it is wanted.
     */
    private val pickTrack = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let { adoptTrack(it) } }

    /**
     * What the row says underneath "Music": the track, and whether it will actually play.
     *
     * A name that cannot be read means the grant behind the URI has gone — the file was deleted,
     * or the app was reinstalled — and the honest thing is to say so here rather than to leave
     * the athlete wondering mid-workout why the music never started.
     */
    private fun musicSubtitle(): String {
        val uri = profile.musicTrack ?: return "No track chosen"
        val name = MusicPlayer.displayName(this, Uri.parse(uri))
            ?: return "That track can no longer be opened"
        return if (profile.musicOn) "$name · ${percent(profile.musicVolume)}" else "Off · $name"
    }

    /**
     * Everything music: what is chosen, whether it plays, and how to change either.
     *
     * The sheet rather than a straight jump to the file picker, because there are two settings
     * and the second one — off for this session, keeping the track — is the one that used to be
     * the HUD chip's tap.
     */
    private fun chooseMusic() {
        val chosen = profile.musicTrack
        val name = chosen?.let { MusicPlayer.displayName(this, Uri.parse(it)) }
        val sheet = CindySheet(
            this,
            title = "Music",
            subtitle = "One track, looped for the whole twenty minutes. It drops in volume while " +
                "the voice is counting, and stops when the clock does."
        )
        sheet.add(
            styledText(
                R.style.Cindy_Headline,
                name ?: if (chosen == null) "No track chosen" else "That track can no longer be opened"
            ).apply {
                setBackgroundResource(R.drawable.glass_card_small)
                setPadding(dp(16), dp(14), dp(16), dp(14))
            }
        )
        if (chosen != null) {
            sheet.toggle("Play during the workout", profile.musicOn) { on ->
                profile.musicOn = on
                render()
            }
            sheet.slider(
                "Volume",
                profile.musicVolume,
                onChange = { v ->
                    profile.musicVolume = v
                    audition?.volume = v
                },
                // Starting the track only once the grip is let go, so a drag is not a series of
                // seeks back to the first bar.
                onSettled = { listenTo(chosen) }
            )
        }
        sheet.add(sheetNote("Anything on the phone the file picker can open. Nothing is uploaded."))
        sheet.actions(
            primary = if (chosen == null) "CHOOSE A TRACK" else "CHANGE TRACK",
            onPrimary = { pickTrack.launch(arrayOf("audio/*")) },
            secondary = if (chosen == null) "CANCEL" else "LISTEN",
            onSecondary = { if (chosen != null) listenTo(chosen) },
            secondaryDismisses = chosen == null
        ).onDismiss {
            stopAudition()
            render()
        }.show()
    }

    /**
     * The preview player, which is not the one the workout uses.
     *
     * [MainActivity] owns the real player and is a different screen with its own lifecycle; two
     * `MediaPlayer`s pointed at the same track would otherwise both be holding it open. This one
     * exists only while a sheet is up, and is released the moment it comes down.
     */
    private var audition: MusicPlayer? = null

    /** Plays the chosen track at the volume currently set, so the mix can be heard being set. */
    private fun listenTo(uri: String) {
        val player = audition ?: MusicPlayer(this).also { audition = it }
        // Set before loading as well as after, because loading applies whatever level is held.
        player.volume = profile.musicVolume
        if (player.trackUri?.toString() != uri && !player.load(Uri.parse(uri))) {
            toast("That track can no longer be played")
            return
        }
        player.play()
    }

    private fun stopAudition() {
        audition?.release()
        audition = null
    }

    override fun onStop() {
        super.onStop()
        // Nothing this screen plays should outlive it — least of all over the workout that comes
        // after, which has a player of its own.
        stopAudition()
        preview?.stop()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAudition()
        preview?.shutdown()
        preview = null
    }

    /**
     * Takes the long-lived grant that lets the track survive a restart, then remembers it.
     *
     * The track is not loaded here: this screen never plays anything, and a MediaPlayer opened
     * to validate a file would be a second one alongside the camera screen's. [MainActivity]
     * picks it up on resume and clears the preference itself if it turns out not to play.
     */
    private fun adoptTrack(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (t: Throwable) {
            Log.w("Cindy", "no persistable permission for $uri", t)
        }
        profile.musicTrack = uri.toString()
        profile.musicOn = true
        render()
        toast("Music: ${MusicPlayer.displayName(this, uri) ?: "track chosen"}")
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
