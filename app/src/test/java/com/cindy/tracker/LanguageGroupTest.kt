package com.cindy.tracker

import android.app.Activity
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import java.time.Duration
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The language list, driven the way a thumb drives it: tap a row, tap play, wait, look again.
 *
 * The speaker behind it is a real one on a fake engine that behaves like Google's, so what is
 * checked is the list's whole conversation with the phone — what it says while the engine is
 * still answering, what a tap on each kind of row does, how it hears about a voice arriving —
 * and not just how it is drawn.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LanguageGroupTest {

    private val engine = FakeTtsEngine()
    private val toasts = mutableListOf<String>()
    private var installerOpened = 0

    /** Any themed screen to build the list on; the list needs a context with the app's styles. */
    private fun screen(): Activity = Robolectric.buildActivity(
        MenuActivity::class.java,
        MenuActivity.intent(RuntimeEnvironment.getApplication(), workoutLive = false)
    ).setup().get()

    /** A list on a speaker that runs its background work where it is asked to. */
    private fun group(initial: String = "en"): LanguageGroup {
        val speaker = Speaker(
            RuntimeEnvironment.getApplication(), engine, background = Executor { it.run() }
        )
        return LanguageGroup(screen(), speaker, initial, { toasts += it }, { installerOpened++ })
    }

    /** The phone's engine connects, and the list starts looking. */
    private fun LanguageGroup.opened(): LanguageGroup {
        engine.becomeReady()
        start()
        idle()
        return this
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun idleFor(seconds: Long) =
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(seconds))

    private fun find(root: View, prefix: String): View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) find(root.getChildAt(i), prefix)?.let { return it }
        }
        return null
    }

    private fun row(group: LanguageGroup, prefix: String): View =
        find(group.view, prefix) ?: error("no row starting with \"$prefix\"")

    private fun said(group: LanguageGroup, prefix: String): String =
        row(group, prefix).contentDescription.toString()

    // ── what it says ─────────────────────────────────────────────────────────

    @Test
    fun `each row says how its language stands once the engine has answered`() {
        engine.likeGoogle()
        val group = group().opened()

        assertTrue(said(group, "Español"), "Ready" in said(group, "Español"))
        assertTrue(said(group, "Русский"), "Tap to download" in said(group, "Русский"))
        assertTrue(said(group, "Polski"), "Online voice only" in said(group, "Polski"))
        assertTrue(said(group, "Português"), "Not offered" in said(group, "Português"))
    }

    @Test
    fun `the language it was given is the one ticked`() {
        engine.likeGoogle()
        val group = group(initial = "es").opened()
        assertEquals("es", group.chosen)
        assertTrue(said(group, "Español").endsWith("selected"))
        assertFalse(said(group, "English").endsWith("selected"))
    }

    @Test
    fun `an engine that never answers is eventually said not to be`() {
        val group = group()
        group.start()
        assertTrue(said(group, "Español"), "Checking" in said(group, "Español"))

        idleFor(7)
        assertTrue(said(group, "Español"), "isn't answering" in said(group, "Español"))
        group.stop()
    }

    // ── choosing ─────────────────────────────────────────────────────────────

    @Test
    fun `choosing a language ticks it`() {
        engine.likeGoogle()
        val group = group().opened()

        row(group, "Español").performClick()

        assertEquals("es", group.chosen)
        assertTrue(said(group, "Español").endsWith("selected"))
        assertFalse(said(group, "English").endsWith("selected"))
    }

    @Test
    fun `choosing a language that has to be downloaded asks for it, and shows it under way`() {
        engine.likeGoogle()
        val group = group().opened()

        row(group, "Русский").performClick()

        assertTrue("setVoice:ru-ru-x-ruc-local" in engine.calls)
        assertTrue(toasts.toString(), "Downloading the Russian voice" in toasts)
        assertEquals("ru", group.chosen)
        idle()
        assertTrue(said(group, "Русский"), "Downloading" in said(group, "Русский"))
    }

    @Test
    fun `a language the engine does not speak cannot be chosen, and the tap says why`() {
        engine.likeGoogle()
        val group = group().opened()

        row(group, "Português").performClick()

        assertEquals("en", group.chosen)
        assertTrue(toasts.toString(), toasts.single().contains("doesn't speak Portuguese"))
    }

    @Test
    fun `an engine with no voice to set sends the athlete to its own screen`() {
        engine.listed = emptyList()
        engine.answers["ru-RU"] = LanguageAvailability.MISSING_DATA
        val group = group().opened()
        assertTrue(said(group, "Русский"), "Tap to download" in said(group, "Русский"))

        row(group, "Русский").performClick()

        assertEquals(1, installerOpened)
        assertTrue(toasts.toString(), toasts.last().startsWith("Opening the voice engine"))
    }

    @Test
    fun `Manage voices opens the engine's screen`() {
        engine.likeGoogle()
        val group = group().opened()
        row(group, "Manage voices").performClick()
        assertEquals(1, installerOpened)
    }

    // ── hearing ──────────────────────────────────────────────────────────────

    @Test
    fun `the play button plays the language's sample in a voice for it`() {
        engine.likeGoogle()
        val group = group().opened()

        row(group, "Hear Spanish").performClick()

        assertEquals("Tres. Cuatro. Cinco. Flexiones.", engine.said.last().text)
        assertEquals("nothing needs saying about a voice that is on the phone", emptyList<String>(), toasts)
    }

    @Test
    fun `a preview of a language that is not on the phone says it is online`() {
        engine.likeGoogle()
        val group = group().opened()

        row(group, "Hear Russian").performClick()

        assertEquals(listOf("Playing an online preview"), toasts)
        assertEquals("Три. Четыре. Пять. Отжимания.", engine.said.last().text)
    }

    @Test
    fun `a preview that cannot reach the network says so`() {
        engine.likeGoogle()
        val group = group().opened()
        row(group, "Hear Russian").performClick()
        toasts.clear()

        engine.listener!!.onError(engine.said.last().id, SpeechFailure.NETWORK)
        idle()

        assertEquals(listOf("The Russian preview needs an internet connection"), toasts)
    }

    @Test
    fun `HEAR IT plays whichever language is ticked`() {
        engine.likeGoogle()
        val group = group().opened()
        row(group, "Español").performClick()

        group.previewChosen()

        assertEquals("Tres. Cuatro. Cinco. Flexiones.", engine.said.last().text)
    }

    // ── keeping up with the phone ────────────────────────────────────────────

    @Test
    fun `a voice that arrives while the list is open shows up by itself`() {
        engine.likeGoogle()
        val group = group().opened()
        assertTrue(said(group, "Русский"), "Tap to download" in said(group, "Русский"))

        engine.listed = EngineFixtures.google.map {
            if (it.name == "ru-ru-x-ruc-local") it.copy(installed = true) else it
        }
        idleFor(3)

        assertTrue(said(group, "Русский"), "Ready" in said(group, "Русский"))
    }

    @Test
    fun `a list that has been stopped stops reading`() {
        engine.likeGoogle()
        val group = group().opened()
        group.stop()

        engine.listed = EngineFixtures.google.map {
            if (it.name == "ru-ru-x-ruc-local") it.copy(installed = true) else it
        }
        idleFor(10)

        assertTrue(said(group, "Русский"), "Tap to download" in said(group, "Русский"))
    }

    @Test
    fun `a list that has been stopped starts again where it left off`() {
        engine.likeGoogle()
        val group = group().opened()
        group.stop()
        engine.listed = EngineFixtures.google.map {
            if (it.name == "ru-ru-x-ruc-local") it.copy(installed = true) else it
        }

        group.start()
        idle()

        assertTrue(said(group, "Русский"), "Ready" in said(group, "Русский"))
        assertNotNull(group.view)
    }
}
