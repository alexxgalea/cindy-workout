package com.cindy.tracker

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.ZonedDateTime

/**
 * Keeps exactly one alarm armed for the next reminder, or none.
 *
 * setWindow rather than an exact alarm: exact alarms need a permission Android 14 denies by
 * default, and plain set() may drift by up to three quarters of the time until it is due — hours,
 * for an alarm armed a day ahead. A fifteen-minute window is precise enough for a nudge.
 */
object ReminderScheduler {
    const val EXTRA_TARGET = "com.cindy.tracker.reminder.TARGET"
    private const val REQUEST_CODE = 4101
    private const val WINDOW_MS = 15 * 60 * 1000L

    fun sync(context: Context, now: ZonedDateTime = ZonedDateTime.now()) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val profile = Profile(context)
        if (!profile.reminderOn) {
            alarms.cancel(pending(context, 0L))
            return
        }
        val target = Reminder.nextFire(now, profile.reminderMinute).toInstant().toEpochMilli()
        alarms.setWindow(AlarmManager.RTC_WAKEUP, target, WINDOW_MS, pending(context, target))
    }

    /**
     * Re-arms only when nothing is armed: a force-stop or a reboot clears alarms, but an alarm that
     * is merely waiting out its window must be left alone or opening the app would postpone it.
     */
    fun ensureArmed(context: Context, now: ZonedDateTime = ZonedDateTime.now()) {
        if (!Profile(context).reminderOn) return
        if (isArmed(context)) return
        sync(context, now)
    }

    /** FLAG_NO_CREATE finds a match on component, action and request code; extras are ignored. */
    private fun isArmed(context: Context): Boolean =
        PendingIntent.getBroadcast(
            context, REQUEST_CODE, fireIntent(context, 0L),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        ) != null

    private fun fireIntent(context: Context, target: Long): Intent =
        Intent(context, ReminderReceiver::class.java)
            .setAction(ReminderReceiver.ACTION_FIRE)
            .putExtra(EXTRA_TARGET, target)

    /** One request code, so every arm replaces the last and cancel finds it whatever its extras. */
    private fun pending(context: Context, target: Long): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            fireIntent(context, target),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
}
