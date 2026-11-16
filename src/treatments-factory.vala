/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Treatments list rows: name, schedule, duration/next dose and stock badge,
// with an options menu (Edit, Refill, Duplicate, Delete).

namespace Dosage {
	public class TreatmentRow : Gtk.Box {
		public Gtk.Image icon;
		public Gtk.Label name_label;
		public Gtk.Label info_label;
		public Gtk.Label duration_label;
		public Gtk.Button inv_button;
		public Gtk.Label inv_label;
		public Gtk.Image inv_warning;
		public Gtk.PopoverMenu popover_menu;

		public Treatment? treatment;
		public uint position;
		private ulong changed_id;
		private GLib.SimpleAction refill_action;

		public signal void edit_requested (uint position);
		public signal void refill_requested (Treatment t);
		public signal void duplicate_requested (uint position);
		public signal void delete_requested (Treatment t, uint position);

		public TreatmentRow () {
			Object (css_name: "item-box");

			icon = new Gtk.Image.from_icon_name ("pill-symbolic") {
				margin_start = 14,
				margin_end = 1,
				valign = Gtk.Align.CENTER
			};
			icon.add_css_class ("med-icon");
			append (icon);

			var labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
				valign = Gtk.Align.CENTER,
				hexpand = true,
				margin_start = 9,
				margin_end = 11,
				margin_top = 2,
				margin_bottom = 2
			};
			append (labels);

			name_label = new Gtk.Label (null) {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				margin_bottom = 1
			};
			name_label.add_css_class ("title");
			labels.append (name_label);

			info_label = new Gtk.Label (null) {
				halign = Gtk.Align.START,
				justify = Gtk.Justification.FILL,
				wrap = true,
				natural_wrap_mode = Gtk.NaturalWrapMode.NONE
			};
			info_label.add_css_class ("subtitle");
			labels.append (info_label);

			duration_label = new Gtk.Label (null) {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				visible = false,
				margin_top = 1
			};
			duration_label.add_css_class ("subtitle");
			labels.append (duration_label);

			var inv_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
			inv_label = new Gtk.Label (null);
			inv_warning = new Gtk.Image.from_icon_name ("dosage-stock-warning-symbolic");
			inv_box.append (inv_label);
			inv_box.append (inv_warning);
			inv_button = new Gtk.Button () {
				valign = Gtk.Align.CENTER,
				margin_end = 4,
				visible = false,
				tooltip_text = _("Refill"),
				child = inv_box
			};
			inv_button.add_css_class ("badge-button");
			inv_button.clicked.connect (() => { if (treatment != null) refill_requested (treatment); });
			append (inv_button);

			// per-row actions ("row.edit" etc.) instead of the JS global app.edit<N>
			var group = new GLib.SimpleActionGroup ();
			var edit = new GLib.SimpleAction ("edit", null);
			edit.activate.connect (() => edit_requested (position));
			refill_action = new GLib.SimpleAction ("refill", null);
			refill_action.activate.connect (() => { if (treatment != null) refill_requested (treatment); });
			var dup = new GLib.SimpleAction ("duplicate", null);
			dup.activate.connect (() => duplicate_requested (position));
			var del = new GLib.SimpleAction ("delete", null);
			del.activate.connect (() => { if (treatment != null) delete_requested (treatment, position); });
			group.add_action (edit);
			group.add_action (refill_action);
			group.add_action (dup);
			group.add_action (del);
			insert_action_group ("row", group);

			var menu = new GLib.Menu ();
			menu.append (_("Edit"), "row.edit");
			menu.append (_("Refill"), "row.refill");
			menu.append (_("Duplicate"), "row.duplicate");
			menu.append (_("Delete"), "row.delete");

			popover_menu = new Gtk.PopoverMenu.from_model (menu) {
				halign = Gtk.Align.START,
				has_arrow = false
			};
			append (popover_menu);

			var options = new Gtk.MenuButton () {
				tooltip_text = _("Options"),
				valign = Gtk.Align.CENTER,
				margin_start = 5,
				margin_end = 11,
				icon_name = "view-more-symbolic",
				menu_model = menu
			};
			options.add_css_class ("circular");
			options.add_css_class ("flat");
			append (options);

			// right click (mouse) / long press (touch) opens the menu where pressed
			var alt_click = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
			alt_click.pressed.connect ((n, x, y) => popup_at (x, y));
			add_controller (alt_click);
			var long_press = new Gtk.GestureLongPress () { touch_only = true };
			long_press.pressed.connect ((x, y) => {
				Haptics.click ();
				popup_at (x, y);
			});
			add_controller (long_press);
		}

		private void popup_at (double x, double y) {
			popover_menu.pointing_to = { (int) x, (int) y, 1, 1 };
			popover_menu.popup ();
		}

		public void bind (Treatment t, uint position) {
			unbind ();
			treatment = t;
			this.position = position;
			name_label.label = t.name;
			icon.icon_name = t.icon;
			css_classes = { t.color };
			refill_action.set_enabled (t.inv_enabled);
			update_labels ();
			changed_id = t.changed.connect (update_labels);
		}

		public void unbind () {
			if (treatment != null && changed_id != 0) treatment.disconnect (changed_id);
			changed_id = 0;
			treatment = null;
		}

		// setInventoryAndDateLabels
		private void update_labels () {
			var t = treatment;
			int64 today = Time.today_ms ();
			int64 start = Time.day_ms (t.dur_start);
			int64 end = Time.day_ms (t.dur_end);

			inv_button.visible = t.inv_enabled;
			if (t.inv_enabled) {
				double current = double.max (0, t.inv_current);
				// TRANSLATORS: %d is a placeholder for the number of remaining inventory stock
				inv_label.label = ngettext ("%d Remaining", "%d Remaining", (ulong) current)
					.replace ("%d", format_number (current));
				bool low = t.inv_current <= t.inv_reminder;
				inv_warning.visible = low;
				if (low) inv_button.add_css_class ("warning");
				else inv_button.remove_css_class ("warning");
			}

			// TRANSLATORS: label for when duration is enabled
			string start_label = _("Starts on") + " " + Locale.format_date (t.dur_start);
			string until_label = _("Until") + " " + Locale.format_date (t.dur_end);
			string ended_label = _("Ended on") + " " + Locale.format_date (t.dur_end);

			duration_label.visible = false;
			if (t.dur_enabled && !t.is_when_needed) {
				duration_label.visible = true;
				duration_label.label = start > today ? start_label : until_label;
			}

			switch (t.frequency) {
				case "daily":
					info_label.label = _("Daily");
					break;
				case "specific-days":
					info_label.label = Locale.specific_days_label (t.days);
					break;
				case "day-of-month":
					info_label.label = _("Day") + ": %d".printf (t.month_day);
					break;
				case "cycle":
					var next_dt = Time.parse_iso (t.cycle_next_date);
					int64 next = next_dt != null ? Time.to_ms (Time.start_of_day (next_dt)) : today;
					string next_label = Locale.format_date (next);
					if (t.dur_enabled) {
						duration_label.label = until_label;
						if (next > today && next <= end)
							duration_label.label += " ⦁ " + _("Next Dose") + ": " + next_label;
					} else if (next > today) {
						duration_label.label = _("Next Dose") + ": " + next_label;
					}
					duration_label.visible = !(next <= today && !t.dur_enabled);
					info_label.label = "%s ⦁ %d ⊷ %d".printf (_("Cycle"), t.cycle[0], t.cycle[1]);
					break;
				case "when-needed":
					info_label.label = _("As Needed");
					break;
			}

			if (t.notes != "") info_label.label += " ⦁ " + t.notes;
			if (t.dur_enabled && (end < today || end < start)) duration_label.label = ended_label;
		}
	}

	namespace TreatmentsFactory {
		public Gtk.SignalListItemFactory create (Window window) {
			var factory = new Gtk.SignalListItemFactory ();
			factory.setup.connect ((f, obj) => {
				var item = (Gtk.ListItem) obj;
				var row = new TreatmentRow ();
				item.child = row;
				row.edit_requested.connect ((pos) => window.present_med_dialog ((int) pos, false));
				row.duplicate_requested.connect ((pos) => window.present_med_dialog ((int) pos, true));
				row.delete_requested.connect ((t, pos) => window.confirm_delete (t, pos, null));
				row.refill_requested.connect ((t) => window.present_refill_dialog (t));

				var keys = new Gtk.EventControllerKey ();
				keys.key_pressed.connect ((keyval, keycode, state) => {
					if (keyval != Gdk.Key.space) return false;
					var lv = row.get_ancestor (typeof (Gtk.ListView));
					if (lv != null) GLib.Signal.emit_by_name (lv, "activate", item.position);
					return true;
				});
				row.add_controller (keys);
			});
			factory.bind.connect ((f, obj) => {
				var item = (Gtk.ListItem) obj;
				((TreatmentRow) item.child).bind ((Treatment) item.item, item.position);
			});
			factory.unbind.connect ((f, obj) => {
				((TreatmentRow) ((Gtk.ListItem) obj).child).unbind ();
			});
			return factory;
		}
	}
}
