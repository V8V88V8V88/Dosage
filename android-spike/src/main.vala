// Dosage Android spike — step 4: native Android reminders.
// Goal: a reminder notification must arrive at a set time even when the app is closed.

public class SpikeWindow : Adw.ApplicationWindow {
	private Gtk.Label status_label;
	private Gtk.Button allow_button;
	private Gtk.Button battery_button;

	public SpikeWindow (Adw.Application app) {
		Object (application: app, title: "Dosage Spike",
		        default_width: 360, default_height: 640);
		// libadwaita windows default to a 360px minimum; this phone is 355px wide.
		width_request = 300;
		height_request = 294;

		var header = new Adw.HeaderBar ();

		var page = new Adw.StatusPage () {
			icon_name = "alarm-symbolic",
			title = "Reminder test",
			description = "Schedule a reminder, then close the app.\nThe notification should still arrive."
		};

		var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
			halign = Gtk.Align.CENTER
		};

		status_label = new Gtk.Label ("") {
			wrap = true,
			justify = Gtk.Justification.CENTER
		};
		status_label.add_css_class ("dim-label");

		allow_button = new Gtk.Button.with_label ("Allow notifications") {
			halign = Gtk.Align.CENTER
		};
		allow_button.add_css_class ("pill");
		allow_button.clicked.connect (() => {
#if ANDROID
			DosageAndroid.request_permissions ();
#endif
		});

		battery_button = new Gtk.Button.with_label ("Allow background (battery)") {
			halign = Gtk.Align.CENTER
		};
		battery_button.add_css_class ("pill");
		battery_button.clicked.connect (() => {
#if ANDROID
			DosageAndroid.request_battery_unrestricted ();
#endif
		});

		var remind_button = new Gtk.Button.with_label ("Remind me in 15 seconds") {
			halign = Gtk.Align.CENTER
		};
		remind_button.add_css_class ("pill");
		remind_button.add_css_class ("suggested-action");
		remind_button.clicked.connect (() => schedule_test (15));

		box.append (status_label);
		box.append (allow_button);
		box.append (battery_button);
		box.append (remind_button);
		page.child = box;

		var view = new Adw.ToolbarView ();
		view.add_top_bar (header);
		view.content = page;
		content = view;

		// Startup timing: log the first frame (should be fast once fontconfig's cache exists).
		add_tick_callback (() => {
			message ("first frame");
			return Source.REMOVE;
		});

		update_status ();
		// Refresh after returning from the permission dialog / settings page.
		notify["is-active"].connect (update_status);
	}

	private void update_status () {
#if ANDROID
		bool notify_ok = DosageAndroid.can_notify ();
		bool exact_ok = DosageAndroid.can_schedule_exact ();
		bool battery_ok = DosageAndroid.is_battery_unrestricted ();
		status_label.label = "Notifications: %s\nExact alarms: %s\nBackground: %s".printf (
			notify_ok ? "allowed" : "NOT allowed",
			exact_ok ? "allowed" : "NOT allowed (reminder may be late)",
			battery_ok ? "unrestricted" : "optimised (phone may delay reminders)");
		allow_button.visible = !(notify_ok && exact_ok);
		battery_button.visible = !battery_ok;
#else
		status_label.label = "Desktop build: uses GLib notifications";
		allow_button.visible = false;
		battery_button.visible = false;
#endif
	}

	// Local "now" in the device timezone. On Android GLib can't find tzdata and
	// DateTime.now_local() is UTC, so take the offset from Android itself.
	public static DateTime now_local () {
#if ANDROID
		var utc = new DateTime.now_utc ();
		int offset = DosageAndroid.utc_offset_seconds (utc.to_unix () * 1000);
		return utc.to_timezone (new TimeZone.offset (offset));
#else
		return new DateTime.now_local ();
#endif
	}

	private void schedule_test (int seconds) {
		var at = now_local ().add_seconds (seconds);
		string body = "Test reminder scheduled for %s".printf (at.format ("%H:%M:%S"));
#if ANDROID
		bool exact = DosageAndroid.schedule (1, at.to_unix () * 1000, "Dosage", body);
		message ("scheduled for %s (exact=%s)", at.format ("%H:%M:%S"), exact.to_string ());
		status_label.label = "Scheduled for %s%s.\nNow close the app (swipe it away).".printf (
			at.format ("%H:%M:%S"), exact ? "" : " (inexact)");
#else
		var app = (Gtk.Application) application;
		Timeout.add_seconds (seconds, () => {
			var n = new GLib.Notification ("Dosage");
			n.set_body (body);
			app.send_notification ("test", n);
			return Source.REMOVE;
		});
		status_label.label = "Scheduled for %s".printf (at.format ("%H:%M:%S"));
#endif
	}
}

public class SpikeApp : Adw.Application {
	public SpikeApp () {
		Object (application_id: "io.github.diegopvlk.Dosage.Spike",
		        flags: ApplicationFlags.DEFAULT_FLAGS);
	}

	protected override void startup () {
		base.startup ();
#if ANDROID
		message ("android bridge init: %s", DosageAndroid.init ().to_string ());
#endif
	}

	protected override void activate () {
		var win = active_window ?? new SpikeWindow (this);
		win.present ();
	}
}

public int main (string[] args) {
	message ("main() reached");
#if ANDROID
	// GTK's Android runtime doesn't set XDG_CACHE_HOME, so fontconfig can't save its
	// cache and rescans every system font (~160 MB) on each launch: ~40-60 s black screen.
	// Must happen before GTK/fontconfig initialise.
	var cache = DosageAndroid.get_cache_dir ();
	if (cache != null) {
		Environment.set_variable ("XDG_CACHE_HOME", cache, true);
		message ("XDG_CACHE_HOME=%s", cache);
	}
#endif
	return new SpikeApp ().run (args);
}
