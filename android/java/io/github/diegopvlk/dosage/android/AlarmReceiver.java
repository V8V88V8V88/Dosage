package io.github.diegopvlk.dosage.android;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/** Fired by AlarmManager; posts the reminder without needing the GTK UI. */
public final class AlarmReceiver extends BroadcastReceiver {
	@Override
	public void onReceive(Context context, Intent intent) {
		int id = intent.getIntExtra(DosageAlarms.EXTRA_ID, 0);
		String title = intent.getStringExtra(DosageAlarms.EXTRA_TITLE);
		String body = intent.getStringExtra(DosageAlarms.EXTRA_BODY);
		long dateKey = intent.getLongExtra(DosageAlarms.EXTRA_DATE_KEY, 0);
		String confirm = intent.getStringExtra(DosageAlarms.EXTRA_CONFIRM);
		String skip = intent.getStringExtra(DosageAlarms.EXTRA_SKIP);
		Log.i(DosageAlarms.TAG, "alarm fired id=" + id);

		DosageAlarms.ensureChannels(context);
		DosageAlarms.prefs(context).edit().remove(String.valueOf(id)).apply();

		// one notification per dose group, so repeats replace instead of stacking
		int notifId = (int) (dateKey / 60000 % 1000000);

		Notification.Builder b = new Notification.Builder(context, DosageAlarms.CHANNEL_ID)
				.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
				.setContentTitle(title != null ? title : "Dosage")
				.setContentText(body != null ? body : "")
				.setStyle(new Notification.BigTextStyle().bigText(body))
				.setCategory(Notification.CATEGORY_REMINDER)
				.setContentIntent(DosageAlarms.launchIntent(context, notifId))
				.setAutoCancel(true);

		if (confirm != null && !confirm.isEmpty())
			b.addAction(new Notification.Action.Builder(null, confirm,
					actionIntent(context, notifId, dateKey, 1)).build());
		if (skip != null && !skip.isEmpty())
			b.addAction(new Notification.Action.Builder(null, skip,
					actionIntent(context, notifId, dateKey, 0)).build());

		context.getSystemService(NotificationManager.class).notify(notifId, b.build());
	}

	private static PendingIntent actionIntent(Context context, int notifId, long dateKey, int taken) {
		Intent i = new Intent(context, ActionReceiver.class)
				.putExtra(DosageAlarms.EXTRA_ID, notifId)
				.putExtra(DosageAlarms.EXTRA_DATE_KEY, dateKey)
				.putExtra(DosageAlarms.EXTRA_TAKEN, taken);
		return PendingIntent.getBroadcast(context, notifId * 2 + taken, i,
				PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
	}
}
