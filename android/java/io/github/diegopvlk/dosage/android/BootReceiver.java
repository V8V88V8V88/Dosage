package io.github.diegopvlk.dosage.android;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import java.util.Map;

/** Alarms don't survive a reboot; re-register the ones Dosage had scheduled. */
public final class BootReceiver extends BroadcastReceiver {
	@Override
	public void onReceive(Context context, Intent intent) {
		String action = intent.getAction();
		if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
				&& !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
				&& !"android.intent.action.QUICKBOOT_POWERON".equals(action))
			return;

		Context app = context.getApplicationContext();
		SharedPreferences prefs = DosageAlarms.prefs(app);
		long now = System.currentTimeMillis();
		int count = 0;
		for (Map.Entry<String, ?> e : prefs.getAll().entrySet()) {
			try {
				int id = Integer.parseInt(e.getKey());
				String[] f = String.valueOf(e.getValue()).split("\u001f", -1);
				long at = Long.parseLong(f[0]);
				if (at <= now) {
					prefs.edit().remove(e.getKey()).apply();
					continue;
				}
				DosageAlarms.schedule(app, id, at, f[1], f[2], Long.parseLong(f[3]), f[4], f[5]);
				count++;
			} catch (Exception ex) {
				Log.w(DosageAlarms.TAG, "bad alarm record " + e.getKey(), ex);
			}
		}
		Log.i(DosageAlarms.TAG, "rescheduled " + count + " alarms after " + action);
	}
}
