package com.cindy.tracker

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class StravaAuthTest {

    // ---- authorizeUri ---------------------------------------------------------------------

    @Test
    fun `the authorize URL carries every required param`() {
        val uri = StravaAuth.authorizeUri("abc123")
        assertTrue(uri.startsWith("https://www.strava.com/oauth/mobile/authorize?"))
        val query = uri.substringAfter("?").split("&").associate {
            val (k, v) = it.split("=", limit = 2)
            k to v
        }
        assertEquals("code", query["response_type"])
        assertEquals("auto", query["approval_prompt"])
        assertEquals(StravaConfig.SCOPE, java.net.URLDecoder.decode(query["scope"], "UTF-8"))
        assertEquals(StravaConfig.REDIRECT_URI, java.net.URLDecoder.decode(query["redirect_uri"], "UTF-8"))
        assertEquals("abc123", query["state"])
    }

    // ---- newState ---------------------------------------------------------------------------

    @Test
    fun `newState is 32 hex characters, and two calls do not collide`() {
        val a = StravaAuth.newState()
        val b = StravaAuth.newState()
        assertEquals(32, a.length)
        assertTrue(a.matches(Regex("[0-9a-f]{32}")))
        assertTrue(a != b)
    }

    // ---- parseRedirect ------------------------------------------------------------------------

    private val redirect = StravaConfig.REDIRECT_URI

    @Test
    fun `a matching state with a code and the write scope parses as Code`() {
        val result = StravaAuth.parseRedirect(
            "$redirect?state=xyz&code=abc123&scope=read,activity:write", "xyz"
        )
        assertEquals(RedirectResult.Code("abc123", setOf("read", "activity:write")), result)
    }

    @Test
    fun `a space-delimited scope is accepted the same as a comma-delimited one`() {
        val result = StravaAuth.parseRedirect(
            "$redirect?state=xyz&code=abc123&scope=read%20activity:write", "xyz"
        )
        assertEquals(RedirectResult.Code("abc123", setOf("read", "activity:write")), result)
    }

    @Test
    fun `a wrong state is a mismatch even when the rest of the redirect is well-formed`() {
        val result = StravaAuth.parseRedirect(
            "$redirect?state=wrong&code=abc123&scope=read,activity:write", "xyz"
        )
        assertEquals(RedirectResult.StateMismatch, result)
    }

    @Test
    fun `a missing state is a mismatch, not malformed`() {
        val result = StravaAuth.parseRedirect("$redirect?code=abc123", "xyz")
        assertEquals(RedirectResult.StateMismatch, result)
    }

    @Test
    fun `a denial is reported only once the state has been checked`() {
        val result = StravaAuth.parseRedirect("$redirect?state=xyz&error=access_denied", "xyz")
        assertEquals(RedirectResult.Denied, result)
    }

    @Test
    fun `a denial with the wrong state is a mismatch, not reported as a denial`() {
        val result = StravaAuth.parseRedirect("$redirect?state=wrong&error=access_denied", "xyz")
        assertEquals(RedirectResult.StateMismatch, result)
    }

    @Test
    fun `a matching state with no write scope is reported so, not as a plain Code`() {
        val result = StravaAuth.parseRedirect("$redirect?state=xyz&code=abc123&scope=read", "xyz")
        assertEquals(RedirectResult.MissingWriteScope, result)
    }

    @Test
    fun `a matching state with neither a code nor an error is malformed`() {
        val result = StravaAuth.parseRedirect("$redirect?state=xyz", "xyz")
        assertEquals(RedirectResult.Malformed, result)
    }

    @Test
    fun `a redirect with no query at all is malformed`() {
        val result = StravaAuth.parseRedirect(redirect, "xyz")
        assertEquals(RedirectResult.Malformed, result)
    }

    @Test
    fun `a bad percent-escape is malformed rather than throwing`() {
        val result = StravaAuth.parseRedirect("$redirect?state=%zz&code=abc123", "xyz")
        assertEquals(RedirectResult.Malformed, result)
    }

    @Test
    fun `an unparseable uri is malformed rather than throwing`() {
        val result = StravaAuth.parseRedirect("not a uri at all ??", "xyz")
        assertEquals(RedirectResult.Malformed, result)
    }

    // ---- exchange -----------------------------------------------------------------------------

    @Test
    fun `exchange posts the authorization_code grant and reads the grant back`() {
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(
                200, emptyMap(),
                """{"access_token":"a1","refresh_token":"r1","expires_at":1700000000,
                    |"scope":"read,activity:write","athlete":{"firstname":"Alex","lastname":"G"}}"""
                    .trimMargin()
            )
        )

        val grant = StravaAuth(transport).exchange("thecode")

        val sent = transport.requests.single()
        assertEquals("POST", sent.method)
        assertEquals("${StravaConfig.API_BASE}/oauth/token", sent.url)
        val form = String(sent.body!!, Charsets.UTF_8)
        assertTrue(form.contains("grant_type=authorization_code"))
        assertTrue(form.contains("code=thecode"))
        assertEquals("a1", grant.accessToken)
        assertEquals("r1", grant.refreshToken)
        assertEquals(1700000000L, grant.expiresAtEpochS)
        assertEquals(setOf("read", "activity:write"), grant.scopes)
        assertEquals("Alex G", grant.athleteName)
    }

    @Test
    fun `exchange tolerates a response with no athlete object`() {
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(
                200, emptyMap(),
                """{"access_token":"a1","refresh_token":"r1","expires_at":1700000000,"scope":"read"}"""
            )
        )
        val grant = StravaAuth(transport).exchange("thecode")
        assertEquals(null, grant.athleteName)
    }

    @Test
    fun `exchange throws a plain auth exception on an http error, never marked revoked`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(400, emptyMap(), """{"message":"Bad Request"}"""))
        try {
            StravaAuth(transport).exchange("thecode")
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertFalse(e.revoked)
        }
    }

    // ---- refresh ------------------------------------------------------------------------------

    @Test
    fun `refresh posts the refresh_token grant`() {
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(
                200, emptyMap(),
                """{"access_token":"a2","refresh_token":"r2","expires_at":1700003600,"scope":"read,activity:write"}"""
            )
        )
        val grant = StravaAuth(transport).refresh("oldRefresh")
        val form = String(transport.requests.single().body!!, Charsets.UTF_8)
        assertTrue(form.contains("grant_type=refresh_token"))
        assertTrue(form.contains("refresh_token=oldRefresh"))
        assertEquals("a2", grant.accessToken)
        assertEquals("r2", grant.refreshToken)
    }

    @Test
    fun `refresh on a 401 throws a revoked auth exception`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}"""))
        try {
            StravaAuth(transport).refresh("oldRefresh")
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertTrue(e.revoked)
        }
    }

    @Test
    fun `refresh on a 400 also throws a revoked auth exception`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(400, emptyMap(), """{"message":"Bad Request"}"""))
        try {
            StravaAuth(transport).refresh("oldRefresh")
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertTrue(e.revoked)
        }
    }

    @Test
    fun `refresh on a 500 throws a plain, non-revoked auth exception`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(500, emptyMap(), "oops"))
        try {
            StravaAuth(transport).refresh("oldRefresh")
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertFalse(e.revoked)
        }
    }

    @Test
    fun `a network failure during refresh propagates as an IOException, not swallowed`() {
        val transport = FakeTransport()
        transport.enqueueFailure(IOException("no network"))
        try {
            StravaAuth(transport).refresh("oldRefresh")
            fail("expected IOException")
        } catch (e: IOException) {
            assertEquals("no network", e.message)
        }
    }

    // ---- revoke -------------------------------------------------------------------------------

    @Test
    fun `revoke sends Basic auth and the token plus its hint as form fields`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(200, emptyMap(), ""))

        StravaAuth(transport).revoke("sometoken", "refresh_token")

        val sent = transport.requests.single()
        assertEquals("POST", sent.method)
        assertEquals("${StravaConfig.OAUTH_BASE}/revoke", sent.url)
        assertTrue(sent.headers["Authorization"]!!.startsWith("Basic "))
        val decoded = String(
            java.util.Base64.getDecoder().decode(sent.headers["Authorization"]!!.removePrefix("Basic ")),
            Charsets.UTF_8
        )
        assertEquals("${StravaConfig.clientId}:${StravaConfig.clientSecret}", decoded)
        val form = String(sent.body!!, Charsets.UTF_8)
        assertTrue(form.contains("token=sometoken"))
        assertTrue(form.contains("token_type_hint=refresh_token"))
    }

    @Test
    fun `revoke throws on an http error, so a best-effort caller can catch and ignore it`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}"""))
        try {
            StravaAuth(transport).revoke("sometoken", "access_token")
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            // expected — the caller decides what "best-effort" means, not this class.
        }
    }
}
