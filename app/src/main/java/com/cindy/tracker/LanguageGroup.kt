package com.cindy.tracker

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The voice sheet's list of languages: one row each, saying where that language stands on this
 * phone, with a button to hear it and a tap to choose it.
 *
 * Each row is two separate targets rather than one — the row chooses, the play button previews —
 * so a screen reader gets two stops it can name, and a thumb aiming for one cannot hit the other.
 *
 * What the athlete sees is only ever what the phone can do. A language the phone can speak says
 * "Ready". One that needs its voice fetched says so and fetches it on the tap that chooses it,
 * and then says "Downloading…", and says something different if that goes on for two minutes,
 * because an engine reports no progress and a download waiting on Wi-Fi looks like a slow one.
 * One the engine does not speak cannot be chosen, and says why. Choosing a language that is not
 * ready yet is allowed, and the workout says it is counting in English until it is.
 *
 * While the sheet is open the states are read again every couple of seconds. That is the only way
 * a download finishing while the athlete watches, or in the engine's own screen, shows up.
 */
class LanguageGroup(
    private val activity: Activity,
    private val speaker: Speaker,
    initial: String,
    private val toast: (String) -> Unit,
    private val openEngineScreen: () -> Unit
) {

    /** The tag of the language ticked. Saved by the sheet's SAVE, not by choosing it. */
    var chosen: String = VoicePacks.of(initial).tag
        private set

    private inner class Row(val pack: VoicePack) {
        val caption: TextView = activity.styledText(R.style.Cindy_Footnote, "Checking…").apply {
            setPadding(0, activity.dp(2), 0, 0)
        }

        val tick = ImageView(activity).apply {
            setImageResource(R.drawable.ic_check)
            imageTintList = ColorStateList.valueOf(activity.getColor(R.color.label))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        /** The part that chooses: the names, how the language stands, and the tick. */
        val select = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(activity.dp(18), activity.dp(12), activity.dp(8), activity.dp(12))
            foreground = RippleDrawable(
                ColorStateList.valueOf(Color.parseColor("#1FFFFFFF")), null, ColorDrawable(Color.WHITE)
            )
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                // The row speaks for itself; its parts must not also be announced.
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                addView(activity.styledText(R.style.Cindy_Headline, pack.nativeName))
                addView(caption)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(
                tick,
                LinearLayout.LayoutParams(activity.dp(19), activity.dp(19)).apply {
                    marginStart = activity.dp(12)
                }
            )
            describeAsButton(VoiceLanguageText.description(pack, "Checking…", chosen = false))
            setOnClickListener { choose(pack) }
        }

        /** The part that previews. */
        val hear = ImageView(activity).apply {
            setImageResource(R.drawable.ic_play)
            imageTintList = ColorStateList.valueOf(activity.getColor(R.color.label_secondary))
            setPadding(activity.dp(14), activity.dp(14), activity.dp(14), activity.dp(14))
            describeAsButton(VoiceLanguageText.previewDescription(pack, null))
            setOnClickListener { preview(pack) }
        }

        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = activity.dp(56)
            addView(select, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(
                hear,
                LinearLayout.LayoutParams(activity.dp(48), activity.dp(48)).apply {
                    marginEnd = activity.dp(8)
                }
            )
        }
    }

    private val rows = VoicePacks.all.map { Row(it) }

    /** What the engine last said about each language, or null until it first has. */
    private var states: Map<String, PackState>? = null

    private val openedAt = SystemClock.elapsedRealtime()
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private val pollAgain = Runnable { poll() }

    val view: View = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        addView(activity.eyebrow("LANGUAGE").apply {
            setPadding(activity.dp(4), activity.dp(18), 0, activity.dp(8))
        })
        addView(activity.insetGroup {
            rows.forEach { row(it.container) }
            row(activity.navRow("Manage voices", "Fetch or remove voice data in the speech engine") {
                openEngineScreen()
            })
        })
        addView(
            activity.sheetNote(
                "Counting uses the voice stored on the phone, so it works offline. Only a preview " +
                    "of a language you haven't downloaded goes online, and it plays a fixed sample."
            )
        )
    }

    init {
        render()
    }

    // ── choosing ──────────────────────────────────────────────────────────────

    private fun choose(pack: VoicePack) {
        val state = states?.get(pack.tag)
        if (!VoiceLanguageText.selectable(state)) {
            toast(VoiceLanguageText.unsupportedNotice(pack))
            return
        }
        chosen = pack.tag
        // The volume check and the sample are spoken in whatever is ticked, as far as the phone can.
        speaker.language = pack.tag
        render()
        if (state == PackState.DOWNLOADABLE) download(pack)
    }

    private fun download(pack: VoicePack) {
        when (speaker.download(pack)) {
            DownloadRequest.ASKED -> {
                toast("Downloading the ${pack.englishName} voice")
                poll()
            }
            DownloadRequest.USE_ENGINE_SCREEN -> {
                toast("Opening the voice engine to fetch ${pack.englishName}")
                openEngineScreen()
            }
            DownloadRequest.NOT_OFFERED ->
                toast("This phone's voice engine doesn't offer ${pack.englishName}")
        }
    }

    // ── hearing ───────────────────────────────────────────────────────────────

    private fun preview(pack: VoicePack) {
        val known = states
        if (known == null) {
            toast(VoiceLanguageText.engineSilent(waited()))
            return
        }
        val state = known[pack.tag]
        if (!VoiceLanguageText.selectable(state)) {
            toast(VoiceLanguageText.unsupportedNotice(pack))
            return
        }
        val started = speaker.previewPack(pack) { failure ->
            toast(VoiceLanguageText.previewFailure(failure, pack))
        }
        // Said once it is playing, not before: a preview that never starts has nothing to label.
        if (started) VoiceLanguageText.previewNote(state)?.let(toast)
    }

    /** Plays the sample of the ticked language: what the sheet's HEAR IT does. */
    fun previewChosen() = preview(VoicePacks.of(chosen))

    // ── keeping up with the phone ─────────────────────────────────────────────

    /** Starts reading the states, now and then every couple of seconds. */
    fun start() {
        if (running) return
        running = true
        poll()
    }

    /** Stops. The sheet dismissed, or the screen no longer showing it. */
    fun stop() {
        running = false
        handler.removeCallbacks(pollAgain)
    }

    private fun poll() {
        if (!running) return
        speaker.packStates { result ->
            states = result
            if (running) render()
        }
        // Quickly until the engine first answers, then at a pace a download can be watched at.
        handler.removeCallbacks(pollAgain)
        handler.postDelayed(pollAgain, if (waitingForEngine()) FIRST_POLL_MS else POLL_MS)
        // With no answer coming back to redraw the rows, time passing is what changes them:
        // "Checking…" turning into "isn't answering" by itself.
        if (states == null) render()
    }

    private fun waited(): Long = SystemClock.elapsedRealtime() - openedAt

    /** True while the engine may yet answer soon. After that it is asked at the ordinary pace. */
    private fun waitingForEngine(): Boolean =
        states == null && waited() < VoiceLanguageText.NO_ANSWER_AFTER_MS

    private fun render() {
        val waited = waited()
        rows.forEach { row ->
            val state = states?.get(row.pack.tag)
            val caption = VoiceLanguageText.caption(state, speaker.downloadingFor(row.pack.tag), waited)
            val isChosen = row.pack.tag == chosen
            row.caption.text = caption
            row.tick.visibility = if (isChosen) View.VISIBLE else View.INVISIBLE
            row.select.contentDescription = VoiceLanguageText.description(row.pack, caption, isChosen)
            row.hear.contentDescription = VoiceLanguageText.previewDescription(row.pack, state)
            row.container.alpha = if (VoiceLanguageText.selectable(state)) 1f else DIMMED
        }
    }

    private companion object {
        /** Until the engine first answers. Short, since it usually does within a second. */
        const val FIRST_POLL_MS = 400L

        /** After that. Often enough to see a download arrive, rarely enough not to matter. */
        const val POLL_MS = 2_000L

        /** A language that cannot be chosen: plainly off, still plainly there. */
        const val DIMMED = 0.45f
    }
}
