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
		Log.i(DosageAlarms.TAG, "alarm fired id=" + id);

		DosageAlarms.ensureChannel(context);

		Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
		PendingIntent open = launch == null ? null : PendingIntent.getActivity(
				context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

		Notification n = new Notification.Builder(context, DosageAlarms.CHANNEL_ID)
				.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
				.setContentTitle(title != null ? title : "Dosage")
				.setContentText(body != null ? body : "Time to take your medication")
				.setCategory(Notification.CATEGORY_REMINDER)
				.setContentIntent(open)
				.setAutoCancel(true)
				.build();

		context.getSystemService(NotificationManager.class).notify(id, n);
	}
}
