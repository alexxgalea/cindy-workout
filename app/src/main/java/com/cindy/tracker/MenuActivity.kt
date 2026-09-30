package com.cindy.tracker

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.text.format.DateFormat
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.cindy.tracker.databinding.ActivityMenuBinding
import com.google.android.material.timepicker.MaterialTimePicker
import com.google.android.material.timepicker.TimeFormat
import java.io.IOException
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

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
     *
     * Every card is dealt, on one running count. The profile card above the settings is the
     * first thing on the screen, and the list carries on from it rather than starting again.
     */
    private fun settleRowsIn() {
        var dealt = 0
        for (g in 0 until binding.rows.childCount) {
            val group = binding.rows.getChildAt(g) as? InsetGroup ?: continue
            for (i in 0 until group.childCount) {
                val row = group.getChildAt(i)
                row.alpha = 0f
                row.translationY = dp(14).toFloat()
                row.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setStartDelay(dealt * ROW_STAGGER_MS)
                    .setDuration(240L)
                    .start()
                dealt++
            }
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
        val all = records.all()
        val sessions = all.size
        val streak = Streak.current(
            Streak.daysTrained(all, ZoneId.systemDefault()), LocalDate.now()
        )
        val stravaTokens = StravaTokenStore(this)
        val stravaGrant = stravaTokens.grant

        // The athlete comes first: who the scores belong to, and what they have earned so far.
        val name = profile.displayName
        val photo = AvatarStore.load(this)
        val earned = Badges.earned(
            all, ZoneId.systemDefault(), WeekFields.of(Locale.getDefault()).firstDayOfWeek
        )
        binding.rows.addView(insetGroup {
            row(avatarRow(
                photo = photo,
                name = name,
                title = name ?: "You",
                value = Badges.headline(earned) ?: if (name == null && photo == null) {
                    "Add your name and photo"
                } else {
                    "Finish a session to earn your first badge"
                }
            ) { startActivity(Intent(this@MenuActivity, AccountActivity::class.java)) })
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(12) })

        binding.rows.addView(insetGroup {
            row(navRow("Movements", movementsSubtitle(movements)) {
                if (workoutLive) {
                    toast("Reset the workout first to change movements")
                } else {
                    chooseMovements(movements, profile) { chosen ->
                        profile.movements = chosen
                        // The subtitle rather than the label, so that turning the squat setting
                        // on or off is confirmed too: the label alone would repeat what it was.
                        toast(movementsSubtitle(chosen))
                        render()
                    }
                }
            })
            row(navRow(
                "Progress",
                when (sessions) {
                    0 -> "No sessions yet"
                    1 -> "1 session"
                    else -> "$sessions sessions"
                } + if (streak >= 1) " · $streak-day streak" else ""
            ) { startActivity(Intent(this@MenuActivity, RecordsActivity::class.java)) })
            row(navRow("Daily reminder", reminderSubtitle()) { chooseReminder() })
            row(navRow(
                "Body weight",
                if (profile.hasBodyWeight) {
                    "%.0f kg".format(Locale.US, profile.bodyWeightKg)
                } else {
                    "Not set — calories need it"
                }
            ) { askBodyWeight(profile) { render() } })
            row(navRow("Heart rate", heartRateSubtitle()) { chooseHeartRate() })
            row(navRow("Strava", stravaSubtitle(StravaConfig.available, stravaGrant)) {
                tapStrava(stravaTokens, stravaGrant)
            })
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

    /**
     * What the row says underneath "Movements": what was chosen, and whether the squats may
     * switch themselves to heels flat.
     *
     * The second half is said only for the air squat, because that is the only choice the setting
     * does anything to: said beside a box squat it would promise something that never happens.
     */
    private fun movementsSubtitle(movements: CindyProfile): String =
        if (profile.smartSquats && movements.squat == SquatVariant.AIR_SQUAT) {
            "${movements.label()} · spots heels flat"
        } else {
            movements.label()
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
        if (profile.voiceOn) {
            "On · ${percent(profile.voiceVolume)} · ${VoicePacks.of(profile.voiceLanguage).nativeName}"
        } else {
            "Off"
        }

    /**
     * The open sheet's language list, so it can be paused while the screen is stopped and picked
     * up again on return — the athlete may have gone to the engine's own screen to fetch a voice.
     */
    private var languageGroup: LanguageGroup? = null

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
        speaker.language = profile.voiceLanguage

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
            onSettled = { speaker.preview(VoiceLine.VolumeCheck) }
        )
        sheet.add(
            sheetNote(
                "Mixes against the phone's own media volume rather than replacing it. The track " +
                    "drops out of the way whenever the voice speaks."
            )
        )
        val languages = LanguageGroup(
            this, speaker, profile.voiceLanguage, ::toast, ::openVoiceInstaller
        )
        languageGroup = languages
        sheet.add(languages.view)
        sheet.actions(
            primary = "SAVE",
            onPrimary = {
                profile.voiceOn = on
                profile.voiceVolume = volume
                profile.voiceLanguage = languages.chosen
                render()
            },
            secondary = "HEAR IT",
            // The sample of whichever language is ticked, in an online voice if that is the only
            // one the phone has for it, rather than always the English it used to be.
            onSecondary = { languages.previewChosen() },
            secondaryDismisses = false
        )
        sheet.onDismiss {
            speaker.stop()
            languages.stop()
            languageGroup = null
        }.show()
        languages.start()
    }

    /**
     * The speech engine's own screen for fetching voice data, or failing that the system's speech
     * settings. Voice data is the engine's to manage, and some engines can only be asked to fetch
     * a voice from their own screen.
     */
    private fun openVoiceInstaller() {
        val screens = listOf(
            Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA),
            Intent("com.android.settings.TTS_SETTINGS")
        )
        for (intent in screens) {
            try {
                startActivity(intent)
                return
            } catch (e: ActivityNotFoundException) {
                Log.w("Cindy", "no screen for $intent", e)
            }
        }
        toast("This phone has no screen for managing voices")
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

    /** Whether the screen has been stopped since it last drew; see [onResume]. */
    private var wasStopped = false

    /**
     * Draws the rows again on the way back to the screen, but not the first time it appears.
     *
     * The first resume follows [onCreate], which has just rendered and started [settleRowsIn];
     * rendering again would rebuild the rows and cancel that entrance. On a return from being
     * stopped it is worth it: the athlete may have changed something elsewhere in the meantime,
     * notably the notification permission in system settings, and the daily reminder row has to
     * say what is true now.
     */
    override fun onResume() {
        super.onResume()
        if (wasStopped) {
            wasStopped = false
            render()
        }
        // Back from the engine's own screen, a voice may have arrived: look at once.
        languageGroup?.start()
    }

    override fun onStop() {
        super.onStop()
        wasStopped = true
        // Nothing this screen plays should outlive it — least of all over the workout that comes
        // after, which has a player of its own.
        stopAudition()
        preview?.stop()
        stopHeartRateSheetResources()
        languageGroup?.stop()
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

    // ── heart rate ───────────────────────────────────────────────────────────

    /**
     * The live connection behind whichever heart-rate sheet is open, and the scan behind
     * "FIND MY WATCH". Both are sheet-scoped exactly like [audition]: started when their sheet
     * opens, and stopped by that same sheet when it closes, or by [onStop].
     *
     * Deliberately not stopped by [render]. The menu re-renders on the way back from being
     * stopped, and a permission or Bluetooth prompt can be what stopped it — in which case the
     * scan its answer just started would be killed by the resume that follows the answer.
     */
    private var heartSource: HeartRateSource? = null
    private var scanner: HeartRateScanner? = null

    private fun stopHeartRateSheetResources() {
        heartSource?.stop()
        heartSource = null
        scanner?.stop()
        scanner = null
    }

    private fun bluetoothAdapter(): BluetoothAdapter? =
        (getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /** What the row says underneath "Heart rate": whether a watch is paired, and by name. */
    private fun heartRateSubtitle(): String {
        val device = profile.heartRateDevice ?: return "No watch paired"
        return if (!profile.body().canUseHeartRate) {
            "${device.name} · add your age for calories"
        } else {
            device.name
        }
    }

    private fun heartRateDetailsSubtitle(): String {
        val body = profile.body()
        return if (body.canUseHeartRate) "${body.sex!!.label} · ${body.age} y" else "Needed for heart-rate calories"
    }

    /**
     * Everything heart rate: pairing a watch, or — once one is paired — a live status line and
     * the age/sex the formula still needs.
     */
    private fun chooseHeartRate() {
        val device = profile.heartRateDevice
        if (device == null) chooseHeartRateUnpaired() else chooseHeartRatePaired(device)
    }

    private fun chooseHeartRateUnpaired() {
        CindySheet(
            this,
            title = "Heart rate",
            subtitle = "Reads the heart rate your watch or chest strap broadcasts, and uses it " +
                "for calories. Nothing is uploaded."
        ).add(
            sheetNote(
                "Turn on heart-rate broadcast on your watch first. Garmin: Broadcast Heart " +
                    "Rate. Polar: share heart rate with other devices. Chest straps broadcast " +
                    "whenever they are worn. Apple Watch and most Wear OS watches do not " +
                    "broadcast a standard heart rate."
            )
        ).actions(
            primary = "FIND MY WATCH",
            onPrimary = { findMyWatch() },
            secondary = "CANCEL",
            onSecondary = {}
        ).show()
    }

    /**
     * A short live-status card, plus the two rows the paired state adds over the unpaired one.
     *
     * This app has no translation seam anywhere else either — see the same warning, already
     * unaddressed, in `Dialogs.kt` and [ResultsActivity] — so the status line's plain-string
     * `setText` calls are suppressed rather than routed through a resource this app has no other
     * use for.
     */
    @SuppressLint("SetTextI18n")
    private fun chooseHeartRatePaired(device: HeartRateDevice) {
        val sheet = CindySheet(
            this,
            title = "Heart rate",
            subtitle = "Reads the heart rate your watch or chest strap broadcasts, and uses it " +
                "for calories. Nothing is uploaded."
        )

        val statusLine = styledText(R.style.Cindy_Footnote, "Connecting…").apply {
            setPadding(0, dp(4), 0, 0)
        }
        sheet.add(insetGroup {
            row(LinearLayout(this@MenuActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(16), dp(14), dp(16), dp(14))
                addView(styledText(R.style.Cindy_Headline, device.name))
                addView(statusLine)
            })
        })
        sheet.add(insetGroup {
            row(navRow("Your details", heartRateDetailsSubtitle()) {
                askHeartRateDetails(profile) {
                    render()
                    sheet.dismiss()
                    chooseHeartRate()
                }
            })
            row(navRow("Find another watch", "Pair a different device") {
                sheet.dismiss()
                findMyWatch()
            })
        })

        // This sheet's own handler, so clearing it clears only the hints this sheet has pending.
        val heartHandler = Handler(Looper.getMainLooper())
        fun hintLater(text: String, delayMs: Long) {
            heartHandler.postDelayed({
                statusLine.text = text
                statusLine.setTextColor(getColor(R.color.label_secondary))
            }, delayMs)
        }
        val listener = object : HeartRateListener {
            override fun onHeartRate(bpm: Int, atElapsedMs: Long) {
                heartHandler.removeCallbacksAndMessages(null)
                statusLine.text = "$bpm bpm"
                statusLine.setTextColor(getColor(R.color.state_ok))
            }

            override fun onStatus(status: HeartRateStatus) {
                heartHandler.removeCallbacksAndMessages(null)
                val message = when (status) {
                    HeartRateStatus.CONNECTING -> {
                        hintLater("Can't find it — is heart-rate broadcast on?", 15_000L)
                        "Connecting…"
                    }
                    // Found and listening: if nothing comes, the watch is not broadcasting, and
                    // that is the one thing worth saying.
                    HeartRateStatus.WAITING -> {
                        hintLater("Connected, but no heart rate — is heart-rate broadcast on?", 8_000L)
                        "Connected — waiting for heart rate…"
                    }
                    HeartRateStatus.NO_PERMISSION -> "Bluetooth permission is off"
                    HeartRateStatus.BLUETOOTH_OFF -> "Bluetooth is off"
                    HeartRateStatus.NOT_A_HEART_RATE_DEVICE ->
                        "No heart rate from it — is heart-rate broadcast on?"
                    HeartRateStatus.UNSUPPORTED -> "This phone has no Bluetooth LE"
                    HeartRateStatus.CONNECTED, HeartRateStatus.OFF -> null
                }
                message?.let {
                    statusLine.text = it
                    statusLine.setTextColor(getColor(R.color.label_secondary))
                }
            }
        }

        // Kept in a local as well as the field: this sheet's dismissal must stop the source this
        // sheet started, and not whichever one a sheet opened after it has put in the field. A
        // dialog's dismiss listener runs after the next sheet may already have been shown.
        val source = HeartRateSources.forProfile(this, profile)
        heartSource = source
        source?.start(listener)

        sheet.actions(
            primary = "DONE",
            onPrimary = {},
            secondary = "FORGET",
            onSecondary = {
                profile.heartRateDevice = null
                render()
            },
            secondaryTint = R.color.state_alert
        ).onDismiss {
            heartHandler.removeCallbacksAndMessages(null)
            source?.stop()
            if (heartSource === source) heartSource = null
        }.show()
    }

    /**
     * What a scan row says under the device's name. A device already linked to the phone says so
     * — that is how a Garmin paired through Garmin Connect is told apart — and shows its signal
     * too when it was also heard advertising.
     */
    private fun foundDeviceLabel(found: FoundDevice): String {
        val signal = found.rssi?.let { signalLabel(it) }
        return when {
            found.connected && signal != null -> "Connected to this phone · $signal"
            found.connected -> "Connected to this phone"
            else -> signal ?: ""
        }
    }

    /** "Strong" / "Good" / "Weak" — the bands the scan sheet shows instead of a raw dBm figure. */
    private fun signalLabel(rssi: Int): String = when {
        rssi >= -60 -> "Strong"
        rssi >= -75 -> "Good"
        else -> "Weak"
    }

    /**
     * Saves [found] as the paired device and reopens the heart-rate sheet on it — straight into
     * "Your details" first when the formula still needs them, since that is the one thing a
     * freshly paired watch is always missing.
     */
    private fun adoptHeartRateDevice(found: FoundDevice) {
        profile.heartRateDevice = HeartRateDevice(found.address, found.name)
        render()
        chooseHeartRate()
        if (!profile.body().canUseHeartRate) {
            askHeartRateDetails(profile) { render() }
        }
    }

    /**
     * A 12-second scan for nearby heart-rate broadcasters. The device list is an [InsetGroup]
     * updated in place as matches arrive, so the sheet itself never flickers mid-scan; only the
     * one-off transition to "SCAN AGAIN" once the window ends rebuilds the sheet, for the primary
     * button's label. Within the group, a row is relabelled where it stands when only its signal
     * changes, and the rows are rebuilt only when a device joins the list, so a row can be tapped
     * while the devices around it keep advertising.
     */
    private fun openScanSheet() {
        var devices = listOf<FoundDevice>()
        // What the rows on screen were built from, and the rows themselves. An update that only
        // changes a signal relabels them where they stand (see HeartRateAdvert.sameRows); only a
        // new device, or a name heard for the first time, rebuilds the list.
        var shown = listOf<FoundDevice>()
        var rows = listOf<View>()
        // True only while a dismiss is this function's own doing (a rebuild, or a device just
        // picked) — the scanner has already been dealt with by then, so the dismiss listener
        // below must not also stop it, or (worse) stop the *next* scan it just started.
        var rebuilding = false
        lateinit var dialog: CindySheet
        lateinit var group: InsetGroup

        fun renderDevices() {
            if (rows.isNotEmpty() && HeartRateAdvert.sameRows(shown, devices)) {
                devices.forEachIndexed { i, found ->
                    rows[i].relabelNavRow(found.name, foundDeviceLabel(found))
                }
                shown = devices
                return
            }
            group.removeAllViews()
            shown = devices
            rows = emptyList()
            if (devices.isEmpty()) {
                group.row(
                    styledText(
                        R.style.Cindy_Callout,
                        "Nothing yet — keep your watch on its broadcast screen"
                    )
                        .apply {
                            setTextColor(getColor(R.color.label_secondary))
                            setPadding(dp(18), dp(16), dp(16), dp(16))
                        }
                )
            } else {
                rows = devices.map { found ->
                    navRow(found.name, foundDeviceLabel(found)) {
                        rebuilding = true
                        scanner?.stop()
                        scanner = null
                        dialog.dismiss()
                        adoptHeartRateDevice(found)
                    }.also { group.row(it) }
                }
            }
        }

        fun buildSheet(windowOpen: Boolean): CindySheet {
            val sheet = CindySheet(this, title = "Looking for heart-rate devices")
            group = insetGroup { }
            sheet.add(group)
            rows = emptyList() // A new group has none of the old rows in it.
            renderDevices()
            val withActions = if (windowOpen) {
                sheet.actions(primary = "CANCEL", onPrimary = {})
            } else {
                sheet.actions(
                    primary = "SCAN AGAIN",
                    onPrimary = { rebuilding = true; openScanSheet() },
                    secondary = "CANCEL",
                    onSecondary = {}
                )
            }
            return withActions.onDismiss {
                if (rebuilding) rebuilding = false else stopHeartRateSheetResources()
            }
        }

        dialog = buildSheet(windowOpen = true)
        scanner = HeartRateScanner(this).also { s ->
            s.start(
                onFound = { found -> devices = found; renderDevices() },
                onDone = {
                    rebuilding = true
                    dialog.dismiss()
                    dialog = buildSheet(windowOpen = false)
                    dialog.show()
                }
            )
        }
        dialog.show()
    }

    private val requestBluetoothPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { results ->
        if (results.values.all { it }) {
            findMyWatch()
        } else {
            toast("Bluetooth permission is needed to find your watch")
        }
    }

    private val requestBluetoothEnable = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        // Whatever the result code, the adapter's own state is the truth: proceed only if the
        // athlete actually turned it on, and say nothing if they backed out of the system prompt.
        if (bluetoothAdapter()?.isEnabled == true) proceedToScan()
    }

    /**
     * The three things that can stand between "FIND MY WATCH" and a working scan, checked in the
     * order that makes each one's system prompt make sense: permission first, since the adapter
     * and location checks below both need it answered; the adapter next, since a location prompt
     * over a radio that is off would be asking the wrong question; the scan itself last.
     */
    @SuppressLint("MissingPermission") // HeartRatePermissions.granted() is checked just above.
    private fun findMyWatch() {
        // Before anything else: with no BLE radio there is no permission worth asking for, and
        // the request-enable intent has nothing to answer it.
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            toast("This phone has no Bluetooth LE, so it cannot hear a watch")
            return
        }
        if (!HeartRatePermissions.granted(this)) {
            requestBluetoothPermissions.launch(HeartRatePermissions.required())
            return
        }
        if (bluetoothAdapter()?.isEnabled != true) {
            requestBluetoothEnable.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
            return
        }
        proceedToScan()
    }

    private fun proceedToScan() {
        if (HeartRatePermissions.locationSwitchBlocksScan(this)) {
            showLocationNeeded()
        } else {
            openScanSheet()
        }
    }

    private fun showLocationNeeded() {
        CindySheet(
            this,
            title = "Location is off",
            subtitle = "Android 11 and older only let apps find Bluetooth devices while " +
                "Location is on. Cindy never reads your location."
        ).actions(
            primary = "OPEN SETTINGS",
            onPrimary = { startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)) },
            secondary = "NOT NOW",
            onSecondary = {}
        ).show()
    }

    // ── reminder ──────────────────────────────────────────────────────────────

    /** Who to tell once the system's notification prompt has been answered. */
    private var afterPermission: ((Boolean) -> Unit)? = null

    /** A field for the same reason as [pickTrack]: registered before the activity starts. */
    private val requestNotifications = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        afterPermission?.invoke(granted)
        afterPermission = null
    }

    /** Runs [then] with whether a notification can be posted, asking on Android 13+ if it can. */
    private fun withNotificationPermission(then: (Boolean) -> Unit) {
        if (ReminderNotifier.canPost(this)) return then(true)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            afterPermission = then
            requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            then(false)
        }
    }

    private fun reminderTime(minute: Int): String =
        Reminder.formatTime(minute, DateFormat.is24HourFormat(this))

    /**
     * What the row says underneath "Daily reminder".
     *
     * A reminder that is switched on but cannot be delivered says so, rather than promising a
     * nudge that will never come.
     */
    private fun reminderSubtitle(): String = when {
        !profile.reminderOn -> "Off"
        !ReminderNotifier.canPost(this) -> "Blocked \u2014 notifications are off for Cindy"
        else -> "Daily at ${reminderTime(profile.reminderMinute)} \u00b7 not on days you train"
    }

    /** Whether the reminder is on, and when. TRY IT sends one now, so the athlete can see it. */
    private fun chooseReminder() {
        var on = profile.reminderOn
        var minute = profile.reminderMinute
        val is24 = DateFormat.is24HourFormat(this)

        val value = styledText(R.style.Cindy_Headline, Reminder.formatTime(minute, is24)).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
            importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val timeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundResource(R.drawable.glass_card_small)
            minimumHeight = dp(52)
            setPadding(dp(16), dp(8), dp(12), dp(8))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(12) }
            addView(styledText(R.style.Cindy_Callout, "Time").apply {
                setTextColor(getColor(R.color.label))
                layoutParams = LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                )
                importantForAccessibility =
                    android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            })
            addView(value)
            describeAsButton("Time, ${value.text}, tap to change")
            setOnClickListener {
                pickTime(minute, is24) {
                    minute = it
                    value.text = Reminder.formatTime(it, is24)
                    describeAsButton("Time, ${value.text}, tap to change")
                }
            }
        }

        CindySheet(
            this,
            title = "Daily reminder",
            subtitle = "One nudge at the time you choose, and none on days you've already trained."
        )
            .toggle("Remind me", on) { on = it }
            .add(timeRow)
            .add(
                sheetNote(
                    "Nothing leaves the phone. The reminder is worked out and sent on this device."
                )
            )
            .actions(
                primary = "SAVE",
                onPrimary = { save(on, minute) },
                secondary = "TRY IT",
                onSecondary = { tryIt() },
                secondaryDismisses = false
            )
            .show()
    }

    /** The system's clock dial, in the phone's own 12- or 24-hour style. */
    private fun pickTime(current: Int, is24: Boolean, onPicked: (Int) -> Unit) {
        val picker = MaterialTimePicker.Builder()
            .setTimeFormat(if (is24) TimeFormat.CLOCK_24H else TimeFormat.CLOCK_12H)
            .setHour(current / 60)
            .setMinute(current % 60)
            .setTitleText("Reminder time")
            .build()
        picker.addOnPositiveButtonClickListener { onPicked(picker.hour * 60 + picker.minute) }
        picker.show(supportFragmentManager, "reminder-time")
    }

    /**
     * Stores the choice. Turning it on without permission leaves it off and says why, so the
     * switch never claims a reminder that cannot arrive.
     */
    private fun save(on: Boolean, minute: Int) {
        profile.reminderMinute = minute
        if (!on) {
            profile.reminderOn = false
            ReminderScheduler.sync(this)
            render()
            return
        }
        withNotificationPermission { granted ->
            if (granted) {
                profile.reminderOn = true
                ReminderScheduler.sync(this)
                toast("Reminder set for ${reminderTime(minute)}")
            } else {
                profile.reminderOn = false
                ReminderScheduler.sync(this)
                notificationsOff()
            }
            render()
        }
    }

    /** Sends today's reminder now, as if today had not been trained. */
    private fun tryIt() {
        withNotificationPermission { granted ->
            if (granted) {
                ReminderNotifier.post(
                    this,
                    Reminder.preview(
                        records.all(),
                        LocalDate.now(),
                        ZoneId.systemDefault(),
                        WeekFields.of(Locale.getDefault()).firstDayOfWeek
                    )
                )
            } else {
                notificationsOff()
            }
        }
    }

    private fun notificationsOff() {
        CindySheet(
            this,
            title = "Notifications are off",
            subtitle = "Cindy can't remind you until notifications are allowed for it."
        ).actions(
            primary = "OPEN SETTINGS",
            onPrimary = {
                startActivity(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                )
            },
            secondary = "NOT NOW",
            onSecondary = {}
        ).show()
    }

    // ── Strava ────────────────────────────────────────────────────────────────

    /**
     * Pure, so [StravaScreenTest] can check every subtitle without building the activity.
     *
     * `available` is passed in rather than read here, so a test can drive every state through
     * [StravaConfig.availableForTest].
     */
    private fun stravaSubtitle(available: Boolean, grant: StravaGrant?): String = when {
        !available -> "Not available in this build"
        grant == null -> "Not connected — upload workouts"
        else -> "Connected · ${grant.athleteName ?: "Strava"}"
    }

    private fun tapStrava(tokens: StravaTokenStore, grant: StravaGrant?) {
        if (!StravaConfig.available) {
            toast("This build has no Strava credentials, so the feature is switched off")
            return
        }
        if (grant == null) connectStrava(tokens) else openStravaSheet(tokens, grant)
    }

    /**
     * Mints a fresh state, remembers it, and opens Strava's own consent page for it.
     *
     * Clears [StravaTokenStore.afterConnectUploadAtMillis] first: that field means "upload this
     * one attempt once connected", set by the results screen's own CONNECT tap, and a connect
     * started from here is not about any particular attempt. Without clearing it, connecting
     * from the menu long after leaving a results screen would silently re-fire whatever request
     * that screen had left pending.
     */
    private fun connectStrava(tokens: StravaTokenStore) {
        tokens.afterConnectUploadAtMillis = null
        val state = StravaAuth.newState()
        tokens.pendingState = state
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(StravaAuth.authorizeUri(state))))
        } catch (e: ActivityNotFoundException) {
            // Neither the Strava app nor a browser is installed to show the consent page.
            tokens.pendingState = null
            toast("Connecting needs the Strava app or a web browser")
        }
    }

    /**
     * The toggle here is what makes the subtitle's claim true or not, so the two must agree:
     * saying "uploads on its own" while the switch underneath it is off would be exactly the
     * kind of confident wrong statement this app's screens otherwise refuse to make.
     */
    private fun stravaSheetSubtitle(grant: StravaGrant, autoUpload: Boolean): String {
        val connectedAs = "Connected${grant.athleteName?.let { " as $it" } ?: ""}."
        return if (autoUpload) {
            "$connectedAs Each finished workout uploads to Strava on its own."
        } else {
            "$connectedAs Automatic upload is off — upload from a workout's results screen instead."
        }
    }

    /**
     * DONE saves the toggle and closes; DISCONNECT is the only other action that does anything.
     */
    private fun openStravaSheet(tokens: StravaTokenStore, grant: StravaGrant) {
        var autoUpload = tokens.autoUpload
        val sheet = CindySheet(
            this,
            title = "Strava",
            subtitle = stravaSheetSubtitle(grant, autoUpload)
        )
        sheet.toggle("Upload automatically", autoUpload) { autoUpload = it }
        sheet.actions(
            primary = "DONE",
            onPrimary = { tokens.autoUpload = autoUpload },
            secondary = "DISCONNECT",
            onSecondary = { disconnectStrava(tokens, grant) },
            secondaryTint = R.color.state_alert
        ).show()
    }

    /**
     * Revokes on Strava's side, best-effort, and forgets the grant locally either way.
     *
     * The athlete may be offline, or may have already removed Cindy Tracker from strava.com
     * themselves — neither should leave the menu row still claiming to be connected. The refresh
     * token is what is sent, rather than the access token: it does not expire on its own, so it
     * is the more likely of the two to still be valid.
     */
    private fun disconnectStrava(tokens: StravaTokenStore, grant: StravaGrant) {
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                StravaAuth(UrlConnectionTransport()).revoke(grant.refreshToken, "refresh_token")
            } catch (e: IOException) {
                // Offline. The local grant comes off regardless, on the next line below.
            } catch (e: StravaAuthException) {
                // Strava already considers us disconnected.
            }
        }
        tokens.clearGrant()
        render()
        toast("Disconnected. If Strava still lists Cindy Tracker, remove it at strava.com/settings/apps")
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
