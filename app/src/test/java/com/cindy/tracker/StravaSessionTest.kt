package com.cindy.tracker

import androidx.test.core.app.ApplicationProvider
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Robolectric only for [StravaTokenStore]'s [android.content.SharedPreferences] — [StravaAuth]
 * itself stays on [FakeTransport], exactly as it does in [StravaAuthTest].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StravaSessionTest {

    private lateinit var store: StravaTokenStore

    @Before
    fun setUp() {
        store = StravaTokenStore(ApplicationProvider.getApplicationContext())
        store.clearGrant()
    }

    private fun grant(
        accessToken: String,
        refreshToken: String,
        expiresAtEpochS: Long
    ) = StravaGrant(accessToken, refreshToken, expiresAtEpochS, setOf("read", "activity:write"), "Alex")

    companion object {
        private const val NOW_MS = 1_700_000_000_000L
        private const val NOW_S = NOW_MS / 1000L
    }

    @Test
    fun `a token with plenty of life left is returned without touching the network`() {
        store.grant = grant("fresh", "r1", expiresAtEpochS = NOW_S + 3600)
        val transport = FakeTransport() // nothing scripted: any call throws immediately.
        val session = StravaSession(store, StravaAuth(transport), clock = { NOW_MS })

        assertEquals("fresh", session.get())
        assertTrue("no refresh should have been attempted", transport.requests.isEmpty())
    }

    @Test
    fun `a token near expiry is refreshed, and the rotated grant is persisted before get returns`() {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS = NOW_S + 100)
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(
                200, emptyMap(),
                """{"access_token":"freshA","refresh_token":"freshR","expires_at":${NOW_S + 3600},
                    |"scope":"read,activity:write"}""".trimMargin()
            )
        )
        val session = StravaSession(store, StravaAuth(transport), clock = { NOW_MS })

        val token = session.get()

        assertEquals("freshA", token)
        assertEquals("the rotated refresh token must already be on disk", "freshR", store.grant!!.refreshToken)
        assertEquals("freshA", store.grant!!.accessToken)
        val sent = transport.requests.single()
        assertTrue(String(sent.body!!, Charsets.UTF_8).contains("refresh_token=staleRefresh"))
    }

    @Test
    fun `a 401 on refresh clears the stored grant and throws a revoked exception`() {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS = NOW_S + 100)
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}"""))
        val session = StravaSession(store, StravaAuth(transport), clock = { NOW_MS })

        try {
            session.get()
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertTrue(e.revoked)
        }
        assertNull("the grant must be gone once Strava says it is revoked", store.grant)
    }

    @Test
    fun `a 500 on refresh leaves the stored grant alone`() {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS = NOW_S + 100)
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(500, emptyMap(), "oops"))
        val session = StravaSession(store, StravaAuth(transport), clock = { NOW_MS })

        try {
            session.get()
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertFalse(e.revoked)
        }
        assertEquals("a transient failure must not disconnect the athlete", "stale", store.grant?.accessToken)
    }

    @Test
    fun `get throws when there is no grant at all`() {
        val session = StravaSession(store, StravaAuth(FakeTransport()), clock = { NOW_MS })
        try {
            session.get()
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertFalse(e.revoked)
        }
    }

    @Test
    fun `two calls racing a near-expiry token refresh only once`() {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS = NOW_S + 100)
        val calls = AtomicInteger(0)
        val firstEntered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = HttpTransport { _ ->
            calls.incrementAndGet()
            firstEntered.countDown()
            release.await(2, TimeUnit.SECONDS)
            HttpResponse(
                200, emptyMap(),
                """{"access_token":"freshA","refresh_token":"freshR","expires_at":${NOW_S + 3600},
                    |"scope":"read,activity:write"}""".trimMargin()
            )
        }
        val session = StravaSession(store, StravaAuth(transport), clock = { NOW_MS })
        val results = java.util.Collections.synchronizedList(mutableListOf<String>())

        val first = Thread { results.add(session.get()) }
        first.start()
        assertTrue("the first call never reached the network", firstEntered.await(2, TimeUnit.SECONDS))

        val second = Thread { results.add(session.get()) }
        second.start()
        // Gives the second thread a moment to actually queue up on the lock before it is freed,
        // rather than start after the first has already finished.
        Thread.sleep(100)
        release.countDown()

        first.join(2000)
        second.join(2000)

        assertEquals(listOf("freshA", "freshA"), results.sorted())
        assertEquals("only the loser should have found nothing to refresh", 1, calls.get())
    }
}
