package com.cindy.tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * The reminder alarm, and the system events that wipe or skew it.
 *
 * Not exported: only this app's own PendingIntent and the system can reach it, and the system's
 * broadcasts are delivered to unexported receivers.
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_FIRE) {
            deliver(context, intent.getLongExtra(ReminderScheduler.EXTRA_TARGET, 0L))
        }
        // Every path re-arms: after a fire for tomorrow, after boot, an update or a clock change
        // for whatever is next in the athlete's own time zone.
        ReminderScheduler.sync(context)
    }

    private fun deliver(context: Context, target: Long) {
        val zone = ZoneId.systemDefault()
        if (!Profile(context).reminderOn || LiveWorkout.active) return
        if (!Reminder.shouldPost(target, System.currentTimeMillis())) return
        val message = Reminder.message(
            RecordStore(context).all(), LocalDate.now(zone), zone,
            WeekFields.of(Locale.getDefault()).firstDayOfWeek
        ) ?: return
        ReminderNotifier.post(context, message)
    }

    companion object {
        const val ACTION_FIRE = "com.cindy.tracker.reminder.FIRE"
    }
}
