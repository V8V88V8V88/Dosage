/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Time helpers. Dosage stores times as JS-style milliseconds since the epoch and
// ISO-8601 UTC strings, so the JSON files stay compatible with the GJS version.
namespace Dosage.Time {
	// Local timezone. On Android GLib finds no tzdata (no /etc/localtime) and would
	// use UTC, so take the device offset from Android itself.
	public GLib.TimeZone local_tz () {
#if ANDROID
		int64 now_ms = GLib.get_real_time () / 1000;
		return new GLib.TimeZone.offset (DosageAndroid.utc_offset_seconds (now_ms));
#else
		return new GLib.TimeZone.local ();
#endif
	}

	public GLib.DateTime now () {
		return new GLib.DateTime.now (local_tz ());
	}

	public int64 now_ms () {
		return GLib.get_real_time () / 1000;
	}

	public GLib.DateTime from_ms (int64 ms) {
		var utc = new GLib.DateTime.from_unix_utc (ms / 1000);
		return utc.add ((ms % 1000) * 1000).to_timezone (local_tz ());
	}

	public int64 to_ms (GLib.DateTime dt) {
		return dt.to_unix () * 1000 + dt.get_microsecond () / 1000;
	}

	// JS: new Date(x).setHours(0, 0, 0, 0)
	public GLib.DateTime start_of_day (GLib.DateTime dt) {
		var local = dt.to_timezone (local_tz ());
		return new GLib.DateTime (local_tz (), local.get_year (), local.get_month (),
		                          local.get_day_of_month (), 0, 0, 0);
	}

	public int64 day_ms (int64 ms) {
		return to_ms (start_of_day (from_ms (ms)));
	}

	public int64 today_ms () {
		return to_ms (start_of_day (now ()));
	}

	// JS: date.setHours(h, m, 0, 0)
	public GLib.DateTime at_time (GLib.DateTime day, int hour, int minute) {
		var d = start_of_day (day);
		return new GLib.DateTime (local_tz (), d.get_year (), d.get_month (),
		                          d.get_day_of_month (), hour, minute, 0);
	}

	// JS: date.getDay() -> 0 = Sunday ... 6 = Saturday
	public int weekday (GLib.DateTime dt) {
		return dt.get_day_of_week () % 7;
	}

	// JS: date.toISOString() -> "2026-11-16T04:12:15.123Z"
	public string to_iso (GLib.DateTime dt) {
		var utc = dt.to_utc ();
		return "%s.%03dZ".printf (utc.format ("%Y-%m-%dT%H:%M:%S"), utc.get_microsecond () / 1000);
	}

	public string now_iso () {
		return to_iso (now ());
	}

	public GLib.DateTime? parse_iso (string? s) {
		if (s == null) return null;
		var dt = new GLib.DateTime.from_iso8601 (s, new GLib.TimeZone.utc ());
		return dt != null ? dt.to_timezone (local_tz ()) : null;
	}

	// Days between the local dates of a and b (b - a), ignoring time of day.
	public int days_between (GLib.DateTime a, GLib.DateTime b) {
		var da = start_of_day (a);
		var db = start_of_day (b);
		var ua = new GLib.DateTime.utc (da.get_year (), da.get_month (), da.get_day_of_month (), 0, 0, 0);
		var ub = new GLib.DateTime.utc (db.get_year (), db.get_month (), db.get_day_of_month (), 0, 0, 0);
		return (int) (ub.difference (ua) / GLib.TimeSpan.DAY);
	}
}

namespace Dosage.Locale {
	private bool initialized = false;
	private string _time_format;
	private int _first_weekday;
	private int _first_work_day;

	private void init () {
		if (initialized) return;
		initialized = true;
		_time_format = "%H:%M";
		_first_weekday = 0;
		_first_work_day = 1;

#if ANDROID
		_time_format = DosageAndroid.is_24_hour () ? "%H:%M" : "%-I:%M %p";
		_first_weekday = DosageAndroid.first_day_of_week ();
		_first_work_day = (_first_weekday + 1) % 7;
#else
		string? t_fmt = locale_query ("t_fmt");
		bool is12 = t_fmt != null && ("%r" in t_fmt || "%p" in t_fmt || "%P" in t_fmt);
#if HAVE_PORTAL
		if (GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") == "GNOME") {
			try {
				var settings = new Xdp.Portal ().get_settings ();
				is12 = settings.read_string ("org.gnome.desktop.interface", "clock-format", null) == "12h";
			} catch (Error e) {
				warning ("clock-format: %s", e.message);
			}
		}
#endif
		_time_format = is12 ? "%-I:%M %p" : "%H:%M";
		if (t_fmt != null && "." in t_fmt) _time_format = _time_format.replace (":", ".");

		string? fw = locale_query ("first_weekday");
		string? fwd = locale_query ("first_workday");
		// `locale` days are 1 to 7
		if (fw != null) _first_weekday = (int.parse (fw) - 1 + 7) % 7;
		if (fwd != null) _first_work_day = (int.parse (fwd) - 1 + 7) % 7;
#endif
	}

#if !ANDROID
	private string? locale_query (string key) {
		try {
			string output;
			GLib.Process.spawn_command_line_sync ("locale " + key, out output);
			return output.strip ();
		} catch (Error e) {
			warning ("locale %s: %s", key, e.message);
			return null;
		}
	}
#endif

	public string time_format () {
		init ();
		return _time_format;
	}

	public int first_weekday () {
		init ();
		return _first_weekday;
	}

	public int first_work_day () {
		init ();
		return _first_work_day;
	}

	public bool clock_is_12 () {
		return time_format ().has_prefix ("%-I");
	}

	public bool time_dot () {
		return "." in time_format ();
	}

	// AM/PM labels for the time picker
	public string[] am_pm () {
		var am = new GLib.DateTime (Time.local_tz (), 2000, 1, 1, 9, 0, 0).format ("%p");
		var pm = new GLib.DateTime (Time.local_tz (), 2000, 1, 1, 21, 0, 0).format ("%p");
		if (am == "" || pm == "") return { "AM", "PM" };
		return { am, pm };
	}

	// getDayLabel: day 0 = Sunday
	public string day_label (int day, bool long_name = false) {
		var now = Time.now ();
		var date = now.add_days ((day - Time.weekday (now) + 7) % 7);
		string label = date.format (long_name ? "%A" : "%a");
		if (label.length == 0) return label;
		unichar first = label.get_char (0);
		return first.toupper ().to_string () + label.substring (label.index_of_nth_char (1));
	}

	// getSpecificDaysLabel
	public string specific_days_label (int[] days) {
		int[] workdays = {};
		for (int i = 0; i < 5; i++) workdays += (first_work_day () + i) % 7;
		int[] weekends = {};
		foreach (int d in new int[] { 0, 6 }) {
			bool is_work = false;
			foreach (int w in workdays) if (w == d) is_work = true;
			if (!is_work) weekends += d;
		}
		bool all_weekend = true, all_work = true;
		foreach (int d in days) {
			bool in_we = false, in_wd = false;
			foreach (int w in weekends) if (w == d) in_we = true;
			foreach (int w in workdays) if (w == d) in_wd = true;
			if (!in_we) all_weekend = false;
			if (!in_wd) all_work = false;
		}

		if (days.length == 1) return day_label (days[0], true);
		if (all_weekend && days.length == 2) return _("Weekends");
		if (all_work && days.length == 5) return _("Weekdays");
		if (days.length == 7) return _("Daily");

		string[] labels = {};
		for (int i = 0; i < 7; i++) {
			int idx = (first_weekday () + i) % 7;
			foreach (int d in days) if (d == idx) { labels += day_label (idx); break; }
		}
		return string.joinv (", ", labels);
	}

	// Long date for History sections, e.g. "Monday, Nov 16, 2026" / "Monday, 16 Nov 2026"
	public string date_format () {
		string? lc = GLib.Intl.setlocale (GLib.LocaleCategory.TIME, null);
		bool month_first = lc != null && (lc.has_prefix ("en_US") || lc.has_prefix ("en_PH") ||
		                                  lc.has_prefix ("en_CA") || lc == "C" || lc == "POSIX");
#if ANDROID
		month_first = false;
#endif
		return month_first ? "%A, %b %-e, %Y" : "%A, %-e %b %Y";
	}

	public string format_date (int64 ms) {
		return Time.from_ms (ms).format ("%x");
	}

	public string format_time (int hour, int minute) {
		var dt = new GLib.DateTime (Time.local_tz (), 2000, 1, 1, hour, minute, 0);
		return dt.format (time_format ());
	}
}

namespace Dosage.Touch {
	// On Android a tap on a button inside an Adw.ActionRow also activates the row. If
	// the row's activatable widget is that same popover button, the popover opens and
	// immediately closes (toggled twice); for spin rows, activation moves focus away
	// and closes it. Let the buttons handle taps alone (desktop is unaffected).
	public void fix_rows (Gtk.Widget root) {
#if ANDROID
		for (var child = root.get_first_child (); child != null; child = child.get_next_sibling ()) {
			var row = child as Adw.ActionRow;
			if (row != null && row.activatable_widget is Gtk.MenuButton) row.activatable_widget = null;
			if (child is Adw.SpinRow) ((Adw.SpinRow) child).activatable = false;
			fix_rows (child);
		}
#endif
	}
}

namespace Dosage.Haptics {
	// Android: vibrate for every interaction with stock GTK/libadwaita widgets, so all
	// buttons, switches, checks, rows and lists feel the same (signal emission hooks).
	public void install () {
#if ANDROID
		hook (typeof (Gtk.Button), "clicked", 1);       // incl. toggle/menu/view-switcher buttons
		hook (typeof (Gtk.CheckButton), "toggled", 0);
		hook (typeof (Gtk.Switch), "state-set", 0);
		hook (typeof (Adw.ButtonRow), "activated", 1);
		hook (typeof (Adw.ActionRow), "activated", 0);   // combo/expander rows, etc.
		hook (typeof (Gtk.ListView), "activate", 0);
#endif
	}

#if ANDROID
	private int64 last_us = 0;

	private void hook (Type type, string signal_name, int kind) {
		// make sure the class is initialised so the signal exists
		type.class_ref ();
		uint id = GLib.Signal.lookup (signal_name, type);
		if (id == 0) return;
		GLib.Signal.add_emission_hook (id, 0, (ihint, values) => {
			// one buzz per interaction (a click can emit several hooked signals)
			int64 now = GLib.get_monotonic_time ();
			if (now - last_us > 60000) DosageAndroid.haptic (kind);
			last_us = now;
			return true;
		});
	}
#endif

	public void tick () {
#if ANDROID
		DosageAndroid.haptic (0);
#endif
	}

	public void click () {
#if ANDROID
		DosageAndroid.haptic (1);
#endif
	}
}

namespace Dosage {
	public string lead_zero (int n) {
		return "%02d".printf (n);
	}

	// JS Number -> string, e.g. 1 -> "1", 0.25 -> "0.25"
	public string format_number (double n) {
		if (n == Math.floor (n) && n.abs () < 1e15) return "%lld".printf ((int64) n);
		var s = "%.2f".printf (n);
		while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
		if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
		return s;
	}

	// treatmentsSorter.js: comparison for the "treatments-sorting" setting
	public int compare_treatments (Treatment a, Treatment b, string sorting) {
		int64 today = Time.today_ms ();
		switch (sorting) {
			case "amount-remaining-less":
			case "amount-remaining-more":
				if (a.inv_enabled != b.inv_enabled) return a.inv_enabled ? -1 : 1;
				if (a.inv_enabled && a.inv_current != b.inv_current) {
					int r = a.inv_current < b.inv_current ? -1 : 1;
					return sorting == "amount-remaining-less" ? r : -r;
				}
				break;
			case "when-needed-last":
				if (a.is_when_needed != b.is_when_needed) return a.is_when_needed ? 1 : -1;
				break;
			case "ended-last":
			case "when-needed-ended-last":
				bool ended_a = !a.is_when_needed && a.dur_enabled && Time.day_ms (a.dur_end) < today;
				bool ended_b = !b.is_when_needed && b.dur_enabled && Time.day_ms (b.dur_end) < today;
				if (ended_a != ended_b) return ended_a ? 1 : -1;
				if (sorting == "when-needed-ended-last" && a.is_when_needed != b.is_when_needed)
					return a.is_when_needed ? 1 : -1;
				break;
		}
		return a.name.collate (b.name);
	}

	// Sections for the Today list: one per time, "as needed" items first.
	public class TodaySectionSorter : Gtk.Sorter {
		protected override Gtk.Ordering compare (Object? a, Object? b) {
			var ia = (TodayItem) a;
			var ib = (TodayItem) b;
			int ka = ia.when_needed ? -1 : ia.hour * 60 + ia.minute;
			int kb = ib.when_needed ? -1 : ib.hour * 60 + ib.minute;
			return Gtk.Ordering.from_cmpfunc (ka < kb ? -1 : (ka > kb ? 1 : 0));
		}

		protected override Gtk.SorterOrder get_order () {
			return Gtk.SorterOrder.PARTIAL;
		}
	}

	// Sections for the History list: one per day, newest first.
	public class HistorySectionSorter : Gtk.Sorter {
		protected override Gtk.Ordering compare (Object? a, Object? b) {
			int64 da = Time.day_ms (((HistoryEntry) a).taken_at);
			int64 db = Time.day_ms (((HistoryEntry) b).taken_at);
			return Gtk.Ordering.from_cmpfunc (da == db ? 0 : (da < db ? 1 : -1));
		}

		protected override Gtk.SorterOrder get_order () {
			return Gtk.SorterOrder.PARTIAL;
		}
	}
}
