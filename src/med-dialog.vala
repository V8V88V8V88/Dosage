/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

namespace Dosage {
	private const string[] FREQUENCIES = { "daily", "specific-days", "day-of-month", "cycle", "when-needed" };

	[GtkTemplate (ui = "/io/github/diegopvlk/Dosage/ui/med-dialog.ui")]
	public class MedDialog : Adw.Dialog {
		[GtkChild] unowned Adw.ToastOverlay toastOverlay;
		[GtkChild] unowned Gtk.Button saveButton;
		[GtkChild] unowned Adw.Clamp medDialogClamp;
		[GtkChild] unowned Adw.EntryRow medName;
		[GtkChild] unowned Gtk.MenuButton dosageColorButton;
		[GtkChild] unowned Gtk.Popover dosageColorPopover;
		[GtkChild] unowned Gtk.Box dosageColorBox;
		[GtkChild] unowned Adw.EntryRow medUnit;
		[GtkChild] unowned Gtk.MenuButton dosageIconButton;
		[GtkChild] unowned Gtk.Popover dosageIconPopover;
		[GtkChild] unowned Gtk.Grid dosageIconBox;
		[GtkChild] unowned Adw.EntryRow medNotes;
		[GtkChild] unowned Adw.ComboRow frequencyMenu;
		[GtkChild] unowned Gtk.MenuButton frequencySpecificDays;
		[GtkChild] unowned Gtk.Box specificDaysBox;
		[GtkChild] unowned Gtk.MenuButton frequencyDayOfMonth;
		[GtkChild] unowned Adw.SpinRow dayOfMonth;
		[GtkChild] unowned Gtk.MenuButton frequencyCycle;
		[GtkChild] unowned Adw.SpinRow cycleActive;
		[GtkChild] unowned Adw.SpinRow cycleInactive;
		[GtkChild] unowned Adw.SpinRow cycleCurrent;
		[GtkChild] unowned Gtk.ListBox dosageList;
		[GtkChild] unowned Adw.SwitchRow increasePriority;
		[GtkChild] unowned Adw.ExpanderRow recurringNotif;
		[GtkChild] unowned Gtk.Adjustment recurringInterval;
		[GtkChild] unowned Adw.ExpanderRow medInventory;
		[GtkChild] unowned Gtk.Adjustment medCurrrentInv;
		[GtkChild] unowned Gtk.Adjustment medReminderInv;
		[GtkChild] unowned Gtk.Adjustment refillAmount;
		[GtkChild] unowned Adw.ExpanderRow medDuration;
		[GtkChild] unowned Adw.ActionRow calendarStartRow;
		[GtkChild] unowned Gtk.Calendar calendarStart;
		[GtkChild] unowned Adw.ActionRow calendarEndRow;
		[GtkChild] unowned Gtk.Calendar calendarEnd;
		[GtkChild] unowned Adw.SwitchRow markAsConfirmed;
		[GtkChild] unowned Adw.ButtonRow deleteButton;

		private Window window;
		private Treatment? editing;   // treatment being edited (null when adding)
		private bool duplicate;
		private Adw.Toast toast = new Adw.Toast ("");
		private Gtk.Widget? freq_prefix;

		public MedDialog (Window window, Treatment? source, bool duplicate) {
			this.window = window;
			this.duplicate = duplicate;
			this.editing = duplicate ? null : source;
			presentation_mode = Adw.DialogPresentationMode.BOTTOM_SHEET;

			var now = Time.now ();
			calendarStartRow.subtitle = now.format ("%x");
			calendarEndRow.subtitle = now.format ("%x");
			setup_icon_and_color ();
			setup_calendar (calendarStart, calendarStartRow);
			setup_calendar (calendarEnd, calendarEndRow);
			setup_frequency_menu ();

			if (source != null) {
				fill_from (source);
			} else {
				dosageList.append (new TimeDoseRow (12, 30, 1, false).row);
			}

			var add_dose = new Gtk.Button.from_icon_name ("list-add-symbolic") {
				valign = Gtk.Align.CENTER,
				margin_end = 3,
				tooltip_text = _("Add Dose")
			};
			add_dose.add_css_class ("circular");
			add_dose.add_css_class ("suggested-action");
			add_dose.clicked.connect (() => {
				var last = TimeDoseRow.of (dosageList.get_last_child ());
				dosageList.append (new TimeDoseRow ((last.hours + 1) % 24, last.minutes, last.value, true).row);
			});
			TimeDoseRow.of (dosageList.get_first_child ()).prefix.prepend (add_dose);

			dayOfMonth.output.connect (() => { update_day_of_month_labels (); return false; });
			cycleActive.output.connect (() => { update_cycle (); return false; });
			cycleInactive.output.connect (() => { update_cycle (); return false; });

			int day = Locale.first_weekday ();
			for (var b = specificDaysBox.get_first_child (); b != null; b = b.get_next_sibling ()) {
				((Gtk.ToggleButton) b).label = Locale.day_label (day);
				((Gtk.ToggleButton) b).toggled.connect (update_specific_days_label);
				day = (day + 1) % 7;
			}

			// Ctrl/Shift + Enter saves
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

			int h, nat;
			medDialogClamp.measure (Gtk.Orientation.VERTICAL, -1, out h, out nat, null, null);
			content_height = h + 48;
		}

		private void fill_from (Treatment t) {
			if (!duplicate) {
				title = _("Edit Treatment");
				saveButton.label = _("Save");
				deleteButton.visible = true;
				presentation_mode = Adw.DialogPresentationMode.AUTO;
				deleteButton.activated.connect (() => window.confirm_delete (t, 0, this));
			}

			medName.text = t.name + (duplicate ? " (%s)".printf (_("Copy")) : "");
			medUnit.text = t.unit;
			medNotes.text = t.notes;

			for (var c = dosageColorBox.get_first_child (); c != null; c = c.get_next_sibling ()) {
				if (c.name == t.color) {
					dosageColorButton.add_css_class (t.color + "-clr");
					dosageColorButton.name = c.name;
				}
			}
			for (var c = dosageIconBox.get_first_child (); c != null; c = c.get_next_sibling ()) {
				if (((Gtk.Button) c).icon_name == t.icon + "-symbolic")
					dosageIconButton.icon_name = t.icon + "-symbolic";
			}

			bool first = true;
			foreach (var td in t.dosage) {
				dosageList.append (new TimeDoseRow (td.hour, td.minute, td.dose, !first).row);
				first = false;
			}

			for (int i = 0; i < FREQUENCIES.length; i++)
				if (FREQUENCIES[i] == t.frequency) frequencyMenu.selected = i;
			if (t.frequency == "specific-days") frequencyMenu.subtitle = Locale.specific_days_label (t.days);

			markAsConfirmed.active = t.mark_confirmed;
			increasePriority.active = t.increase_priority;
			recurringNotif.enable_expansion = t.recurring_enabled;
			recurringInterval.value = t.recurring_interval;
			if (t.has_month_day) dayOfMonth.value = t.month_day;
			if (t.frequency == "day-of-month") update_day_of_month_labels ();

			int day = Locale.first_weekday ();
			for (var b = specificDaysBox.get_first_child (); b != null; b = b.get_next_sibling ()) {
				foreach (var d in t.days) if (d == day) ((Gtk.ToggleButton) b).active = true;
				day = (day + 1) % 7;
			}

			cycleActive.value = t.cycle[0];
			cycleInactive.value = t.cycle[1];
			cycleCurrent.adjustment.upper = t.cycle[0] + t.cycle[1];
			cycleCurrent.value = t.cycle[2];
			if (t.frequency == "cycle") frequencyMenu.subtitle = "%d ⊷ %d".printf (t.cycle[0], t.cycle[1]);

			medInventory.enable_expansion = t.inv_enabled;
			medCurrrentInv.value = t.inv_current;
			medReminderInv.value = t.inv_reminder;
			refillAmount.value = t.inv_refill;

			if (t.dur_enabled) {
				medDuration.enable_expansion = true;
				calendarStart.select_day (Time.from_ms (t.dur_start));
				calendarEnd.select_day (Time.from_ms (t.dur_end));
			}
		}

		private void setup_icon_and_color () {
			for (var c = dosageColorBox.get_first_child (); c != null; c = c.get_next_sibling ()) {
				var btn = (Gtk.Button) c;
				btn.clicked.connect (() => {
					dosageColorButton.css_classes = { btn.name + "-clr", "circular" };
					dosageColorButton.name = btn.name;
					dosageColorPopover.popdown ();
				});
			}
			for (var c = dosageIconBox.get_first_child (); c != null; c = c.get_next_sibling ()) {
				var btn = (Gtk.Button) c;
				btn.clicked.connect (() => {
					dosageIconButton.icon_name = btn.icon_name;
					dosageIconPopover.popdown ();
				});
			}
		}

		// handleCalendarSelect
		private void setup_calendar (Gtk.Calendar cal, Adw.ActionRow row) {
			Gtk.Calendar c = cal;
			cal.day_selected.connect (() => row.subtitle = c.get_date ().format ("%x"));
			cal.next_month.connect (() => row.subtitle = c.get_date ().format ("%x"));
			cal.prev_month.connect (() => row.subtitle = c.get_date ().format ("%x"));
			cal.next_year.connect (() => row.subtitle = c.get_date ().format ("%x"));
			cal.prev_year.connect (() => row.subtitle = c.get_date ().format ("%x"));
		}

		private void setup_frequency_menu () {
			freq_prefix = frequencyMenu.get_first_child ()?.get_first_child ();
			frequencyMenu.notify["selected-item"].connect (on_frequency_changed);
			on_frequency_changed ();
		}

		private void on_frequency_changed () {
			uint sel = frequencyMenu.selected;
			if (freq_prefix != null) freq_prefix.visible = sel != 0 && sel != 4;
			frequencySpecificDays.visible = sel == 1;
			frequencyDayOfMonth.visible = sel == 2;
			frequencyCycle.visible = sel == 3;

			switch (sel) {
				case 1:
					frequencyMenu.title = _("Specific Days");
					update_specific_days_label ();
					break;
				case 2:
					update_day_of_month_labels ();
					break;
				case 3:
					frequencyMenu.title = _("Cycle");
					update_cycle ();
					break;
				default:
					frequencyMenu.title = _("Frequency");
					break;
			}

			// "as needed": no confirmation, priority, duration or recurring, single dose
			markAsConfirmed.visible = sel != 4;
			increasePriority.visible = sel != 4;
			medDuration.visible = sel != 4;
			recurringNotif.visible = sel != 4;
			var first = dosageList.get_first_child ();
			for (var r = first; r != null; r = r.get_next_sibling ()) {
				TimeDoseRow.of (r).prefix.sensitive = sel != 4;
				r.visible = sel != 4 || r == first;
			}
		}

		private int[] selected_days () {
			int[] days = {};
			int day = Locale.first_weekday ();
			for (var b = specificDaysBox.get_first_child (); b != null; b = b.get_next_sibling ()) {
				if (((Gtk.ToggleButton) b).active) days += day;
				day = (day + 1) % 7;
			}
			// sorted ascending
			for (int i = 0; i < days.length; i++)
				for (int j = i + 1; j < days.length; j++)
					if (days[j] < days[i]) { int tmp = days[i]; days[i] = days[j]; days[j] = tmp; }
			return days;
		}

		private void update_specific_days_label () {
			var days = selected_days ();
			frequencyMenu.subtitle = days.length == 0 ? _("Choose") : Locale.specific_days_label (days);
		}

		private void update_day_of_month_labels () {
			frequencyMenu.title = _("Day of Month");
			frequencyMenu.subtitle = _("Day") + ": %d".printf ((int) dayOfMonth.value);
		}

		private void update_cycle () {
			int sum = (int) (cycleActive.value + cycleInactive.value);
			frequencyMenu.subtitle = "%d ⊷ %d".printf ((int) cycleActive.value, (int) cycleInactive.value);
			cycleCurrent.adjustment.upper = sum;
			if (cycleCurrent.value > sum) cycleCurrent.value = sum;
		}

		private void show_toast (string title) {
			toast.dismiss ();
			toast = new Adw.Toast (title);
			toastOverlay.add_toast (toast);
			Haptics.click ();
		}

		private bool is_valid_input () {
			medName.changed.connect (() => medName.remove_css_class ("error"));
			medUnit.changed.connect (() => medUnit.remove_css_class ("error"));

			if (medName.text.strip () == "") {
				show_toast (_("Empty Name"));
				medName.add_css_class ("error");
				return false;
			}
			if (medUnit.text.strip () == "") {
				show_toast (_("Empty Unit"));
				medUnit.add_css_class ("error");
				return false;
			}
			if (frequencySpecificDays.visible && selected_days ().length == 0) {
				show_toast (_("Choose at Least One Day"));
				return false;
			}

			var store = Store.get_default ();
			string name = medName.text.strip ().down ();
			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				if (t == editing) continue;
				if (t.name.down () == name) {
					show_toast (_("Name Already on Treatment List"));
					medName.add_css_class ("error");
					return false;
				}
			}

			var seen = new GenericSet<string> (str_hash, str_equal);
			for (var r = dosageList.get_first_child (); r != null; r = r.get_next_sibling ()) {
				var row = TimeDoseRow.of (r);
				string key = "%d,%d".printf (row.hours, row.minutes);
				if (seen.contains (key)) {
					show_toast (_("Duplicated Time"));
					return false;
				}
				seen.add (key);
			}
			return true;
		}

		[GtkCallback (name = "_close")]
		private void on_close () {
			force_close ();
		}

		[GtkCallback (name = "_save")]
		private void on_save () {
			if (!is_valid_input ()) return;
			var t = build_treatment ();
			var store = Store.get_default ();

			if (editing != null) {
				uint pos;
				if (store.treatments.find (editing, out pos)) store.treatments.remove (pos);
			}
			string sorting = new GLib.Settings (Config.APP_ID).get_string ("treatments-sorting");
			uint pos = store.treatments.insert_sorted (t, (a, b) =>
				compare_treatments ((Treatment) a, (Treatment) b, sorting));

			window.update_everything (false, false, true);
			window.scroll_treatments_to (pos > 0 ? pos - 1 : 0);
			force_close ();
			window.schedule_notifications ("saving");
		}

		private Treatment build_treatment () {
			var t = new Treatment ();
			t.name = medName.text.strip ();
			t.unit = medUnit.text.strip ();
			t.notes = medNotes.text.strip ();
			t.frequency = FREQUENCIES[frequencyMenu.selected];
			t.color = dosageColorButton.name;
			t.icon = dosageIconButton.icon_name.replace ("-symbolic", "");
			t.days = selected_days ();
			t.has_month_day = true;
			t.month_day = (int) dayOfMonth.value;
			t.cycle = { (int) cycleActive.adjustment.value, (int) cycleInactive.adjustment.value,
			            (int) cycleCurrent.adjustment.value };
			t.mark_confirmed = markAsConfirmed.active;
			t.increase_priority = increasePriority.active;
			t.recurring_enabled = recurringNotif.enable_expansion;
			t.recurring_interval = (int) recurringInterval.value;
			t.inv_enabled = medInventory.enable_expansion;
			t.inv_current = medCurrrentInv.value;
			t.inv_reminder = medReminderInv.value;
			t.inv_refill = refillAmount.value;

			t.dur_enabled = medDuration.enable_expansion;
			if (t.dur_enabled) {
				t.dur_start = calendarStart.get_date ().to_unix () * 1000;
				t.dur_end = calendarEnd.get_date ().to_unix () * 1000;
			} else {
				t.dur_start = Time.now ().to_unix () * 1000;
				t.dur_end = t.dur_start;
			}

			// doses sorted by time; keep lastTaken for unchanged times when editing
			var rows = new GenericArray<TimeDoseRow> ();
			for (var r = dosageList.get_first_child (); r != null; r = r.get_next_sibling ())
				rows.add (TimeDoseRow.of (r));
			rows.sort ((a, b) => (a.hours * 60 + a.minutes) - (b.hours * 60 + b.minutes));
			foreach (var row in rows) {
				var td = new TimeDose (row.hours, row.minutes, row.value);
				if (editing != null)
					foreach (var old in editing.dosage)
						if (old.hour == td.hour && old.minute == td.minute) td.last_taken = old.last_taken;
				t.dosage.add (td);
			}
			// cycleNextDate is filled in by update_cycle_and_last_up
			if (t.frequency == "cycle") t.cycle_next_date = Time.now_iso ();
			return t;
		}
	}
}
