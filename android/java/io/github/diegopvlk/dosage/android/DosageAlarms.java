package io.github.diegopvlk.dosage.android;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.Application;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Native Android reminder plumbing for Dosage, called from the GTK thread over JNI.
 *
 * GTK's Android backend has no notifications or alarms, and the GTK process may be
 * killed at any time, so reminders are owned by Android:
 *  - AlarmManager wakes {@link AlarmReceiver}, which posts the notification itself;
 *  - Confirm/Skip buttons go to {@link ActionReceiver}, which records the action in
 *    files/notification-actions for the Vala side to apply (it watches that file);
 *  - every scheduled alarm is also kept in SharedPreferences so {@link BootReceiver}
 *    can re-register them after a reboot without starting GTK.
 */
public final class DosageAlarms {
	static final String TAG = "DosageAlarms";
	static final String CHANNEL_ID = "reminders";
	static final String CHANNEL_STOCK = "stock";
	static final String PREFS = "dosage-alarms";
	static final String ACTIONS_FILE = "notification-actions";

	static final String EXTRA_ID = "id";
	static final String EXTRA_TITLE = "title";
	static final String EXTRA_BODY = "body";
	static final String EXTRA_DATE_KEY = "date_key";
	static final String EXTRA_CONFIRM = "confirm_label";
	static final String EXTRA_SKIP = "skip_label";
	static final String EXTRA_TAKEN = "taken";

	private static Activity currentActivity;
	private static boolean callbacksRegistered;

	private DosageAlarms() {}

	/** Create the notification channels and start tracking the foreground activity. */
	public static synchronized void init(Context context) {
		Context app = context.getApplicationContext();
		ensureChannels(app);
		if (!callbacksRegistered && app instanceof Application) {
			((Application) app).registerActivityLifecycleCallbacks(new ActivityTracker());
			callbacksRegistered = true;
		}
	}

	static void ensureChannels(Context context) {
		NotificationManager nm = context.getSystemService(NotificationManager.class);
		if (nm.getNotificationChannel(CHANNEL_ID) == null) {
			NotificationChannel ch = new NotificationChannel(
					CHANNEL_ID, "Medication reminders", NotificationManager.IMPORTANCE_HIGH);
			ch.setDescription("Reminders to take your medication");
			ch.enableVibration(true);
			nm.createNotificationChannel(ch);
		}
		if (nm.getNotificationChannel(CHANNEL_STOCK) == null) {
			NotificationChannel ch = new NotificationChannel(
					CHANNEL_STOCK, "Low stock", NotificationManager.IMPORTANCE_DEFAULT);
			ch.setDescription("When a treatment is running low");
			nm.createNotificationChannel(ch);
		}
	}

	// --- permissions ------------------------------------------------------------------

	public static boolean canNotify(Context context) {
		if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
				Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
			return false;
		return context.getSystemService(NotificationManager.class).areNotificationsEnabled();
	}

	public static boolean canScheduleExact(Context context) {
		return context.getSystemService(AlarmManager.class).canScheduleExactAlarms();
	}

	/** Ask for POST_NOTIFICATIONS and, if needed, open the exact-alarm settings page. */
	public static void requestPermissions(Context context) {
		final Context app = context.getApplicationContext();
		new Handler(Looper.getMainLooper()).post(() -> {
			Activity activity = currentActivity;
			if (Build.VERSION.SDK_INT >= 33 && !canNotify(app) && activity != null) {
				activity.requestPermissions(
						new String[] { Manifest.permission.POST_NOTIFICATIONS }, 1001);
			}
			if (!canScheduleExact(app)) {
				Intent intent = new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
						Uri.parse("package:" + app.getPackageName()));
				intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
				(activity != null ? activity : app).startActivity(intent);
			}
		});
	}

	/** True if the app is exempt from battery optimisation ("Unrestricted"). */
	public static boolean isBatteryUnrestricted(Context context) {
		PowerManager pm = context.getSystemService(PowerManager.class);
		return pm.isIgnoringBatteryOptimizations(context.getPackageName());
	}

	/** Show Android's "let app run in background" prompt. */
	public static void requestBatteryUnrestricted(Context context) {
		final Context app = context.getApplicationContext();
		new Handler(Looper.getMainLooper()).post(() -> {
			if (isBatteryUnrestricted(app)) return;
			Activity activity = currentActivity;
			Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
					Uri.parse("package:" + app.getPackageName()));
			if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			(activity != null ? activity : app).startActivity(intent);
		});
	}

	// --- misc -----------------------------------------------------------------------

	/** Haptic feedback: 0 = tick (selection), 1 = click (action), 2 = heavy click. */
	public static void haptic(Context context, int kind) {
		Vibrator v = context.getSystemService(Vibrator.class);
		if (v == null || !v.hasVibrator()) return;
		int effect = kind == 0 ? VibrationEffect.EFFECT_TICK
				: kind == 2 ? VibrationEffect.EFFECT_HEAVY_CLICK
				: VibrationEffect.EFFECT_CLICK;
		v.vibrate(VibrationEffect.createPredefined(effect));
	}

	/** Device language as a POSIX locale for gettext, e.g. "pt_BR". */
	public static String posixLocale() {
		java.util.Locale l = java.util.Locale.getDefault();
		String country = l.getCountry();
		return country.isEmpty() ? l.getLanguage() : l.getLanguage() + "_" + country;
	}

	// --- reminders -----------------------------------------------------------------------

	/**
	 * Schedule a reminder notification. dateKey identifies the dose group (due time in
	 * ms) for the Confirm/Skip buttons; empty labels hide those buttons.
	 *
	 * @return true if scheduled exactly, false if Android only allowed an inexact alarm.
	 */
	public static boolean schedule(Context context, int id, long triggerAtMillis, String title,
	                               String body, long dateKey, String confirmLabel, String skipLabel) {
		Context app = context.getApplicationContext();
		ensureChannels(app);
		Intent intent = alarmIntent(app, id)
				.putExtra(EXTRA_TITLE, title)
				.putExtra(EXTRA_BODY, body)
				.putExtra(EXTRA_DATE_KEY, dateKey)
				.putExtra(EXTRA_CONFIRM, confirmLabel)
				.putExtra(EXTRA_SKIP, skipLabel);
		boolean exact = register(app, id, triggerAtMillis, intent);

		// remember it for BootReceiver
		String record = triggerAtMillis + "\u001f" + title + "\u001f" + body + "\u001f" + dateKey
				+ "\u001f" + confirmLabel + "\u001f" + skipLabel;
		prefs(app).edit().putString(String.valueOf(id), record).apply();
		return exact;
	}

	static boolean register(Context app, int id, long triggerAtMillis, Intent intent) {
		AlarmManager am = app.getSystemService(AlarmManager.class);
		PendingIntent pi = PendingIntent.getBroadcast(app, id, intent,
				PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
		boolean exact = am.canScheduleExactAlarms();
		if (exact) {
			// setAlarmClock: highest priority, never deferred, honoured by OEM battery
			// managers (ColorOS froze the app and delayed setExactAndAllowWhileIdle).
			am.setAlarmClock(new AlarmManager.AlarmClockInfo(triggerAtMillis, launchIntent(app, 0)), pi);
		} else {
			am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi);
		}
		return exact;
	}

	public static void cancel(Context context, int id) {
		Context app = context.getApplicationContext();
		PendingIntent pi = PendingIntent.getBroadcast(app, id, alarmIntent(app, id),
				PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
		app.getSystemService(AlarmManager.class).cancel(pi);
		prefs(app).edit().remove(String.valueOf(id)).apply();
	}

	/** Post a notification right away (e.g. low stock). */
	public static void notifyNow(Context context, int id, String title, String body) {
		Context app = context.getApplicationContext();
		ensureChannels(app);
		Notification n = new Notification.Builder(app, CHANNEL_STOCK)
				.setSmallIcon(android.R.drawable.ic_dialog_info)
				.setContentTitle(title)
				.setContentText(body)
				.setContentIntent(launchIntent(app, id))
				.setAutoCancel(true)
				.build();
		app.getSystemService(NotificationManager.class).notify(id, n);
	}

	public static void withdraw(Context context, int id) {
		context.getApplicationContext().getSystemService(NotificationManager.class).cancel(id);
	}

	static Intent alarmIntent(Context app, int id) {
		return new Intent(app, AlarmReceiver.class).putExtra(EXTRA_ID, id);
	}

	static PendingIntent launchIntent(Context app, int requestCode) {
		Intent launch = app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
		if (launch == null) return null;
		return PendingIntent.getActivity(app, requestCode, launch,
				PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
	}

	static SharedPreferences prefs(Context app) {
		return app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
	}

	/** Append "dateKey,taken" for the Vala side (see ActionReceiver). */
	static synchronized void recordAction(Context app, long dateKey, int taken) {
		File f = new File(app.getFilesDir(), ACTIONS_FILE);
		try (FileOutputStream out = new FileOutputStream(f, true)) {
			out.write((dateKey + "," + taken + "\n").getBytes(StandardCharsets.UTF_8));
		} catch (Exception e) {
			Log.e(TAG, "recordAction", e);
		}
	}

	private static final class ActivityTracker implements Application.ActivityLifecycleCallbacks {
		@Override public void onActivityResumed(Activity a) { currentActivity = a; }
		@Override public void onActivityPaused(Activity a) { if (currentActivity == a) currentActivity = null; }
		@Override public void onActivityCreated(Activity a, Bundle b) {}
		@Override public void onActivityStarted(Activity a) {}
		@Override public void onActivityStopped(Activity a) {}
		@Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
		@Override public void onActivityDestroyed(Activity a) {}
	}
}
