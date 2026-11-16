/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Reminder text shared by both platforms, and Android's alarm scheduling.
// Desktop scheduling (in-process timers + GNotification) lives in the window,
// like in the GJS version, because it needs the running app for its actions.

namespace Dosage.Reminders {
	// Doses due at the same time are notified together.
	public class Group : Object {
		public int64 date_key; // ms of the due time
		public int hour;
		public int minute;
		public GenericArray<TodayItem> items = new GenericArray<TodayItem> ();

		public bool increase_priority () {
			for (int i = 0; i < int.min (items.length, 3); i++)
				if (items[i].treatment.increase_priority) return true;
			return false;
		}

		// smallest recurring interval among the group, or -1 if none recurs
		public int recurring_interval () {
			int interval = 99;
			bool enabled = false;
			foreach (var it in items) {
				if (it.treatment.recurring_enabled) {
					enabled = true;
					interval = int.min (interval, it.treatment.recurring_interval);
				}
			}
			return enabled ? interval : -1;
		}
	}

	public string title (Group g) {
		return _("Reminder") + " · " + Locale.format_time (g.hour, g.minute);
	}

	public string body (Group g) {
		const int MAX = 3;
		var lines = new string[0];
		var names = new string[0];
		for (int i = 0; i < int.min (g.items.length, MAX); i++) {
			var it = g.items[i];
			lines += "%s ⸱ %s %s".printf (it.name, format_number (it.dose), it.unit);
			names += it.name;
		}
		if (g.items.length > MAX) {
			int more = g.items.length - MAX;
			// TRANSLATORS: %d is a placeholder for the number of collapsed treatments in a notification
			return string.joinv (", ", names) + " " + ngettext ("and %d more", "and %d more", more).printf (more);
		}
		return string.joinv ("\n\r", lines);
	}

#if ANDROID
	// Android kills background apps, so in-process timers would never fire. Reminders
	// are AlarmManager alarms owned by the system (see android/java). We schedule
	// today's remaining doses plus the next days, so reminders keep coming even if
	// the app isn't opened; every app start/change reschedules everything.
	private const int DAYS_AHEAD = 2;
	private const int MAX_REPEATS = 12;

	private GLib.File ids_file () {
		return GLib.File.new_for_path (GLib.Environment.get_user_cache_dir ()).get_child ("scheduled-alarms");
	}

	private void cancel_previous () {
		try {
			uint8[] data;
			ids_file ().load_contents (null, out data, null);
			foreach (var line in ((string) data).split ("\n"))
				if (line.strip () != "") DosageAndroid.cancel (int.parse (line));
		} catch (Error e) {
			// nothing scheduled yet
		}
	}

	private void save_ids (int[] ids) {
		var sb = new StringBuilder ();
		foreach (var id in ids) sb.append_printf ("%d\n", id);
		try {
			ids_file ().replace_contents (sb.str.data, null, false, GLib.FileCreateFlags.NONE, null);
		} catch (Error e) {
			warning ("save alarm ids: %s", e.message);
		}
	}

	// Doses due on a future day (offset >= 1), grouped by time.
	private GenericArray<Group> future_groups (GLib.ListStore treatments, int offset) {
		var day = Time.now ().add_days (offset);
		var by_key = new HashTable<int64?, Group> (int64_hash, int64_equal);
		var result = new GenericArray<Group> ();

		for (uint i = 0; i < treatments.get_n_items (); i++) {
			var t = (Treatment) treatments.get_item (i);
			if (t.is_when_needed || !is_med_day_ahead (t, day, offset)) continue;
			foreach (var td in t.dosage) {
				int64 key = Time.to_ms (Time.at_time (day, td.hour, td.minute));
				var g = by_key.lookup (key);
				if (g == null) {
					g = new Group () { date_key = key, hour = td.hour, minute = td.minute };
					by_key.insert (key, g);
					result.add (g);
				}
				g.items.add (new TodayItem (t, td.hour, td.minute, td.dose, false));
			}
		}
		return result;
	}

	// Like Treatment.is_med_day, but advances the cycle position by `offset` days.
	private bool is_med_day_ahead (Treatment t, GLib.DateTime day, int offset) {
		if (t.frequency != "cycle") return t.is_med_day (day);
		int64 d = Time.to_ms (Time.start_of_day (day));
		if (t.dur_enabled && (Time.day_ms (t.dur_start) > d || Time.day_ms (t.dur_end) < d)) return false;
		int active = t.cycle[0], inactive = t.cycle[1], current = t.cycle[2];
		for (int i = 0; i < offset; i++) {
			current += 1;
			if (current > active + inactive) current = 1;
		}
		return current <= active;
	}

	public void schedule_android (GenericArray<Group> today_groups, GLib.ListStore treatments) {
		cancel_previous ();
		var ids = new int[0];
		int64 now = Time.now_ms ();

		var all = new GenericArray<Group> ();
		foreach (var g in today_groups) all.add (g);
		for (int offset = 1; offset <= DAYS_AHEAD; offset++)
			foreach (var g in future_groups (treatments, offset)) all.add (g);

		foreach (var g in all) {
			// stable id per day+time; day index relative to today
			int day_index = Time.days_between (Time.now (), Time.from_ms (g.date_key));
			int base_id = 10000 + day_index * 1440 + g.hour * 60 + g.minute;
			string title = title (g), body = body (g);
			int interval = g.recurring_interval ();

			// repeats only for today (Android caps apps at 500 alarms); later days
			// get rescheduled with repeats when the app runs on that day
			int repeats = (interval > 0 && day_index == 0) ? MAX_REPEATS : 0;
			for (int k = 0; k <= repeats; k++) {
				int64 at = g.date_key + (int64) k * interval * 60000;
				if (at <= now) continue; // past ones are visible on the Today page
				int id = base_id + k * 100000;
				DosageAndroid.schedule (id, at, title, body);
				ids += id;
			}
		}
		save_ids (ids);
		message ("scheduled %d Android reminders", ids.length);
	}
#endif
}
