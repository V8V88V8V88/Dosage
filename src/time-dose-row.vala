/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

namespace Dosage {
	// Hours/minutes spinners (+ AM/PM in 12h locales).
	public class TimePicker : Gtk.Box {
		public int hours;   // 0-23
		public int minutes;
		public string text { get; private set; default = ""; }

		private Gtk.Adjustment adj_h;
		private Gtk.Adjustment adj_m;
		private Adw.ToggleGroup am_pm;
		private bool is12;

		public TimePicker (int hours24, int minutes) {
			Object (css_name: "time-picker");
			is12 = Locale.clock_is_12 ();
			bool is_pm = hours24 >= 12;
			int shown = is12 ? (hours24 % 12 == 0 ? 12 : hours24 % 12) : hours24;

			var hm = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
			hm.set_direction (Gtk.TextDirection.LTR);

			adj_h = new Gtk.Adjustment (shown, is12 ? 1 : 0, is12 ? 12 : 23, 1, 1, 0);
			var spin_h = spin_button (adj_h);
			var sep = new Gtk.Label (Locale.time_dot () ? " . " : " ∶ ");
			adj_m = new Gtk.Adjustment (minutes, 0, 59, 5, 5, 0);
			var spin_m = spin_button (adj_m);

			var labels = Locale.am_pm ();
			am_pm = new Adw.ToggleGroup () {
				margin_start = 8,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				visible = is12,
				orientation = Gtk.Orientation.VERTICAL
			};
			am_pm.add (new Adw.Toggle () { label = labels[0], name = "am" });
			am_pm.add (new Adw.Toggle () { label = labels[1], name = "pm" });
			am_pm.active_name = is_pm ? "pm" : "am";

			hm.append (spin_h);
			hm.append (sep);
			hm.append (spin_m);
			append (hm);
			append (am_pm);

			spin_h.output.connect (() => {
				spin_h.text = is12 ? "%d".printf ((int) adj_h.value) : lead_zero ((int) adj_h.value);
				update ();
				return true;
			});
			spin_m.output.connect (() => {
				spin_m.text = lead_zero ((int) adj_m.value);
				update ();
				return true;
			});
			am_pm.notify["active"].connect (update);
			update ();
		}

		private Gtk.SpinButton spin_button (Gtk.Adjustment adj) {
			var spin = (Gtk.SpinButton) Object.new (typeof (Gtk.SpinButton), css_name: "time-spinbutton");
			spin.orientation = Gtk.Orientation.VERTICAL;
			spin.valign = Gtk.Align.CENTER;
			spin.numeric = true;
			spin.wrap = true;
			spin.adjustment = adj;
			return spin;
		}

		private void update () {
			int h = (int) adj_h.value;
			if (is12) {
				bool pm = am_pm.active_name == "pm";
				if (pm && h < 12) h += 12;
				else if (!pm && h == 12) h = 0;
			}
			hours = h;
			minutes = (int) adj_m.value;
			text = Locale.format_time (hours, minutes);
		}
	}

	// One "time + dose" row of the medication dialog. Adw.SpinRow is sealed, so this
	// wraps one (like the JS version); get it back from a row with TimeDoseRow.of ().
	public class TimeDoseRow : Object {
		public Adw.SpinRow row;
		public Gtk.Box prefix;
		public Gtk.MenuButton time_btn;
		public TimePicker picker;

		public int hours { get { return picker.hours; } }
		public int minutes { get { return picker.minutes; } }

		public double value { get { return row.value; } }

		public static TimeDoseRow of (Gtk.Widget w) {
			return w.get_data<TimeDoseRow> ("time-dose-row");
		}

		public TimeDoseRow (int hour, int minute, double dose, bool removable) {
			row = new Adw.SpinRow (new Gtk.Adjustment (dose, 0.25, 9999, 0.25, 1, 0), 0.2, 2);
			row.add_css_class ("t-d-row");
			row.set_data<TimeDoseRow> ("time-dose-row", this);

			picker = new TimePicker (hour, minute);
			time_btn = new Gtk.MenuButton () {
				can_shrink = true,
				tooltip_text = _("Change Time"),
				label = picker.text,
				valign = Gtk.Align.CENTER,
				halign = Gtk.Align.START,
				popover = new Gtk.Popover () {
					child = new Gtk.ScrolledWindow () {
						propagate_natural_height = true,
						propagate_natural_width = true,
						child = picker
					}
				}
			};
			time_btn.add_css_class ("flat");
			time_btn.add_css_class ("numeric");
			picker.notify["text"].connect (() => time_btn.label = picker.text);

			prefix = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
			if (removable) {
				var remove_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
					valign = Gtk.Align.CENTER,
					margin_end = 3,
					tooltip_text = _("Remove Dose")
				};
				remove_btn.add_css_class ("circular");
				remove_btn.add_css_class ("destructive-action");
				remove_btn.clicked.connect (() => ((Gtk.ListBox) row.parent).remove (row));
				prefix.append (remove_btn);
			}
			prefix.append (time_btn);
			row.add_prefix (prefix);
		}
	}
}
