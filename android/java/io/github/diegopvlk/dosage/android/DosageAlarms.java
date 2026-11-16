package io.github.diegopvlk.dosage.android;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.Application;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
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

/**
 * Native Android reminder plumbing for Dosage, called from the GTK thread over JNI.
 *
 * GTK's Android backend has no notification/alarm support and the GTK process
 * may be killed at any time, so reminders are owned by Android: AlarmManager
 * wakes {@link AlarmReceiver}, which posts the notification itself.
 */
public final class DosageAlarms {
	static final String TAG = "DosageAlarms";
	static final String CHANNEL_ID = "reminders";
	static final String EXTRA_ID = "id";
	static final String EXTRA_TITLE = "title";
	static final String EXTRA_BODY = "body";

	private static Activity currentActivity;
	private static boolean callbacksRegistered;

	private DosageAlarms() {}

	/** Create the notification channel and start tracking the foreground activity. */
	public static synchronized void init(Context context) {
		Context app = context.getApplicationContext();
		ensureChannel(app);
		if (!callbacksRegistered && app instanceof Application) {
			((Application) app).registerActivityLifecycleCallbacks(new ActivityTracker());
			callbacksRegistered = true;
		}
	}

	static void ensureChannel(Context context) {
		NotificationManager nm = context.getSystemService(NotificationManager.class);
		if (nm.getNotificationChannel(CHANNEL_ID) != null) return;
		NotificationChannel channel = new NotificationChannel(
				CHANNEL_ID, "Medication reminders", NotificationManager.IMPORTANCE_HIGH);
		channel.setDescription("Reminders to take your medication");
		channel.enableVibration(true);
		nm.createNotificationChannel(channel);
	}

	public static boolean canNotify(Context context) {
		if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
				Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
			return false;
		return context.getSystemService(NotificationManager.class).areNotificationsEnabled();
	}

	public static boolean canScheduleExact(Context context) {
		return context.getSystemService(AlarmManager.class).canScheduleExactAlarms();
	}

	/** Haptic feedback: 0 = tick (selection), 1 = click (action), 2 = heavy click. */
	public static void haptic(Context context, int kind) {
		Vibrator v = context.getSystemService(Vibrator.class);
		if (v == null || !v.hasVibrator()) return;
		int effect = kind == 0 ? VibrationEffect.EFFECT_TICK
				: kind == 2 ? VibrationEffect.EFFECT_HEAVY_CLICK
				: VibrationEffect.EFFECT_CLICK;
		v.vibrate(VibrationEffect.createPredefined(effect));
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

	/**
	 * Schedule a reminder. Survives the app being closed (not a reboot: that needs a
	 * BOOT_COMPLETED receiver that reschedules from Dosage's data).
	 *
	 * @return true if scheduled as an exact alarm, false if Android only allowed an inexact one.
	 */
	public static boolean schedule(Context context, int id, long triggerAtMillis,
	                               String title, String body) {
		Context app = context.getApplicationContext();
		ensureChannel(app);
		AlarmManager am = app.getSystemService(AlarmManager.class);
		PendingIntent pi = pendingIntent(app, id, title, body);
		boolean exact = am.canScheduleExactAlarms();
		if (exact) {
			// setAlarmClock is the highest-priority alarm type (what clock apps use):
			// never batched/deferred, exempt from Doze, and OEM battery managers
			// (ColorOS, MIUI...) honour it. setExactAndAllowWhileIdle got a ~45 s
			// window and a frozen process on OnePlus.
			Intent launch = app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
			PendingIntent show = launch == null ? null : PendingIntent.getActivity(
					app, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
			am.setAlarmClock(new AlarmManager.AlarmClockInfo(triggerAtMillis, show), pi);
		} else {
			am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi);
		}
		Log.i(TAG, "scheduled id=" + id + " at=" + triggerAtMillis + " exact=" + exact);
		return exact;
	}

	public static void cancel(Context context, int id) {
		Context app = context.getApplicationContext();
		app.getSystemService(AlarmManager.class).cancel(pendingIntent(app, id, null, null));
	}

	private static PendingIntent pendingIntent(Context app, int id, String title, String body) {
		Intent intent = new Intent(app, AlarmReceiver.class)
				.putExtra(EXTRA_ID, id)
				.putExtra(EXTRA_TITLE, title)
				.putExtra(EXTRA_BODY, body);
		return PendingIntent.getBroadcast(app, id, intent,
				PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
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
