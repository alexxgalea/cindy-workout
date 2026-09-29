package com.cindy.tracker

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The reminder from alarm to notification, through the real scheduler, receiver and notifier.
 *
 * Each test gets a fresh app, so no alarm or notification leaks between them; the set-up and
 * tear-down still reset the stored state, as every Robolectric test here does.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReminderDeliveryTest {

    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val context: Context = app
    private val alarms get() = context.getSystemService(AlarmManager::class.java)!!
    private val notifications get() = context.getSystemService(NotificationManager::class.java)!!

    @Before
    fun setUp() {
        reset()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    @After
    fun tearDown() = reset()

    private fun reset() {
        Profile(context).reminderOn = false
        LiveWorkout.active = false
        RecordStore(context).clear()
    }

    private fun turnOn() {
        Profile(context).reminderOn = true
    }

    private fun fire(target: Long) {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction(ReminderReceiver.ACTION_FIRE)
            .putExtra(ReminderScheduler.EXTRA_TARGET, target)
        ReminderReceiver().onReceive(context, intent)
    }

    private fun posted() = shadowOf(notifications).allNotifications

    @Test
    fun `turning the reminder on arms one alarm at the chosen time`() {
        turnOn()
        Profile(context).reminderMinute = 18 * 60
        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.of(ZonedDateTime.now(zone).toLocalDate(), LocalTime.of(9, 0), zone)
        ReminderScheduler.sync(context, now)
        val alarm = shadowOf(alarms).peekNextScheduledAlarm()!!
        val expected = now.toLocalDate().atTime(18, 0).atZone(zone).toInstant().toEpochMilli()
        assertEquals(expected, alarm.triggerAtTime)
        assertEquals(AlarmManager.RTC_WAKEUP, alarm.type)
    }

    @Test
    fun `turning it off cancels the alarm`() {
        turnOn()
        ReminderScheduler.sync(context)
        assertNotNull(shadowOf(alarms).peekNextScheduledAlarm())
        Profile(context).reminderOn = false
        ReminderScheduler.sync(context)
        assertNull(shadowOf(alarms).peekNextScheduledAlarm())
    }

    @Test
    fun `a day with no session gets a reminder`() {
        turnOn()
        fire(System.currentTimeMillis())
        assertEquals(1, posted().size)
    }

    @Test
    fun `a day already trained stays quiet but re-arms`() {
        turnOn()
        val now = System.currentTimeMillis()
        RecordStore(context).add(Attempt(rounds = 3, reps = 4, atMillis = now))
        fire(now)
        assertEquals(0, posted().size)
        assertNotNull(shadowOf(alarms).peekNextScheduledAlarm())
    }

    @Test
    fun `a reminder hours late is dropped`() {
        turnOn()
        fire(System.currentTimeMillis() - 3 * 60 * 60 * 1000L)
        assertEquals(0, posted().size)
    }

    @Test
    fun `a live workout silences it`() {
        turnOn()
        LiveWorkout.active = true
        fire(System.currentTimeMillis())
        assertEquals(0, posted().size)
    }

    @Test
    fun `boot re-arms the reminder`() {
        turnOn()
        assertNull(shadowOf(alarms).peekNextScheduledAlarm())
        ReminderReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertNotNull(shadowOf(alarms).peekNextScheduledAlarm())
    }
}
