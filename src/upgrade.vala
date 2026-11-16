/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Upgrade old JSON layouts in place (port of utils/upgradeItems.js).
// Each function returns true if the data changed (and should be saved).

namespace Dosage.Upgrade {
	private const int LATEST = 1;

	private int version_of (Json.Object root) {
		return J.is_number (root, "version") ? (int) J.num (root, "version") : -1;
	}

	public bool treatments (Json.Object root) {
		int current = version_of (root);
		if (current >= LATEST) return false;

		// version 0: very old "meds" layout / missing inventory.enabled
		if (current < 0) treatments_v0 (root);

		// version 1: notification object, inventory.refill, markConfirmed
		bool priority = false;
		var schema = GLib.SettingsSchemaSource.get_default ().lookup (Config.APP_ID, true);
		if (schema != null) priority = new GLib.Settings (Config.APP_ID).get_boolean ("priority");

		if (root.has_member ("treatments")) {
			var arr = root.get_array_member ("treatments");
			for (uint i = 0; i < arr.get_length (); i++) {
				var item = arr.get_object_element (i);
				var notif = new Json.Object ();
				notif.set_boolean_member ("increasePriority", priority);
				var rec = new Json.Object ();
				if (J.is_object (item, "recurring")) {
					var old = item.get_object_member ("recurring");
					rec.set_boolean_member ("enabled", J.is_bool (old, "enabled") && old.get_boolean_member ("enabled"));
					rec.set_member ("interval", J.number (J.is_number (old, "interval") ? J.num (old, "interval") : 5));
				} else {
					rec.set_boolean_member ("enabled", false);
					rec.set_member ("interval", J.number (5));
				}
				notif.set_object_member ("recurring", rec);
				item.set_object_member ("notification", notif);
				if (J.is_object (item, "inventory"))
					item.get_object_member ("inventory").set_member ("refill", J.number (30));
				if (item.has_member ("recurring")) item.remove_member ("recurring");
				item.set_boolean_member ("markConfirmed", false);
			}
		}

		root.set_member ("version", J.number (LATEST));
		return true;
	}

	private void treatments_v0 (Json.Object root) {
		if (root.has_member ("meds")) {
			var treatments = new Json.Array ();
			string last_update = "";
			var meds = root.get_array_member ("meds");
			for (uint i = 0; i < meds.get_length (); i++) {
				var item = meds.get_object_element (i);
				var info = item.has_member ("info") ? item.get_object_member ("info") : item.get_object_member ("_info");
				var dur = info.get_object_member ("duration");

				var dosage = info.get_array_member ("dosage");
				for (uint j = 0; j < dosage.get_length (); j++) {
					var d = dosage.get_object_element (j);
					d.set_null_member ("lastTaken");
					if (d.has_member ("updated")) d.remove_member ("updated");
				}

				// start/end were strings in seconds
				if (J.is_string (dur, "start")) {
					double start = double.parse (dur.get_string_member ("start")) * 1000;
					double end = J.is_string (dur, "end") ? double.parse (dur.get_string_member ("end")) * 1000 : 0;
					dur.set_member ("start", J.number (start));
					dur.set_member ("end", J.number (end != 0 ? end : start));
				}

				if (!J.is_string (info, "lastUpdate")) info.set_string_member ("lastUpdate", Time.now_iso ());

				// v1.1.0 only has recurring: boolean
				bool rc_enabled = false;
				double rc_interval = 5;
				if (J.is_object (info, "recurring")) {
					var r = info.get_object_member ("recurring");
					rc_enabled = J.is_bool (r, "enabled") && r.get_boolean_member ("enabled");
					if (J.is_number (r, "interval") && J.num (r, "interval") != 0) rc_interval = J.num (r, "interval");
				} else if (J.is_bool (info, "recurring")) {
					rc_enabled = info.get_boolean_member ("recurring");
				}
				var recurring = new Json.Object ();
				recurring.set_boolean_member ("enabled", rc_enabled);
				recurring.set_member ("interval", J.number (rc_interval));

				var med = new Json.Object ();
				med.set_string_member ("name", item.has_member ("name") ? item.get_string_member ("name") : item.get_string_member ("_name"));
				med.set_string_member ("unit", item.has_member ("unit") ? item.get_string_member ("unit") : item.get_string_member ("_unit"));
				med.set_member ("notes", info.get_member ("notes"));
				med.set_member ("frequency", info.get_member ("frequency"));
				med.set_member ("color", info.get_member ("color"));
				med.set_string_member ("icon", info.get_string_member ("icon").replace ("-symbolic", ""));
				med.set_member ("days", info.get_member ("days"));
				med.set_member ("cycle", info.get_member ("cycle"));
				med.set_array_member ("dosage", dosage);
				med.set_object_member ("recurring", recurring);
				med.set_member ("inventory", info.get_member ("inventory"));
				med.set_object_member ("duration", dur);
				treatments.add_object_element (med);
				last_update = info.get_string_member ("lastUpdate");
			}
			root.remove_member ("meds");
			root.set_array_member ("treatments", treatments);
			root.set_string_member ("lastUpdate", last_update);
		}

		// #73: inventory.enabled may be missing
		if (root.has_member ("treatments")) {
			var arr = root.get_array_member ("treatments");
			for (uint i = 0; i < arr.get_length (); i++) {
				var item = arr.get_object_element (i);
				if (J.is_object (item, "inventory") && !item.get_object_member ("inventory").has_member ("enabled"))
					item.get_object_member ("inventory").set_boolean_member ("enabled", false);
			}
		}
	}

	public bool history (Json.Object root) {
		int current = version_of (root);
		if (current >= LATEST) return false;

		if (current < 0) {
			if (root.has_member ("meds")) {
				var history = new Json.Array ();
				var meds = root.get_array_member ("meds");
				for (uint i = 0; i < meds.get_length (); i++) {
					var item = meds.get_object_element (i);
					var info = item.has_member ("info") ? item.get_object_member ("info") : item.get_object_member ("_info");
					string date = item.has_member ("date") ? item.get_string_member ("date") : item.get_string_member ("_date");
					string taken = item.has_member ("taken") ? item.get_string_member ("taken") : item.get_string_member ("_taken");
					int taken_value = taken == "yes" ? 1 : (taken == "no" ? 0 : -1);
					var dt = Time.parse_iso (date);

					var h = new Json.Object ();
					h.set_string_member ("name", item.has_member ("name") ? item.get_string_member ("name") : item.get_string_member ("_name"));
					h.set_string_member ("unit", item.has_member ("unit") ? item.get_string_member ("unit") : item.get_string_member ("_unit"));
					h.set_member ("time", info.get_member ("time"));
					h.set_member ("dose", info.get_member ("dose"));
					h.set_string_member ("color", item.has_member ("color") ? item.get_string_member ("color") : item.get_string_member ("_color"));
					var taken_arr = new Json.Array ();
					taken_arr.add_element (J.number (dt != null ? Time.to_ms (dt) : Time.now_ms ()));
					taken_arr.add_element (J.number (taken_value));
					h.set_array_member ("taken", taken_arr);
					history.add_object_element (h);
				}
				root.remove_member ("meds");
				root.set_array_member ("history", history);
			} else if (J.is_object (root, "history")) {
				// { "history": { "<date>": [items] } } -> flat array
				var flat = new Json.Array ();
				var by_date = root.get_object_member ("history");
				foreach (var key in by_date.get_members ()) {
					var items = by_date.get_array_member (key);
					for (uint i = 0; i < items.get_length (); i++) flat.add_element (items.get_element (i));
				}
				root.set_array_member ("history", flat);
			}
		}

		root.set_member ("version", J.number (LATEST));
		return true;
	}
}
