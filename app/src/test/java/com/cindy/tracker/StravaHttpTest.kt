package com.cindy.tracker

import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class StravaHttpTest {

    // ---- FormBody -----------------------------------------------------------------------

    @Test
    fun `a single field encodes as name equals value`() {
        val body = FormBody.encode(listOf("client_id" to "12345"))
        assertEquals("client_id=12345", String(body, Charsets.UTF_8))
    }

    @Test
    fun `multiple fields join with an ampersand, in order`() {
        val body = FormBody.encode(listOf("grant_type" to "authorization_code", "code" to "abc"))
        assertEquals("grant_type=authorization_code&code=abc", String(body, Charsets.UTF_8))
    }

    @Test
    fun `reserved characters are percent-encoded, and a space becomes a plus`() {
        // Exactly the characters a redirect's state or code could plausibly contain.
        val body = FormBody.encode(listOf("value" to "a b&c=d+e/f?g#h"))
        assertEquals("value=a+b%26c%3Dd%2Be%2Ff%3Fg%23h", String(body, Charsets.UTF_8))
    }

    @Test
    fun `non-ascii text encodes as its utf-8 percent sequence`() {
        val body = FormBody.encode(listOf("name" to "café"))
        assertEquals("name=caf%C3%A9", String(body, Charsets.UTF_8))
    }

    @Test
    fun `an empty field list encodes as an empty body`() {
        assertEquals("", String(FormBody.encode(emptyList()), Charsets.UTF_8))
    }

    // ---- Multipart ------------------------------------------------------------------------

    @Test
    fun `a text field is framed with the boundary and a blank line before its value`() {
        val body = Multipart(boundary = "TEST").apply { field("data_type", "json") }.build()
        assertEquals(
            "--TEST\r\n" +
                "Content-Disposition: form-data; name=\"data_type\"\r\n" +
                "\r\n" +
                "json\r\n" +
                "--TEST--\r\n",
            String(body, Charsets.UTF_8)
        )
    }

    @Test
    fun `a file part carries filename and content-type headers`() {
        val body = Multipart(boundary = "TEST").apply {
            file("file", "cindy-123.json", "application/json", "{}".toByteArray(Charsets.UTF_8))
        }.build()
        assertEquals(
            "--TEST\r\n" +
                "Content-Disposition: form-data; name=\"file\"; filename=\"cindy-123.json\"\r\n" +
                "Content-Type: application/json\r\n" +
                "\r\n" +
                "{}\r\n" +
                "--TEST--\r\n",
            String(body, Charsets.UTF_8)
        )
    }

    @Test
    fun `fields and a file combine with one boundary before each part and a closing boundary`() {
        val body = Multipart(boundary = "TEST").apply {
            field("data_type", "json")
            field("sport_type", "Crossfit")
            file("file", "cindy-1.json", "application/json", "{}".toByteArray(Charsets.UTF_8))
        }.build()
        val expected = listOf(
            "--TEST\r\nContent-Disposition: form-data; name=\"data_type\"\r\n\r\njson\r\n",
            "--TEST\r\nContent-Disposition: form-data; name=\"sport_type\"\r\n\r\nCrossfit\r\n",
            "--TEST\r\nContent-Disposition: form-data; name=\"file\"; " +
                "filename=\"cindy-1.json\"\r\nContent-Type: application/json\r\n\r\n{}\r\n",
            "--TEST--\r\n"
        ).joinToString("")
        assertEquals(expected, String(body, Charsets.UTF_8))
    }

    @Test
    fun `a binary body survives byte for byte, even bytes that look like a boundary or crlf`() {
        // 0x2d is '-', so two of them look like a boundary dash; 13 and 10 are CR and LF.
        val bytes = byteArrayOf(0, 1, 2, 0x2d, 0x2d, 13, 10, 255.toByte())
        val built = Multipart(boundary = "TEST").apply {
            file("file", "blob.bin", "application/octet-stream", bytes)
        }.build()
        val header = (
            "--TEST\r\nContent-Disposition: form-data; name=\"file\"; filename=\"blob.bin\"\r\n" +
                "Content-Type: application/octet-stream\r\n\r\n"
            ).toByteArray(Charsets.UTF_8)
        val trailer = "\r\n--TEST--\r\n".toByteArray(Charsets.UTF_8)
        assertEquals(header.size + bytes.size + trailer.size, built.size)
        assertArrayEquals(header, built.copyOfRange(0, header.size))
        assertArrayEquals(bytes, built.copyOfRange(header.size, header.size + bytes.size))
        assertArrayEquals(trailer, built.copyOfRange(header.size + bytes.size, built.size))
    }

    @Test
    fun `a quote in a field name is escaped so the header stays well-formed`() {
        val body = Multipart(boundary = "TEST").apply { field("weird\"name", "value") }.build()
        assertTrue(String(body, Charsets.UTF_8).contains("name=\"weird\\\"name\""))
    }

    @Test
    fun `content type reports the same boundary the body was framed with`() {
        assertEquals("multipart/form-data; boundary=TEST", Multipart(boundary = "TEST").contentType)
    }

    @Test
    fun `a boundary is generated when none is given, and two instances do not collide`() {
        assertNotEquals(Multipart().contentType, Multipart().contentType)
    }

    // ---- FakeTransport ----------------------------------------------------------------------

    @Test
    fun `FakeTransport records the exact request it received`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(200, emptyMap(), "{}"))
        val request = HttpRequest(
            method = "POST",
            url = "https://www.strava.com/api/v3/oauth/token",
            headers = mapOf("Authorization" to "Bearer xyz"),
            body = "grant_type=refresh_token".toByteArray(Charsets.UTF_8),
            contentType = FormBody.CONTENT_TYPE
        )

        transport.execute(request)

        assertEquals(1, transport.requests.size)
        val recorded = transport.requests.single()
        assertEquals("POST", recorded.method)
        assertEquals("https://www.strava.com/api/v3/oauth/token", recorded.url)
        assertEquals("Bearer xyz", recorded.headers["Authorization"])
        assertEquals(FormBody.CONTENT_TYPE, recorded.contentType)
        assertEquals("grant_type=refresh_token", String(recorded.body!!, Charsets.UTF_8))
    }

    @Test
    fun `FakeTransport replays scripted responses in the order they were queued`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(202, emptyMap(), "first"))
        transport.enqueue(HttpResponse(200, emptyMap(), "second"))
        val get = HttpRequest("GET", "https://example.invalid")

        assertEquals("first", transport.execute(get).body)
        assertEquals("second", transport.execute(get).body)
        assertEquals(2, transport.requests.size)
    }

    @Test
    fun `FakeTransport replays a scripted IOException instead of a response`() {
        val transport = FakeTransport()
        transport.enqueueFailure(IOException("no network"))

        try {
            transport.execute(HttpRequest("GET", "https://example.invalid"))
            fail("expected an IOException")
        } catch (e: IOException) {
            assertEquals("no network", e.message)
        }
    }

    @Test
    fun `FakeTransport fails loudly on a call with nothing scripted, instead of guessing a response`() {
        val transport = FakeTransport()

        try {
            transport.execute(HttpRequest("GET", "https://example.invalid/unscripted"))
            fail("expected an exception naming the unscripted request")
        } catch (e: IllegalStateException) {
            assertTrue(e.message!!.contains("https://example.invalid/unscripted"))
        }
    }
}
