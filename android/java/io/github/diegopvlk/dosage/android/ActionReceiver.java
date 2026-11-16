package io.github.diegopvlk.dosage.android;

import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Confirm/Skip pressed on a reminder. Records the action for the Vala side and
 * dismisses the notification. Receiving this broadcast also starts the app process
 * if needed; Dosage applies pending actions on start and while running.
 */
public final class ActionReceiver extends BroadcastReceiver {
	@Override
	public void onReceive(Context context, Intent intent) {
		int notifId = intent.getIntExtra(DosageAlarms.EXTRA_ID, 0);
		long dateKey = intent.getLongExtra(DosageAlarms.EXTRA_DATE_KEY, 0);
		int taken = intent.getIntExtra(DosageAlarms.EXTRA_TAKEN, 1);
		Log.i(DosageAlarms.TAG, "action " + taken + " for " + dateKey);
		DosageAlarms.recordAction(context.getApplicationContext(), dateKey, taken);
		context.getSystemService(NotificationManager.class).cancel(notifId);
	}
}
