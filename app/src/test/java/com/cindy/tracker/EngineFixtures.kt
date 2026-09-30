package com.cindy.tracker

import java.util.Locale

/**
 * Voice lists shaped like the ones real engines return, shared by the tests that choose between
 * voices and the tests that drive the engine.
 */
object EngineFixtures {

    /** An English-language phone in Britain, so its region says nothing about Spanish. */
    val britain: Locale = Locale.forLanguageTag("en-GB")

    fun voice(
        name: String,
        language: String,
        country: String = "",
        installed: Boolean = true,
        network: Boolean = false,
        quality: Int = 400,
        latency: Int = 200
    ) = EngineVoice(name, language, country, installed, network, quality, latency)

    /**
     * Google's shape: local and network voices side by side, some fetched and some not. Spanish
     * is installed; Russian is offered but has to be fetched; Polish is spoken only over the
     * network; Portuguese is not listed at all.
     */
    val google: List<EngineVoice> = listOf(
        voice("es-es-x-eea-local", "es", "ES"),
        voice("es-es-x-eea-network", "es", "ES", network = true, quality = 500, latency = 400),
        voice("es-us-x-sfb-local", "es", "US"),
        voice("es-us-x-esc-local", "es", "US", installed = false),
        voice("ru-ru-x-ruc-local", "ru", "RU", installed = false),
        voice("ru-ru-x-ruc-network", "ru", "RU", network = true),
        voice("pl-pl-x-oda-network", "pl", "PL", network = true),
        voice("en-us-x-tpd-local", "en", "US")
    )
}
