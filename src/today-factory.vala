/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Today list: section headers (time / "As Needed") and item rows.

namespace Dosage {
	public class TodayHeader : Gtk.Box {
		public Gtk.Button select_group_btn;
		public Gtk.Label when_needed_label;
		public Gtk.Image pin_icon;

		public TodayHeader () {
			Object (hexpand: true);
			select_group_btn = (Gtk.Button) Object.new (typeof (Gtk.Button), css_name: "time-group-selection");
			select_group_btn.add_css_class ("flat");
			select_group_btn.valign = Gtk.Align.START;

			when_needed_label = new Gtk.Label (_("As Needed")) {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				opacity = 0.75
			};
			pin_icon = new Gtk.Image.from_icon_name ("pin-symbolic") {
				opacity = 0.75,
				margin_start = 4
			};
			append (select_group_btn);
			append (when_needed_label);
			append (pin_icon);
		}
	}

	public class TodayRow : Gtk.Box {
		public Gtk.Image icon;
		public Gtk.Label name_label;
		public Gtk.Label dose_and_notes;
		public Adw.SpinRow amount_spin;
		public Gtk.MenuButton amount_btn;
		public Gtk.CheckButton check_button;

		public TodayItem? item;
		private bool updating;

		public TodayRow () {
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
				margin_end = 12,
				margin_top = 4,
				margin_bottom = 4
			};
			append (labels);

			name_label = new Gtk.Label (null) {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				margin_bottom = 1
			};
			name_label.add_css_class ("title");
			labels.append (name_label);

			dose_and_notes = new Gtk.Label (null) {
				halign = Gtk.Align.START,
				justify = Gtk.Justification.FILL,
				wrap = true,
				natural_wrap_mode = Gtk.NaturalWrapMode.NONE
			};
			dose_and_notes.add_css_class ("subtitle");
			labels.append (dose_and_notes);

			var amount_box = (Gtk.ListBox) Object.new (typeof (Gtk.ListBox), css_name: "spinbox");
			amount_box.add_css_class ("spin-today-amount");
			amount_spin = new Adw.SpinRow (new Gtk.Adjustment (1, 0.25, 9999, 0.25, 1, 0), 0.25, 2);
			amount_box.append (amount_spin);

			var popover = new Gtk.Popover () {
				child = new Gtk.ScrolledWindow () {
					propagate_natural_height = true,
					propagate_natural_width = true,
					child = amount_box
				}
			};
			popover.add_css_class ("popover-scrolled");

			amount_btn = new Gtk.MenuButton () {
				tooltip_text = _("Change Dose"),
				icon_name = "view-more-horizontal-symbolic",
				valign = Gtk.Align.CENTER,
				halign = Gtk.Align.CENTER,
				margin_end = 10,
				visible = false,
				popover = popover
			};
			amount_btn.add_css_class ("circular");
			amount_btn.add_css_class ("today-amount");
			append (amount_btn);

			check_button = new Gtk.CheckButton () {
				valign = Gtk.Align.CENTER,
				halign = Gtk.Align.CENTER,
				margin_end = 11,
				can_focus = false,
				can_target = false
			};
			check_button.add_css_class ("selection-mode");
			append (check_button);

			amount_spin.notify["value"].connect (() => {
				if (updating || item == null) return;
				item.dose = amount_spin.value;
				set_dose_and_notes ();
			});

			// leaving selection resets the dose to the scheduled one
			amount_btn.notify["visible"].connect (() => {
				if (!amount_btn.visible && item != null) {
					item.dose = item.original_dose;
					set_dose_and_notes ();
				}
			});
		}

		public void set_selected (bool selected) {
			check_button.active = selected;
			amount_btn.visible = selected;
		}

		public void set_dose_and_notes () {
			string label = "%s %s".printf (format_number (item.dose), item.unit);
			if (item.notes != "") label += " ⦁ " + item.notes;
			dose_and_notes.label = label;
		}

		public void bind (TodayItem item) {
			this.item = item;
			name_label.label = item.name;
			set_dose_and_notes ();
			updating = true;
			amount_spin.value = item.dose;
			updating = false;
			icon.icon_name = item.icon;
			css_classes = { "card-stripe", item.color };
			opacity = item.when_needed ? 0.75 : 1;
		}
	}

	namespace TodayFactory {
		public Gtk.SignalListItemFactory header (Window window) {
			var factory = new Gtk.SignalListItemFactory ();
			factory.setup.connect ((f, obj) => {
				var list_header = (Gtk.ListHeader) obj;
				var header = new TodayHeader ();
				header.select_group_btn.clicked.connect (() => {
					for (uint pos = list_header.start; pos < list_header.end; pos++)
						window.select_today_item (pos, true);
				});
				list_header.child = header;
			});
			factory.bind.connect ((f, obj) => {
				var list_header = (Gtk.ListHeader) obj;
				var header = (TodayHeader) list_header.child;
				var item = (TodayItem) list_header.item;
				header.when_needed_label.visible = item.when_needed;
				header.pin_icon.visible = item.when_needed;
				header.select_group_btn.visible = !item.when_needed;
				if (!item.when_needed)
					header.select_group_btn.label = Locale.format_time (item.hour, item.minute);
			});
			return factory;
		}

		public Gtk.SignalListItemFactory items () {
			var factory = new Gtk.SignalListItemFactory ();
			factory.setup.connect ((f, obj) => {
				var list_item = (Gtk.ListItem) obj;
				var row = new TodayRow ();
				list_item.child = row;
				list_item.selectable = false;
				list_item.notify["selected"].connect (() => row.set_selected (list_item.selected));

				// activate item with space bar
				var keys = new Gtk.EventControllerKey ();
				keys.key_pressed.connect ((keyval, keycode, state) => {
					if (keyval == Gdk.Key.space) {
						var list_view = row.get_ancestor (typeof (Gtk.ListView)) as Gtk.ListView;
						if (list_view != null) GLib.Signal.emit_by_name (list_view, "activate", list_item.position);
						return true;
					}
					return false;
				});
				row.add_controller (keys);
			});
			factory.bind.connect ((f, obj) => {
				var list_item = (Gtk.ListItem) obj;
				var row = (TodayRow) list_item.child;
				row.bind ((TodayItem) list_item.item);
				row.set_selected (list_item.selected);
			});
			return factory;
		}
	}
}
