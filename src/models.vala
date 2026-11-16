/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Data model. JSON layout matches the GJS version exactly so
// dosage-treatments.json / dosage-history.json stay interchangeable.

namespace Dosage {
	public errordomain DataError {
		INVALID
	}

	// --- JSON helpers -------------------------------------------------------

	namespace J {
		internal Json.Node number (double n) {
			var node = new Json.Node (Json.NodeType.VALUE);
			// JSON.stringify writes integers without a fraction
			if (n == Math.floor (n) && n.abs () < 1e15) node.set_int ((int64) n);
			else node.set_double (n);
			return node;
		}

		internal bool is_number (Json.Object o, string key) {
			if (!o.has_member (key)) return false;
			var n = o.get_member (key);
			if (n.get_node_type () != Json.NodeType.VALUE) return false;
			var t = n.get_value_type ();
			return t == typeof (int64) || t == typeof (double);
		}

		internal bool is_string (Json.Object o, string key) {
			if (!o.has_member (key)) return false;
			var n = o.get_member (key);
			return n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (string);
		}

		internal bool is_bool (Json.Object o, string key) {
			if (!o.has_member (key)) return false;
			var n = o.get_member (key);
			return n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (bool);
		}

		internal bool is_object (Json.Object o, string key) {
			return o.has_member (key) && o.get_member (key).get_node_type () == Json.NodeType.OBJECT;
		}

		internal bool is_number_array (Json.Object o, string key, int exact_len = -1) {
			if (!o.has_member (key) || o.get_member (key).get_node_type () != Json.NodeType.ARRAY) return false;
			var arr = o.get_array_member (key);
			if (exact_len >= 0 && arr.get_length () != exact_len) return false;
			for (uint i = 0; i < arr.get_length (); i++) {
				var n = arr.get_element (i);
				if (n.get_node_type () != Json.NodeType.VALUE) return false;
				var t = n.get_value_type ();
				if (t != typeof (int64) && t != typeof (double)) return false;
			}
			return true;
		}

		internal double num (Json.Object o, string key) {
			return o.get_member (key).get_double ();
		}

		internal int[] int_array (Json.Array arr) {
			int[] r = {};
			for (uint i = 0; i < arr.get_length (); i++) r += (int) arr.get_element (i).get_double ();
			return r;
		}

		internal Json.Array to_array (int[] values) {
			var arr = new Json.Array ();
			foreach (var v in values) arr.add_element (number (v));
			return arr;
		}

		internal string to_string (Json.Node node) {
			var gen = new Json.Generator ();
			gen.set_root (node);
			return gen.to_data (null);
		}
	}

	// --- Treatment ------------------------------------------------------------

	public class TimeDose : Object {
		public int hour;
		public int minute;
		public double dose;
		public string? last_taken; // ISO-8601 UTC or null

		public TimeDose (int hour, int minute, double dose) {
			this.hour = hour;
			this.minute = minute;
			this.dose = dose;
		}
	}

	public class Treatment : Object {
		public string name;
		public string unit;
		public string notes;
		public string frequency; // daily, specific-days, day-of-month, cycle, when-needed
		public string color;
		public string icon;
		public int[] days;        // 0 = Sunday
		public bool has_month_day;
		public int month_day;
		public int[] cycle;       // [active, inactive, current]
		public GenericArray<TimeDose> dosage = new GenericArray<TimeDose> ();
		public bool increase_priority;
		public bool recurring_enabled;
		public int recurring_interval;
		public bool inv_enabled;
		public double inv_current;
		public double inv_reminder;
		public double inv_refill;
		public bool dur_enabled;
		public int64 dur_start;   // ms
		public int64 dur_end;     // ms
		public string? cycle_next_date;
		public bool mark_confirmed;

		// JS: it.notify('obj') — tells list rows to refresh
		public signal void changed ();

		public bool is_when_needed {
			get { return frequency == "when-needed"; }
		}

		// isValidTreatmentItem
		public static Treatment from_json (Json.Object o) throws DataError {
			bool ok =
				J.is_string (o, "name") && o.get_string_member ("name").strip () != "" &&
				J.is_string (o, "unit") && o.get_string_member ("unit").strip () != "" &&
				J.is_string (o, "notes") &&
				J.is_string (o, "frequency") && o.get_string_member ("frequency") != "" &&
				J.is_string (o, "color") && o.get_string_member ("color") != "" &&
				J.is_string (o, "icon") && o.get_string_member ("icon") != "" &&
				J.is_number_array (o, "days") &&
				J.is_number_array (o, "cycle") && o.get_array_member ("cycle").get_length () > 0 &&
				o.has_member ("dosage") && o.get_member ("dosage").get_node_type () == Json.NodeType.ARRAY &&
				o.get_array_member ("dosage").get_length () > 0 &&
				J.is_bool (o, "markConfirmed") &&
				J.is_object (o, "notification") &&
				J.is_object (o, "inventory") &&
				J.is_object (o, "duration");

			if (ok) {
				string freq = o.get_string_member ("frequency");
				if (freq == "specific-days" && o.get_array_member ("days").get_length () == 0) ok = false;
				if (freq == "day-of-month" && !J.is_number (o, "monthDay")) ok = false;
				if (freq == "cycle" && !J.is_string (o, "cycleNextDate")) ok = false;

				var notif = o.get_object_member ("notification");
				ok = ok && J.is_bool (notif, "increasePriority") && J.is_object (notif, "recurring");
				if (ok) {
					var rec = notif.get_object_member ("recurring");
					ok = J.is_bool (rec, "enabled") && J.is_number (rec, "interval");
				}
				var inv = o.get_object_member ("inventory");
				ok = ok && J.is_bool (inv, "enabled") && J.is_number (inv, "current") &&
					J.is_number (inv, "reminder") && J.is_number (inv, "refill");
				var dur = o.get_object_member ("duration");
				ok = ok && J.is_bool (dur, "enabled") && J.is_number (dur, "start") && J.is_number (dur, "end");

				o.get_array_member ("dosage").foreach_element ((arr, i, node) => {
					if (node.get_node_type () != Json.NodeType.OBJECT) { ok = false; return; }
					var d = node.get_object ();
					bool last_ok = d.has_member ("lastTaken") &&
						(d.get_member ("lastTaken").is_null () || J.is_string (d, "lastTaken"));
					if (!J.is_number_array (d, "time", 2) || !J.is_number (d, "dose") || !last_ok) ok = false;
				});
			}

			if (!ok) {
				var node = new Json.Node (Json.NodeType.OBJECT);
				node.set_object (o);
				throw new DataError.INVALID ("Invalid treatment item\n\n%s", J.to_string (node));
			}

			var t = new Treatment ();
			t.name = o.get_string_member ("name");
			t.unit = o.get_string_member ("unit");
			t.notes = o.get_string_member ("notes");
			t.frequency = o.get_string_member ("frequency");
			t.color = o.get_string_member ("color");
			t.icon = o.get_string_member ("icon");
			t.days = J.int_array (o.get_array_member ("days"));
			t.has_month_day = J.is_number (o, "monthDay");
			t.month_day = t.has_month_day ? (int) J.num (o, "monthDay") : 0;
			int[] cycle = J.int_array (o.get_array_member ("cycle"));
			while (cycle.length < 3) cycle += 1;
			t.cycle = cycle;

			o.get_array_member ("dosage").foreach_element ((arr, i, node) => {
				var d = node.get_object ();
				var time = d.get_array_member ("time");
				var td = new TimeDose ((int) time.get_element (0).get_double (),
				                       (int) time.get_element (1).get_double (),
				                       J.num (d, "dose"));
				td.last_taken = d.get_member ("lastTaken").is_null () ? null : d.get_string_member ("lastTaken");
				t.dosage.add (td);
			});

			var notif = o.get_object_member ("notification");
			t.increase_priority = notif.get_boolean_member ("increasePriority");
			var rec = notif.get_object_member ("recurring");
			t.recurring_enabled = rec.get_boolean_member ("enabled");
			t.recurring_interval = (int) J.num (rec, "interval");

			var inv = o.get_object_member ("inventory");
			t.inv_enabled = inv.get_boolean_member ("enabled");
			t.inv_current = J.num (inv, "current");
			t.inv_reminder = J.num (inv, "reminder");
			t.inv_refill = J.num (inv, "refill");

			var dur = o.get_object_member ("duration");
			t.dur_enabled = dur.get_boolean_member ("enabled");
			t.dur_start = (int64) J.num (dur, "start");
			t.dur_end = (int64) J.num (dur, "end");

			t.cycle_next_date = J.is_string (o, "cycleNextDate") ? o.get_string_member ("cycleNextDate") : null;
			t.mark_confirmed = o.get_boolean_member ("markConfirmed");
			return t;
		}

		public Json.Node to_json () {
			var o = new Json.Object ();
			o.set_string_member ("name", name);
			o.set_string_member ("unit", unit);
			o.set_string_member ("notes", notes);
			o.set_string_member ("frequency", frequency);
			o.set_string_member ("color", color);
			o.set_string_member ("icon", icon);
			o.set_array_member ("days", J.to_array (days));
			if (has_month_day) o.set_member ("monthDay", J.number (month_day));
			o.set_array_member ("cycle", J.to_array (cycle));

			var dosage_arr = new Json.Array ();
			foreach (var td in dosage) {
				var d = new Json.Object ();
				d.set_array_member ("time", J.to_array ({ td.hour, td.minute }));
				d.set_member ("dose", J.number (td.dose));
				if (td.last_taken != null) d.set_string_member ("lastTaken", td.last_taken);
				else d.set_null_member ("lastTaken");
				dosage_arr.add_object_element (d);
			}
			o.set_array_member ("dosage", dosage_arr);

			var rec = new Json.Object ();
			rec.set_boolean_member ("enabled", recurring_enabled);
			rec.set_member ("interval", J.number (recurring_interval));
			var notif = new Json.Object ();
			notif.set_boolean_member ("increasePriority", increase_priority);
			notif.set_object_member ("recurring", rec);
			o.set_object_member ("notification", notif);

			var inv = new Json.Object ();
			inv.set_boolean_member ("enabled", inv_enabled);
			inv.set_member ("current", J.number (inv_current));
			inv.set_member ("reminder", J.number (inv_reminder));
			inv.set_member ("refill", J.number (inv_refill));
			o.set_object_member ("inventory", inv);

			var dur = new Json.Object ();
			dur.set_boolean_member ("enabled", dur_enabled);
			dur.set_member ("start", J.number (dur_start));
			dur.set_member ("end", J.number (dur_end));
			o.set_object_member ("duration", dur);

			if (cycle_next_date != null) o.set_string_member ("cycleNextDate", cycle_next_date);
			o.set_boolean_member ("markConfirmed", mark_confirmed);

			var node = new Json.Node (Json.NodeType.OBJECT);
			node.set_object (o);
			return node;
		}

		// isTodayMedDay (cycle uses the stored current position)
		public bool is_med_day (GLib.DateTime day) {
			int64 d = Time.to_ms (Time.start_of_day (day));
			if (dur_enabled && (Time.day_ms (dur_start) > d || Time.day_ms (dur_end) < d)) return false;

			switch (frequency) {
				case "daily":
					return true;
				case "specific-days":
					int wd = Time.weekday (day);
					foreach (var x in days) if (x == wd) return true;
					return false;
				case "day-of-month":
					return month_day == day.get_day_of_month ();
				case "cycle":
					return cycle[2] <= cycle[0];
				default:
					return false;
			}
		}

		public bool has_ended () {
			return dur_enabled && Time.day_ms (dur_end) < Time.today_ms ();
		}
	}

	// --- History --------------------------------------------------------------

	public class HistoryEntry : Object {
		public string name;
		public string unit;
		public int hour;
		public int minute;
		public double dose;
		public string color;
		public int64 taken_at; // ms
		// -1 missed, 0 skipped, 1 confirmed, 2 auto-confirmed, 3 confirmed later
		public int taken_state;

		public signal void changed ();

		public HistoryEntry (string name, string unit, int hour, int minute, double dose,
		                     string color, int64 taken_at, int taken_state) {
			this.name = name;
			this.unit = unit;
			this.hour = hour;
			this.minute = minute;
			this.dose = dose;
			this.color = color;
			this.taken_at = taken_at;
			this.taken_state = taken_state;
		}

		// isValidHistoryItem
		public static HistoryEntry from_json (Json.Object o) throws DataError {
			bool ok =
				J.is_string (o, "name") && o.get_string_member ("name").strip () != "" &&
				J.is_string (o, "unit") && o.get_string_member ("unit").strip () != "" &&
				J.is_number_array (o, "time", 2) &&
				J.is_number (o, "dose") &&
				J.is_string (o, "color") && o.get_string_member ("color") != "" &&
				J.is_number_array (o, "taken", 2);

			if (!ok) {
				var node = new Json.Node (Json.NodeType.OBJECT);
				node.set_object (o);
				throw new DataError.INVALID ("Invalid history item\n\n%s", J.to_string (node));
			}

			var time = o.get_array_member ("time");
			var taken = o.get_array_member ("taken");
			return new HistoryEntry (
				o.get_string_member ("name"), o.get_string_member ("unit"),
				(int) time.get_element (0).get_double (), (int) time.get_element (1).get_double (),
				J.num (o, "dose"), o.get_string_member ("color"),
				(int64) taken.get_element (0).get_double (), (int) taken.get_element (1).get_double ());
		}

		public Json.Node to_json () {
			var o = new Json.Object ();
			o.set_string_member ("name", name);
			o.set_string_member ("unit", unit);
			o.set_array_member ("time", J.to_array ({ hour, minute }));
			o.set_member ("dose", J.number (dose));
			o.set_string_member ("color", color);
			var taken = new Json.Array ();
			taken.add_element (J.number (taken_at));
			taken.add_element (J.number (taken_state));
			o.set_array_member ("taken", taken);
			var node = new Json.Node (Json.NodeType.OBJECT);
			node.set_object (o);
			return node;
		}
	}

	// --- Today ----------------------------------------------------------------

	// One dose of one treatment shown on the Today page (not persisted).
	public class TodayItem : Object {
		public Treatment treatment;
		public int hour;
		public int minute;
		public double dose;
		public double original_dose;
		public bool when_needed;
		public int64 date_today_ls; // ms, when the Today list was built

		public string name { get { return treatment.name; } }
		public string unit { get { return treatment.unit; } }
		public string notes { get { return treatment.notes; } }
		public string color { get { return treatment.color; } }
		public string icon { get { return treatment.icon; } }

		public TodayItem (Treatment t, int hour, int minute, double dose, bool when_needed) {
			this.treatment = t;
			this.hour = hour;
			this.minute = minute;
			this.dose = dose;
			this.original_dose = dose;
			this.when_needed = when_needed;
			this.date_today_ls = Time.now_ms ();
		}
	}
}
