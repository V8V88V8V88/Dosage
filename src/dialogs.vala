/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Refill, One-Time Entry and Preferences dialogs.

namespace Dosage {
	private void add_save_shortcut (Adw.Dialog dialog, Gtk.Button save) {
		var keys = new Gtk.EventControllerKey ();
		keys.key_pressed.connect ((keyval, keycode, state) => {
			bool mod = (state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK)) != 0;
			if (mod && keyval == Gdk.Key.Return && save.sensitive) {
				save.activate ();
				return true;
			}
			return false;
		});
		((Gtk.Widget) dialog).add_controller (keys);
	}

	private int natural_height (Gtk.Widget w) {
		int min, nat;
		w.measure (Gtk.Orientation.VERTICAL, -1, out min, out nat, null, null);
		return min;
	}

	// --- Refill -------------------------------------------------------------------------

	[GtkTemplate (ui = "/io/github/diegopvlk/Dosage/ui/refill-dialog.ui")]
	public class RefillDialog : Adw.Dialog {
		[GtkChild] unowned Adw.Clamp refillDialogClamp;
		[GtkChild] unowned Adw.SpinRow refillRow;
		[GtkChild] unowned Gtk.Button refillButton;
		[GtkChild] unowned Gtk.Button saveButton;

		private Window window;
		private Treatment treatment;

		public RefillDialog (Window window, Treatment t) {
			this.window = window;
			this.treatment = t;
			refillRow.subtitle = t.name;
			refillRow.value = t.inv_current;
			refillButton.label = "+" + format_number (t.inv_refill);
			add_save_shortcut (this, saveButton);
			content_height = natural_height (refillDialogClamp) + 50;
		}

		[GtkCallback (name = "_refill")]
		private void on_refill () {
			Haptics.tick ();
			refillRow.value += treatment.inv_refill;
		}

		[GtkCallback (name = "_save")]
		private void on_save () {
			Haptics.click ();
			treatment.inv_current = refillRow.value;
			treatment.changed ();
			string sorting = new GLib.Settings (Config.APP_ID).get_string ("treatments-sorting");
			if (sorting == "amount-remaining-more" || sorting == "amount-remaining-less")
				window.sort_treatments (sorting);
			window.update_everything (false, true, true);
			window.schedule_notifications ("saving");
			force_close ();
		}
	}

	// --- One-Time Entry ---------------------------------------------------------------

	[GtkTemplate (ui = "/io/github/diegopvlk/Dosage/ui/one-time-dialog.ui")]
	public class OneTimeDialog : Adw.Dialog {
		[GtkChild] unowned Adw.ToastOverlay toastOverlay;
		[GtkChild] unowned Adw.Clamp oneTimeDialogClamp;
		[GtkChild] unowned Adw.ButtonRow oneTimeBtnRow;
		[GtkChild] unowned Adw.EntryRow medName;
		[GtkChild] unowned Gtk.MenuButton colorButton;
		[GtkChild] unowned Gtk.Popover colorPopover;
		[GtkChild] unowned Gtk.Box colorBox;
		[GtkChild] unowned Adw.EntryRow medUnit;
		[GtkChild] unowned Adw.SpinRow medAmount;
		[GtkChild] unowned Adw.ActionRow medTime;
		[GtkChild] unowned Gtk.ScrolledWindow popoverScrollTime;
		[GtkChild] unowned Adw.ActionRow dateOneEntry;
		[GtkChild] unowned Gtk.Calendar calOneEntry;
		[GtkChild] unowned Gtk.Button confirmBtn;
		[GtkChild] unowned Gtk.Popover oneTimePopover;
		[GtkChild] unowned Gtk.Box oneTimeEntries;

		private Window window;
		private TimePicker picker;
		private bool existing_entry;
		private Adw.Toast toast = new Adw.Toast ("");

		public OneTimeDialog (Window window) {
			this.window = window;
			var now = Time.now ();
			picker = new TimePicker (now.get_hour (), now.get_minute ());
			popoverScrollTime.child = picker;
			medTime.subtitle = picker.text;
			picker.notify["text"].connect (() => medTime.subtitle = picker.text);

			for (var c = colorBox.get_first_child (); c != null; c = c.get_next_sibling ()) {
				var btn = (Gtk.Button) c;
				btn.clicked.connect (() => {
					colorButton.css_classes = { btn.name + "-clr", "circular" };
					colorButton.name = btn.name;
					colorPopover.popdown ();
				});
			}

			// can't log doses in the future
			dateOneEntry.subtitle = now.format ("%x");
			calOneEntry.day_selected.connect (on_date_selected);
			calOneEntry.next_month.connect (on_date_selected);
			calOneEntry.prev_month.connect (on_date_selected);
			calOneEntry.next_year.connect (on_date_selected);
			calOneEntry.prev_year.connect (on_date_selected);

			confirmBtn.clicked.connect (() => {
				if (!is_valid_input ()) return;
				Haptics.click ();
				add_to_history ();
				window.update_everything (false, true, false);
				window.history_changed ();
				force_close ();
				window.schedule_notifications ("saving");
			});

			medName.changed.connect (() => { medName.remove_css_class ("error"); update_confirm (); toast.dismiss (); });
			medUnit.changed.connect (() => { medUnit.remove_css_class ("error"); update_confirm (); toast.dismiss (); });

			setup_treatments_list ();
			content_height = natural_height (oneTimeDialogClamp) + 58;
		}

		private void on_date_selected () {
			var sel = calOneEntry.get_date ();
			if (sel.format ("%F") > Time.now ().format ("%F")) {
				calOneEntry.add_css_class ("calendar-error");
				Haptics.click ();
				Timeout.add (500, () => { calOneEntry.remove_css_class ("calendar-error"); return Source.REMOVE; });
				calOneEntry.select_day (new GLib.DateTime.now_local ());
			}
			dateOneEntry.subtitle = calOneEntry.get_date ().format ("%x");
		}

		private void update_confirm () {
			confirmBtn.sensitive = medName.text.strip () != "" && medUnit.text.strip () != "";
		}

		private Gtk.Button list_button (string label) {
			var btn = new Gtk.Button.with_label (label) { can_shrink = true };
			btn.add_css_class ("flat");
			btn.remove_css_class ("text-button");
			var lbl = (Gtk.Label) btn.get_first_child ();
			lbl.halign = Gtk.Align.START;
			lbl.max_width_chars = 50;
			return btn;
		}

		// "Choose from treatments" popover: New + existing treatments
		private void setup_treatments_list () {
			var btn_new = list_button (_("New"));
			btn_new.clicked.connect (() => {
				oneTimePopover.popdown ();
				medName.text = "";
				medUnit.text = _("Pill(s)");
				colorButton.css_classes = { "circular" };
				colorButton.name = "default";
				medAmount.value = 1;
				medName.sensitive = true;
				medUnit.sensitive = true;
				existing_entry = false;
				toast.dismiss ();
			});
			oneTimeEntries.append (btn_new);

			((Gtk.Box) oneTimeBtnRow.child).append (oneTimePopover);
			oneTimeBtnRow.activated.connect (() => oneTimePopover.popup ());

			var store = Store.get_default ();
			oneTimeBtnRow.sensitive = store.treatments.get_n_items () > 0;
			var sorted = new GenericArray<Treatment> ();
			for (uint i = 0; i < store.treatments.get_n_items (); i++) sorted.add ((Treatment) store.treatments.get_item (i));
			sorted.sort ((a, b) => a.name.collate (b.name));
			foreach (var t in sorted) {
				var btn = list_button (t.name);
				btn.add_css_class ("one-time-name");
				btn.width_request = 120;
				var tr = t;
				btn.clicked.connect (() => {
					colorButton.css_classes = { tr.color + "-clr", "circular" };
					oneTimePopover.popdown ();
					medName.text = tr.name;
					medUnit.text = tr.unit;
					colorButton.name = tr.color;
					medAmount.value = tr.dosage[0].dose;
					medName.sensitive = false;
					medUnit.sensitive = false;
					confirmBtn.sensitive = true;
					existing_entry = true;
					toast.dismiss ();
				});
				oneTimeEntries.append (btn);
			}
		}

		private bool is_valid_input () {
			if (existing_entry) return true;
			var store = Store.get_default ();
			string name = medName.text.strip ().down ();
			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				if (((Treatment) store.treatments.get_item (i)).name.down () == name) {
					toast = new Adw.Toast (_("Name Already on Treatment List"));
					toastOverlay.add_toast (toast);
					medName.add_css_class ("error");
					return false;
				}
			}
			return true;
		}

		private void add_to_history () {
			var store = Store.get_default ();
			var day = calOneEntry.get_date ();
			var when = new GLib.DateTime (Time.local_tz (), day.get_year (), day.get_month (), day.get_day_of_month (),
			                              picker.hours, picker.minutes, Time.now ().get_second ());
			var entry = new HistoryEntry (medName.text.strip (), medUnit.text.strip (), picker.hours, picker.minutes,
			                              medAmount.value, colorButton.name, Time.to_ms (when), 1);
			store.history.insert_sorted (entry, (a, b) => {
				int64 x = ((HistoryEntry) a).taken_at, y = ((HistoryEntry) b).taken_at;
				return x < y ? 1 : (x > y ? -1 : 0);
			});

			bool is_today = Time.to_ms (Time.start_of_day (when)) == Time.today_ms ();
			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				if (t.name != entry.name) continue;
				// logging a scheduled dose for today marks it as taken
				if (is_today)
					foreach (var td in t.dosage)
						if (td.hour == entry.hour && td.minute == entry.minute) td.last_taken = Time.now_iso ();
				if (t.inv_enabled) t.inv_current -= entry.dose;
				t.changed ();
				break;
			}
		}
	}

	// --- Preferences ------------------------------------------------------------------------

	[GtkTemplate (ui = "/io/github/diegopvlk/Dosage/ui/preferences.ui")]
	public class PrefsDialog : Adw.Dialog {
		[GtkChild] unowned Adw.SwitchRow autoStart;
		[GtkChild] unowned Adw.SwitchRow autoClear;
		[GtkChild] unowned Adw.SwitchRow lowNotif;
		[GtkChild] unowned Adw.SwitchRow notifSound;
		[GtkChild] unowned Adw.SwitchRow confirmBtn;
		[GtkChild] unowned Adw.SwitchRow skipBtn;
		[GtkChild] unowned Adw.ComboRow exportHistFmt;
		[GtkChild] unowned Adw.ButtonRow saveHistoryBtn;
		[GtkChild] unowned Adw.ButtonRow saveTreatmentsBtn;

		private GLib.Settings settings = new GLib.Settings (Config.APP_ID);
		private Window window;

		public PrefsDialog (Window window) {
			this.window = window;
			settings.bind ("clear-old-hist", autoClear, "active", GLib.SettingsBindFlags.DEFAULT);
			settings.bind ("low-stock-notif", lowNotif, "active", GLib.SettingsBindFlags.DEFAULT);
			settings.bind ("sound", notifSound, "active", GLib.SettingsBindFlags.DEFAULT);
			settings.bind ("confirm-button", confirmBtn, "active", GLib.SettingsBindFlags.DEFAULT);
			settings.bind ("skip-button", skipBtn, "active", GLib.SettingsBindFlags.DEFAULT);

			autoStart.active = settings.get_boolean ("autostart");
			autoStart.notify["active"].connect (on_autostart);

#if ANDROID
			// Android: reminders are system alarms, so there is no background app to start;
			// sound, notification buttons and low-stock alerts aren't wired up there yet.
			autoStart.visible = false;
			notifSound.visible = false;
			lowNotif.visible = false;
			confirmBtn.get_parent ()?.get_ancestor (typeof (Adw.ExpanderRow))?.set_visible (false);
#endif

			exportHistFmt.selected = settings.get_int ("export-history-format");
			exportHistFmt.notify["selected-item"].connect (() =>
				settings.set_int ("export-history-format", (int) exportHistFmt.selected));
			var store = Store.get_default ();
			saveHistoryBtn.sensitive = store.history.get_n_items () > 0;
			saveTreatmentsBtn.sensitive = store.treatments.get_n_items () > 0;
		}

		private void on_autostart () {
			bool state = autoStart.active;
			settings.set_boolean ("autostart", state);
#if !ANDROID
			if (GLib.Environment.get_variable ("container") == "flatpak") {
#if HAVE_PORTAL
				var portal = new Xdp.Portal ();
				var cmd = new GenericArray<weak string> ();
				cmd.add (Config.APP_ID);
				cmd.add ("--startup");
				portal.request_background.begin (null,
					_("Accept to allow running in the background and receive notifications"),
					cmd, state ? Xdp.BackgroundFlags.AUTOSTART : Xdp.BackgroundFlags.NONE, null, (obj, res) => {
						try {
							portal.request_background.end (res);
						} catch (Error e) {
							if (!state) return;
							var alert = new Adw.AlertDialog (_("An Issue Has Occurred"), e.message);
							alert.add_response ("close", _("Close"));
							alert.present (this);
						}
					});
#endif
			} else {
				string path = GLib.Path.build_filename (GLib.Environment.get_home_dir (), ".config", "autostart",
				                                        "dosage-tracker-startup.desktop");
				try {
					if (state) {
						GLib.DirUtils.create_with_parents (GLib.Path.get_dirname (path), 0755);
						GLib.FileUtils.set_contents (path, "[Desktop Entry]\nType=Application\nName=%s\nExec=dosage --startup\n".printf (Config.APP_ID));
					} else {
						GLib.FileUtils.remove (path);
					}
				} catch (Error e) {
					warning ("autostart: %s", e.message);
				}
			}
#endif
		}

		[GtkCallback (name = "_saveHistory")]
		private void on_save_history () {
			uint fmt = exportHistFmt.selected;
			bool iso = fmt == 1 || fmt == 3;
			bool html = fmt == 2 || fmt == 3;
			var history = Store.get_default ().history;
			string data = html ? Export.history_html (history, iso) : Export.history_csv (history, iso);
			string name = "%s_%s%s%s".printf (_("Dosage"), _("History"), iso ? "_ISO" : "", html ? ".html" : ".csv");
			Export.save.begin (window, name, data);
		}

		[GtkCallback (name = "_saveTreatments")]
		private void on_save_treatments () {
			string name = "%s_%s.html".printf (_("Dosage"), _("Treatments"));
			Export.save.begin (window, name, Export.treatments_html (Store.get_default ().treatments));
		}
	}
}
