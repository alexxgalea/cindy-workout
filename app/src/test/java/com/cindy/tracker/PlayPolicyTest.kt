package com.cindy.tracker

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The privacy policy, held to what Google Play requires of it and to what the app says itself.
 *
 * The policy is published at an address the app links to, and Help's PRIVACY section and the
 * consent sheet say the same things in the app. A promise made in one and not the other is the
 * kind of mismatch Play's review looks for, so the sentences that appear in more than one place
 * are checked against each other here. Rendering is `tools/play/render.py`; this reads the same
 * markers: `{{#strava}}` is kept for a build with Strava, `{{^strava}}` for one without.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PlayPolicyTest {

    private val root: File = run {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        checkNotNull(dir) { "Cannot find the repository root" }
    }

    private val template: String get() = File(root, "play/privacy-policy.html").readText()

    private fun render(withStrava: Boolean): String {
        val block = Regex("""\{\{([#^])strava\}\}(.*?)\{\{/strava\}\}\n?""", RegexOption.DOT_MATCHES_ALL)
        return block.replace(template) {
            val keep = if (it.groupValues[1] == "#") withStrava else !withStrava
            if (keep) it.groupValues[2].trimStart('\n') else ""
        }
    }

    /** The visible words of a page: tags dropped, entities left as they are, spaces collapsed. */
    private fun words(html: String): String = html
        .replace(Regex("(?s)<style.*?</style>"), "")
        .replace(Regex("<[^>]+>"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()

    @After
    fun resetSeam() {
        StravaConfig.availableForTest = null
    }

    private fun helpText(): String {
        val help = Robolectric.buildActivity(HelpActivity::class.java).setup().get()
        val out = mutableListOf<String>()
        fun walk(v: View) {
            if (v is TextView) out += v.text.toString()
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(help.findViewById(android.R.id.content))
        help.finish()
        return out.joinToString("\n")
    }

    @Test
    fun `only the publisher's own details are left to fill in, and the Strava blocks are closed`() {
        val open = Regex("""\{\{[#^]strava\}\}""").findAll(template).count()
        val close = Regex("""\{\{/strava\}\}""").findAll(template).count()
        assertEquals("unbalanced Strava blocks", open, close)
        for (withStrava in listOf(false, true)) {
            val left = Regex("""\{\{[^}]*\}\}""").findAll(render(withStrava)).map { it.value }.toSet()
            assertEquals(
                "something other than the three details is left (strava=$withStrava)",
                setOf("{{DEVELOPER_NAME}}", "{{CONTACT_EMAIL}}", "{{EFFECTIVE_DATE}}"), left
            )
        }
    }

    @Test
    fun `the policy has what Google Play requires of one`() {
        for (withStrava in listOf(false, true)) {
            val page = render(withStrava)
            val text = words(page)
            // Who publishes it and how to reach them.
            assertTrue(text.contains("Published by {{DEVELOPER_NAME}}"))
            assertTrue(page.contains("mailto:{{CONTACT_EMAIL}}"))
            assertTrue(text.contains("Effective {{EFFECTIVE_DATE}}"))
            // The data it touches, how it is kept and removed, and the usual duties.
            for (heading in listOf(
                "What the app uses, and where it goes", "What the app does not do", "Backup",
                "Keeping and deleting your information", "Security", "Children", "Changes", "Contact"
            )) {
                assertTrue("no '$heading' section (strava=$withStrava)", page.contains("<h2>$heading</h2>"))
            }
        }
    }

    @Test
    fun `a build without Strava does not mention it, and one with Strava says what is sent`() {
        assertFalse(words(render(false)).contains("strava", ignoreCase = true))

        val with = words(render(true))
        for (phrase in listOf(
            "Strava's own privacy policy",
            "HTTPS",
            "DISCONNECT",
            "excluded from Android's backup",
            "Never the camera picture, the video or your pose"
        )) {
            assertTrue("the Strava section lost: $phrase", with.contains(phrase))
        }
        // What the consent sheet tells the athlete is sent, in the words the policy uses.
        for (phrase in listOf(
            "every set with its reps", "paused and in real time", "if you have set a body weight",
            "heart-rate trace, if a watch recorded one", "a title and a short description"
        )) {
            assertTrue("the policy no longer says: $phrase", with.contains(phrase))
        }
    }

    @Test
    fun `the policy and Help give the same ways to delete`() {
        val policy = words(render(false))
        val help = helpText().replace(Regex("\\s+"), " ")
        for (phrase in listOf(
            "CLEAR on the Progress screen", "REMOVE on the Account screen", "Clear storage",
            "Movies/Cindy"
        )) {
            assertTrue("the policy lacks: $phrase", policy.contains(phrase))
            assertTrue("Help lacks: $phrase", help.contains(phrase))
        }
        assertTrue(help.contains("no ads, no analytics, no account"))
        assertTrue(policy.contains("no ads, no analytics, no tracking and no account"))
    }

    @Test
    fun `the policy address the app opens is the one the policy is published at`() {
        // The README and Help both point here; the renderer's output is what goes there.
        assertEquals("https://alexxgalea.github.io/cindy-privacy/", AppLinks.PRIVACY_POLICY)
        assertTrue(File(root, "play/privacy-policy.html").isFile)
    }
}
