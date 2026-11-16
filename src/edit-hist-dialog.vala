/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

namespace Dosage {
	[GtkTemplate (ui = "/io/github/diegopvlk/Dosage/ui/edit-hist-dialog.ui")]
	public class EditHistDialog : Adw.Dialog {
		[GtkChild] unowned Adw.Clamp editHistDialogClamp;
		[GtkChild] unowned Gtk.Button saveButton;
		[GtkChild] unowned Gtk.ScrolledWindow popoverScrollTime;
		[GtkChild] unowned Adw.SpinRow nameDoseSpinRow;
		[GtkChild] unowned Adw.ActionRow takenRow;
		[GtkChild] unowned Adw.ToggleGroup takenButtons;

		private Window window;
		private HistoryEntry entry;
		private TimePicker picker;
		private bool confirm_activated;

		public EditHistDialog (Window window, HistoryEntry entry) {
			this.window = window;
			this.entry = entry;

			var taken = Time.from_ms (entry.taken_at);
			// missed doses default to their scheduled time
			int h = entry.taken_state == -1 ? entry.hour : taken.get_hour ();
			int m = entry.taken_state == -1 ? entry.minute : taken.get_minute ();
			picker = new TimePicker (h, m);
			popoverScrollTime.child = picker;

			nameDoseSpinRow.title = entry.name;
			nameDoseSpinRow.subtitle = "%s %s".printf (format_number (entry.dose), entry.unit);
			nameDoseSpinRow.value = entry.dose;
			takenRow.subtitle = picker.text;

			switch (entry.taken_state) {
				case 2:
					takenButtons.active_name = "confirmed";
					takenRow.title = _("Auto-Confirmed");
					break;
				case 1:
					takenButtons.active_name = "confirmed";
					takenRow.title = _("Confirmed At");
					break;
				case 0:
					takenButtons.active_name = "skipped";
					takenRow.title = _("Skipped At");
					break;
				case -1:
					takenButtons.active_name = "skipped";
					takenRow.title = _("Missed") + " (?)";
					saveButton.sensitive = false;
					break;
				case 3:
					takenButtons.active_name = "confirmed";
					takenRow.title = _("Confirmed");
					takenRow.subtitle = _("Time Unknown");
					break;
			}

			nameDoseSpinRow.notify["value"].connect (() => {
				nameDoseSpinRow.subtitle = "%s %s".printf (format_number (nameDoseSpinRow.value), entry.unit);
			});
			picker.notify["text"].connect (() => {
				if (takenRow.subtitle == picker.text) return;
				takenRow.subtitle = picker.text;
				if (takenButtons.active_name == "confirmed") {
					takenRow.title = _("Confirmed At");
					confirm_activated = true;
				}
			});

			var keys = new Gtk.EventControllerKey ();
			keys.key_pressed.connect ((keyval, keycode, state) => {
				bool mod = (state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK)) != 0;
				if (mod && keyval == Gdk.Key.Return && saveButton.sensitive) {
					saveButton.activate ();
					return true;
				}
				return false;
			});
			((Gtk.Widget) this).add_controller (keys);

			int min_h, nat;
			editHistDialogClamp.measure (Gtk.Orientation.VERTICAL, -1, out min_h, out nat, null, null);
			content_height = min_h + 48;
		}

		[GtkCallback (name = "_handleTakenRowStatus")]
		private void on_taken_status () {
			saveButton.sensitive = true;
			takenRow.subtitle = picker.text;
			Haptics.tick ();
			if (takenButtons.active_name == "confirmed") {
				takenRow.title = _("Confirmed At");
				confirm_activated = true;
			} else {
				takenRow.title = _("Skipped At");
			}
		}

		[GtkCallback (name = "_closeDialog")]
		private void on_close () {
			force_close ();
		}

		[GtkCallback (name = "_save")]
		private void on_save () {
			Haptics.click ();
			save ();
			force_close ();
		}

		private void save () {
			var store = Store.get_default ();
			int64 old_taken_at = entry.taken_at;
			int old_state = entry.taken_state;
			double old_dose = entry.dose;
			double new_dose = nameDoseSpinRow.value;

			double missed = 0, skipped = 0, confirmed = 0;
			switch (old_state) {
				case -1: missed = old_dose; break;
				case 0: skipped = old_dose; break;
				default: confirmed = old_dose; break;
			}

			bool skip = takenButtons.active_name == "skipped";
			bool conf = takenButtons.active_name == "confirmed";
			int state;
			if (skip) state = 0;
			else if (confirm_activated && conf) state = 1;
			else if (old_state == 2 && conf) state = 2;
			else if (old_state == 3 && conf) state = 3;
			else state = 1;

			var day = Time.from_ms (old_taken_at);
			int64 new_taken_at = Time.to_ms (Time.at_time (day, picker.hours, picker.minutes));

			if (new_taken_at == old_taken_at && state == old_state && new_dose == old_dose) return;

			// re-insert at its new place (history is newest first)
			uint pos;
			if (store.history.find (entry, out pos)) store.history.remove (pos);
			entry.taken_at = new_taken_at;
			entry.taken_state = state;
			entry.dose = new_dose;
			uint new_pos = store.history.insert_sorted (entry, (a, b) => {
				int64 x = ((HistoryEntry) a).taken_at, y = ((HistoryEntry) b).taken_at;
				return x < y ? 1 : (x > y ? -1 : 0);
			});
			store.save_history ();
			window.history_changed ();
			window.scroll_history_to (new_pos > 0 ? new_pos - 1 : 0);

			// adjust stock for the change
			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				if (t.name != entry.name || !t.inv_enabled) continue;
				double before = t.inv_current;
				if (state == 0) {
					t.inv_current += confirmed;
				} else {
					t.inv_current += (old_dose - new_dose) - (skipped + missed);
				}
				if (before == t.inv_current) break;
				t.changed ();
				store.save_treatments ();
				window.refresh_inventory ();
			}
		}
	}
}
