/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// History list: one section per day, rows with a taken/skipped/missed badge.

namespace Dosage {
	public class HistoryRow : Gtk.Box {
		public Gtk.CheckButton check_button;
		private Gtk.Label name_label;
		private Gtk.Label dose_label;
		private Gtk.Box taken_box;
		private Gtk.Label taken_label;
		private Gtk.Image taken_icon;

		public HistoryEntry? entry;
		private ulong changed_id;

		public HistoryRow () {
			Object (css_name: "item-box");

			check_button = new Gtk.CheckButton () {
				valign = Gtk.Align.CENTER,
				halign = Gtk.Align.CENTER,
				margin_start = 13,
				tooltip_text = _("Select to be Removed")
			};
			check_button.add_css_class ("selection-mode");
			append (check_button);

			var labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
				valign = Gtk.Align.CENTER,
				hexpand = true,
				margin_start = 9,
				margin_end = 10
			};
			append (labels);

			name_label = new Gtk.Label (null) {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				margin_bottom = 1
			};
			name_label.add_css_class ("title");
			labels.append (name_label);

			dose_label = new Gtk.Label (null) {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END
			};
			dose_label.add_css_class ("subtitle");
			labels.append (dose_label);

			taken_box = (Gtk.Box) Object.new (typeof (Gtk.Box), css_name: "badge-box");
			taken_box.valign = Gtk.Align.CENTER;
			taken_box.margin_end = 14;
			taken_label = new Gtk.Label (null) {
				valign = Gtk.Align.CENTER,
				ellipsize = Pango.EllipsizeMode.END
			};
			taken_icon = (Gtk.Image) Object.new (typeof (Gtk.Image), css_name: "badge-icon");
			taken_box.append (taken_label);
			taken_box.append (taken_icon);
			append (taken_box);
		}

		public void bind (HistoryEntry e) {
			unbind ();
			entry = e;
			css_classes = { e.color };
			update_labels ();
			changed_id = e.changed.connect (update_labels);
		}

		public void unbind () {
			if (entry != null && changed_id != 0) entry.disconnect (changed_id);
			changed_id = 0;
			entry = null;
		}

		private void update_labels () {
			var e = entry;
			name_label.label = e.name;
			dose_label.label = "%s %s ⦁ %s".printf (format_number (e.dose), e.unit,
			                                        Locale.format_time (e.hour, e.minute));
			var taken = Time.from_ms (e.taken_at);
			taken_icon.visible = e.taken_state == 1 || e.taken_state == 2 || e.taken_state == 3;
			taken_box.css_classes = {};

			switch (e.taken_state) {
				case 1:
					taken_label.label = Locale.format_time (taken.get_hour (), taken.get_minute ());
					taken_icon.icon_name = "check-confirmed-symbolic";
					taken_box.css_classes = { "success" };
					break;
				case 2:
					taken_label.label = _("Auto-Confirmed");
					taken_icon.icon_name = "check-auto-confirmed-symbolic";
					taken_box.css_classes = { "success" };
					break;
				case 0:
					taken_label.label = _("Skipped");
					break;
				case -1:
					taken_label.label = _("Missed");
					taken_box.css_classes = { "error" };
					break;
				case 3:
					taken_label.label = _("Confirmed");
					taken_icon.icon_name = "check-confirmed-symbolic";
					taken_box.css_classes = { "success" };
					break;
			}
		}
	}

	namespace HistoryFactory {
		public Gtk.SignalListItemFactory header () {
			var factory = new Gtk.SignalListItemFactory ();
			factory.setup.connect ((f, obj) => {
				((Gtk.ListHeader) obj).child = new Gtk.Label (null) {
					halign = Gtk.Align.START,
					ellipsize = Pango.EllipsizeMode.END
				};
			});
			factory.bind.connect ((f, obj) => {
				var h = (Gtk.ListHeader) obj;
				var e = (HistoryEntry) h.item;
				string s = Time.from_ms (e.taken_at).format (Locale.date_format ());
				if (s.length > 0)
					s = s.get_char (0).toupper ().to_string () + s.substring (s.index_of_nth_char (1));
				((Gtk.Label) h.child).label = s;
			});
			return factory;
		}

		public Gtk.SignalListItemFactory items (Gtk.MultiSelection selection) {
			var factory = new Gtk.SignalListItemFactory ();
			factory.setup.connect ((f, obj) => {
				var item = (Gtk.ListItem) obj;
				var row = new HistoryRow ();
				item.child = row;
				item.selectable = false;
				item.notify["selected"].connect (() => row.check_button.active = item.selected);
				row.check_button.toggled.connect (() => {
					bool want = row.check_button.active;
					if (want == item.selected) return;
					if (want) selection.select_item (item.position, false);
					else selection.unselect_item (item.position);
				});

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
				var row = (HistoryRow) item.child;
				row.bind ((HistoryEntry) item.item);
				row.check_button.active = item.selected;
			});
			factory.unbind.connect ((f, obj) => {
				((HistoryRow) ((Gtk.ListItem) obj).child).unbind ();
			});
			return factory;
		}
	}
}
