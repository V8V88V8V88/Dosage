/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

namespace Dosage {
	[GtkTemplate (ui = "/io/github/diegopvlk/Dosage/ui/window.ui")]
	public class Window : Adw.ApplicationWindow {
		[GtkChild] unowned Gtk.ListView todayList;
		[GtkChild] unowned Gtk.Button toggleHistAmountBtn;
		[GtkChild] unowned Gtk.Button removeHistItemsBtn;
		[GtkChild] unowned Gtk.Button unselectHistItemsBtn;
		[GtkChild] unowned Gtk.ListView historyList;
		[GtkChild] unowned Gtk.ListView treatmentsList;
		[GtkChild] unowned Adw.ViewStackPage treatmentsPage;
		[GtkChild] unowned Gtk.MenuButton buttonTreatmentsSorter;
		[GtkChild] unowned Adw.StatusPage emptyToday;
		[GtkChild] unowned Adw.StatusPage emptyHistory;
		[GtkChild] unowned Adw.StatusPage emptyTreatments;
		[GtkChild] unowned Adw.Spinner spinnerToday;
		[GtkChild] unowned Gtk.Button skipBtn;
		[GtkChild] unowned Gtk.Button entryBtn;
		[GtkChild] unowned Adw.ButtonContent entryBtnContent;
		[GtkChild] unowned Gtk.Button unselectBtn;
		[GtkChild] unowned Adw.ViewStack viewStack;
		[GtkChild] unowned Gtk.ToggleButton btnWhenNeeded;
		[GtkChild] unowned Gtk.ToggleButton buttonSearch;
		[GtkChild] unowned Gtk.SearchBar searchBar;
		[GtkChild] unowned Gtk.SearchEntry searchEntry;

		private Store store = Store.get_default ();
		private GLib.Settings settings;

		private GLib.ListStore today_ls = new GLib.ListStore (typeof (TodayItem));
		private Gtk.CustomFilter today_filter;
		private Gtk.MultiSelection today_select;
		private GenericArray<TodayItem> today_items = new GenericArray<TodayItem> ();
		private bool has_when_needed;

		private HashTable<string, uint> scheduled = new HashTable<string, uint> (str_hash, str_equal);
		private bool played;
		private bool delay_dialog;

		public Window (Adw.Application app) {
			Object (application: app);
			settings = new GLib.Settings (Config.APP_ID);
#if !ANDROID
			// On Android the window always fills the screen; a remembered desktop size
			// (e.g. 800x591) larger than the phone breaks input.
			settings.bind ("window-width", this, "default-width", GLib.SettingsBindFlags.DEFAULT);
			settings.bind ("window-height", this, "default-height", GLib.SettingsBindFlags.DEFAULT);
#endif
			settings.changed["clear-old-hist"].connect (() => {
				if (settings.get_boolean ("clear-old-hist")) {
					clear_old_history_entries ();
					set_show_history_amount ();
					store.save_history ();
				}
			});
#if ANDROID
			// libadwaita windows default to a 360px minimum; phones can be narrower.
			width_request = 300;
			height_request = 294;
#endif
			setup_today_list ();
			setup_treatments_list ();
			setup_history_list ();
			setup_view_stack ();
			store.load_error.connect (show_error);

			// let the window draw first, then load (JS: setTimeout(load, 100))
			Timeout.add (100, () => {
				load ();
				return Source.REMOVE;
			});
			clock_tick ();
		}

		// --- startup -------------------------------------------------------------

		private void load () {
			store.load ();
			if (add_missed_items () | clear_old_history_entries ()) store.save_history ();
			withdraw_past_notifications ();
			update_cycle_and_last_up (false);
			store.save_treatments ();
			load_today ();
			history_changed ();
			spinnerToday.visible = false;
			handle_suspension ();
			schedule_notifications (null);
			check_inventory (false);
		}

		private void show_error (string message) {
			var dialog = new Adw.AlertDialog (_("An Issue Has Occurred"), message);
			dialog.add_response ("close", _("Close"));
			dialog.present (this);
		}

		private void clock_tick () {
			int64 last_date = Time.today_ms ();
			// update everything at next midnight
			Timeout.add (2500, () => {
				int64 now = Time.today_ms ();
				if (now > last_date) {
					clear_old_history_entries ();
					add_missed_items ();
					update_everything (false, false, false);
					scroll_history_to (0);
					schedule_notifications (null);
					last_date = now;
				}
				return Source.CONTINUE;
			});
		}

		private void handle_suspension () {
#if !ANDROID
			try {
				var bus = GLib.Bus.get_sync (GLib.BusType.SYSTEM);
				bus.signal_subscribe ("org.freedesktop.login1", "org.freedesktop.login1.Manager",
					"PrepareForSleep", "/org/freedesktop/login1", null, GLib.DBusSignalFlags.NONE,
					() => schedule_notifications ("sleep"));
			} catch (Error e) {
				warning ("login1: %s", e.message);
			}
#endif
		}

		// these are from the closed app, so their actions don't work: remove them
		private void withdraw_past_notifications () {
#if !ANDROID
			var prev = Time.parse_iso (store.last_update) ?? Time.now ();
			prev = prev.add_days (-1);
			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				foreach (var td in t.dosage) {
					var day = Time.now ();
					while (day.compare (prev) > 0) {
						int64 key = Time.to_ms (Time.at_time (day, td.hour, td.minute));
						application.withdraw_notification (key.to_string ());
						day = day.add_days (-1);
					}
				}
			}
#endif
		}

		// --- data updates ---------------------------------------------------------

		// Add history entries for doses not taken since the last update.
		private bool add_missed_items () {
			bool items_added = false;
			var to_add = new GenericArray<HistoryEntry> ();

			var last_update = Time.parse_iso (store.last_update) ?? Time.now ();
			var today = Time.now ();
			// if the app was closed for more than 2 months, only add the last 2 months
			if (Time.days_between (last_update, today) >= 60) {
				last_update = today.add_months (-2);
				store.last_update = Time.to_iso (last_update);
			}
			var today_start = Time.start_of_day (today);

			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				var next = Time.start_of_day (last_update);
				int64 start = Time.day_ms (t.dur_start);
				int64 end = Time.day_ms (t.dur_end);
				int current = t.cycle[2];
				int active = t.cycle[0], inactive = t.cycle[1];
				bool inv_enabled = t.inv_enabled && t.mark_confirmed;

				while (next.compare (today_start) < 0) {
					int64 next_ms = Time.to_ms (next);
					if (t.dur_enabled && (start > next_ms || end < next_ms)) break;

					foreach (var td in t.dosage) {
						bool due = false;
						switch (t.frequency) {
							case "daily": due = true; break;
							case "specific-days":
								foreach (var d in t.days) if (d == Time.weekday (next)) due = true;
								break;
							case "day-of-month": due = t.month_day == next.get_day_of_month (); break;
							case "cycle": due = current <= active; break;
						}

						if (due && td.last_taken == null) {
							int state = -1;
							GLib.DateTime when;
							if (t.mark_confirmed) {
								when = Time.at_time (next, td.hour, td.minute);
								state = 2;
							} else {
								when = Time.at_time (next, 23, 59).add_seconds (59.999);
							}
							to_add.add (new HistoryEntry (t.name, t.unit, td.hour, td.minute, td.dose,
							                              t.color, Time.to_ms (when), state));
							items_added = true;
							if (inv_enabled) t.inv_current -= td.dose;
						}
						// only the first date of confirmed/skipped items doesn't get added
						td.last_taken = null;
					}

					current += 1;
					if (current > active + inactive) current = 1;
					next = next.add_days (1);
					t.changed ();
				}
			}

			to_add.sort ((a, b) => a.taken_at < b.taken_at ? 1 : (a.taken_at > b.taken_at ? -1 : 0));
			var objs = new Object[0];
			foreach (var h in to_add) objs += h;
			store.history.splice (0, 0, objs);
			return items_added;
		}

		private void update_cycle_and_last_up (bool skip_cycle_up) {
			var last_update = Time.parse_iso (store.last_update) ?? Time.now ();
			if (Time.to_ms (Time.start_of_day (last_update)) < Time.today_ms ())
				store.last_update = Time.now_iso ();

			if (skip_cycle_up) return;

			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				if (t.frequency != "cycle") continue;

				if (Time.day_ms (t.dur_start) < Time.today_ms ()) {
					int passed = int.max (0, Time.days_between (last_update, Time.now ()));
					int current = t.cycle[2];
					for (int d = 0; d < passed; d++) {
						current += 1;
						if (current > t.cycle[0] + t.cycle[1]) current = 1;
					}
					t.cycle[2] = current;
					t.cycle_next_date = find_cycle_date (t, null);
				} else {
					t.cycle_next_date = find_cycle_date (t, Time.from_ms (t.dur_start));
				}
				t.changed ();
			}
		}

		private string find_cycle_date (Treatment t, GLib.DateTime? start) {
			int curr = t.cycle[2];
			var next = Time.start_of_day (start ?? Time.now ());
			while (true) {
				if (curr <= t.cycle[0]) break;
				curr += 1;
				if (curr > t.cycle[0] + t.cycle[1]) curr = 1;
				next = next.add_days (1);
			}
			return Time.to_iso (next);
		}

		// Keep only the 30 most recent days of history (if enabled).
		private bool clear_old_history_entries () {
			if (!settings.get_boolean ("clear-old-hist")) return false;
			var days = new GenericArray<int64?> ();
			var keep = new Object[0];
			for (uint i = 0; i < store.history.get_n_items (); i++) {
				var h = (HistoryEntry) store.history.get_item (i);
				int64 day = Time.day_ms (h.taken_at);
				bool known = false;
				foreach (var d in days) if (d == day) known = true;
				if (!known) days.add (day);
			}
			days.sort ((a, b) => a < b ? 1 : (a > b ? -1 : 0));
			int64 oldest_kept = days.length > 30 ? days[29] : int64.MIN;
			for (uint i = 0; i < store.history.get_n_items (); i++) {
				var h = (HistoryEntry) store.history.get_item (i);
				if (Time.day_ms (h.taken_at) >= oldest_kept) keep += h;
			}
			store.history.splice (0, store.history.get_n_items (), keep);
			return true;
		}

		private void check_inventory (bool is_notif_action) {
			treatmentsPage.needs_attention = false;
			treatmentsPage.badge_number = 0;
			bool notify = false;

			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				if (t.inv_enabled && t.inv_current <= t.inv_reminder) {
					treatmentsPage.needs_attention = true;
					treatmentsPage.badge_number += 1;
					if (!notify) notify = !t.has_ended () && !t.is_when_needed;
				}
			}

#if !ANDROID
			if (!settings.get_boolean ("low-stock-notif")) return;
			application.withdraw_notification ("low-stock");
			if (!is_notif_action && notify) {
				var n = new_notification ();
				n.set_icon (new GLib.ThemedIcon.from_names ({ "emblem-important-symbolic", "dialog-information-symbolic" }));
				n.set_title (_("Reminder"));
				// TRANSLATORS: Notification text for when the inventory is low
				n.set_body (_("You have treatments low in stock"));
				application.send_notification ("low-stock", n);
			}
#endif
		}

		public void update_everything (bool is_notif_action, bool skip_cycle_up, bool skip_hist_up) {
			set_show_history_amount ();
			update_cycle_and_last_up (skip_cycle_up);
			store.save_treatments ();
			load_today ();
			update_entry_btn (false);
			check_inventory (is_notif_action);
			unselect_hist_items ();
			if (!skip_hist_up) store.save_history ();
		}

		public void refresh_inventory () {
			check_inventory (false);
		}

		// --- Today page -----------------------------------------------------------

		private void setup_today_list () {
#if ANDROID
			// drag-to-select is a mouse feature; on touch a tap starts a rubberband
			todayList.enable_rubberband = false;
#endif
			todayList.remove_css_class ("view");
			todayList.add_css_class ("background");
			todayList.header_factory = TodayFactory.header (this);
			todayList.factory = TodayFactory.items ();

			today_filter = new Gtk.CustomFilter ((obj) => {
				return settings.get_boolean ("show-when-needed") || !((TodayItem) obj).when_needed;
			});
			var filtered = new Gtk.FilterListModel (today_ls, today_filter);
			var sorted = new Gtk.SortListModel (filtered, null);
			sorted.section_sorter = new TodaySectionSorter ();
			today_select = new Gtk.MultiSelection (sorted);
			todayList.model = today_select;

			today_select.selection_changed.connect (() => {
				today_items = new GenericArray<TodayItem> ();
				var bits = today_select.get_selection ();
				for (uint i = 0; i < today_select.get_n_items (); i++)
					if (bits.contains (i)) today_items.add ((TodayItem) today_select.get_item (i));
				update_entry_btn (today_items.length > 0);
			});
		}

		private void load_today () {
			today_ls.remove_all ();
			has_when_needed = false;
			var list = new GenericArray<TodayItem> ();
			var today = Time.now ();

			for (uint i = 0; i < store.treatments.get_n_items (); i++) {
				var t = (Treatment) store.treatments.get_item (i);
				foreach (var td in t.dosage) {
					if ((t.is_med_day (today) && td.last_taken == null) || t.is_when_needed)
						list.add (new TodayItem (t, td.hour, td.minute, td.dose, t.is_when_needed));
					// only one dose
					if (t.is_when_needed) {
						has_when_needed = true;
						break;
					}
				}
			}

			list.sort ((a, b) => a.name.collate (b.name));
			var objs = new Object[0];
			foreach (var it in list) objs += it;
			today_ls.splice (0, 0, objs);

			bool no_items = today_select.get_n_items () == 0;
			bool no_treatments = store.treatments.get_n_items () == 0;
			buttonTreatmentsSorter.sensitive = !no_treatments;
			emptyTreatments.visible = no_treatments;
			emptyToday.visible = no_items;
			emptyToday.icon_name = no_treatments ? "pill-symbolic" : "all-done-symbolic";
			emptyToday.title = no_treatments ? _("No Treatments") : _("All Done for Today");

			btnWhenNeeded.visible = viewStack.visible_child_name == "today-page" && has_when_needed;
			btnWhenNeeded.active = settings.get_boolean ("show-when-needed");
			if (!no_items) todayList.scroll_to (0, Gtk.ListScrollFlags.NONE, null);
		}

		public void select_today_item (uint position, bool group_check) {
			if (!group_check) Haptics.tick ();
			if (group_check || !today_select.is_selected (position))
				today_select.select_item (position, false);
			else
				today_select.unselect_item (position);
		}

		[GtkCallback (name = "selectTodayItems")]
		private void on_select_today_items (Gtk.ListView list, uint position) {
			select_today_item (position, false);
		}

		[GtkCallback (name = "unselectTodayItems")]
		public void unselect_today_items () {
			today_items = new GenericArray<TodayItem> ();
			today_select.unselect_all ();
			update_entry_btn (false);
		}

		[GtkCallback (name = "setShowWhenNeeded")]
		private void on_set_show_when_needed () {
			unselect_today_items ();
			settings.set_boolean ("show-when-needed", btnWhenNeeded.active);
			load_today ();
		}

		public void toggle_show_when_needed () {
			btnWhenNeeded.active = !btnWhenNeeded.active;
		}

		private void update_entry_btn (bool has_today_items) {
			entryBtnContent.label = has_today_items ? _("Confirm") : _("One-Time Entry");
			var icon = entryBtnContent.get_first_child ()?.get_first_child ();
			if (icon != null) icon.visible = !has_today_items;
			skipBtn.visible = has_today_items;
			unselectBtn.visible = has_today_items;

			bool has_wn = false;
			foreach (var it in today_items) if (it.when_needed) has_wn = true;
			skipBtn.sensitive = !has_wn;

			if (has_today_items) entryBtn.add_css_class ("suggested-action");
			else entryBtn.remove_css_class ("suggested-action");
		}

		[GtkCallback (name = "addTodayOrOneTimeToHist")]
		private void on_add_today_or_one_time (Gtk.Button btn) {
			int taken = int.parse (btn.name); // 1 confirm, 0 skip
			Haptics.click ();
			var now = Time.now ();

			if (today_items.length > 0) {
				var to_add = new Object[0];
				foreach (var it in today_items) {
					to_add += new HistoryEntry (it.name, it.unit,
						it.when_needed ? now.get_hour () : it.hour,
						it.when_needed ? now.get_minute () : it.minute,
						it.dose, it.color, Time.now_ms (), taken);
					if (it.when_needed) update_treat_inventory (it, false);
					else update_treat_inv_and_last_tk (it, taken);
					withdraw_notification_at (it.hour, it.minute);
				}
				// newest first, in list order
				Object[] reversed = {};
				for (int i = to_add.length - 1; i >= 0; i--) reversed += to_add[i];
				store.history.splice (0, 0, reversed);

				update_everything (false, true, false);
				schedule_notifications ("adding");
				scroll_history_to (0);
			} else {
				present_one_time_dialog ();
			}
			update_entry_btn (false);
		}

		public void present_one_time_dialog () {
			if (delay_dialog) return;
			delay_dialog = true;
			Timeout.add (500, () => { delay_dialog = false; return Source.REMOVE; });
			new OneTimeDialog (this).present (this);
		}

		private void update_treat_inv_and_last_tk (TodayItem item, int taken) {
			var t = item.treatment;
			if (t.inv_enabled && taken == 1) t.inv_current -= item.dose;
			foreach (var td in t.dosage)
				if (td.hour == item.hour && td.minute == item.minute) td.last_taken = Time.now_iso ();
			t.changed ();
		}

		private void update_treat_inventory (TodayItem item, bool increase) {
			var t = item.treatment;
			if (!t.inv_enabled) return;
			t.inv_current += increase ? item.dose : -item.dose;
			t.changed ();
		}

		// Confirm/Skip from a notification. Items from a previous day update the
		// "missed" history entry instead of adding a new one.
		private void add_notif_items_to_history (Reminders.Group group, int taken) {
			var to_add = new Object[0];
			int64 today = Time.today_ms ();

			foreach (var it in group.items) {
				int64 date_ls = Time.day_ms (it.date_today_ls);
				if (date_ls != today) {
					var end_of_day = Time.at_time (Time.from_ms (it.date_today_ls), 23, 59).add_seconds (59.999);
					for (uint i = 0; i < store.history.get_n_items (); i++) {
						var h = (HistoryEntry) store.history.get_item (i);
						bool same = h.name == it.name && h.hour == it.hour && h.minute == it.minute &&
							h.unit == it.unit && h.dose == it.dose && Time.day_ms (h.taken_at) == date_ls;
						bool missed = h.taken_state == -1, auto_confirmed = h.taken_state == 2;
						if (same && (missed || auto_confirmed)) {
							h.taken_at = Time.to_ms (end_of_day);
							// 3 for items not confirmed today
							h.taken_state = taken == 1 ? 3 : 0;
							if (taken == 0 && auto_confirmed) update_treat_inventory (it, true);
							else if (taken == 1 && missed) update_treat_inventory (it, false);
							h.changed ();
							break;
						}
					}
				} else {
					to_add += new HistoryEntry (it.name, it.unit, it.hour, it.minute, it.dose,
					                            it.color, Time.now_ms (), taken);
					update_treat_inv_and_last_tk (it, taken);
				}
			}
			Object[] reversed = {};
			for (int i = to_add.length - 1; i >= 0; i--) reversed += to_add[i];
			store.history.splice (0, 0, reversed);
		}

		// --- reminders --------------------------------------------------------------

		private GenericArray<Reminders.Group> today_groups () {
			var groups = new GenericArray<Reminders.Group> ();
			var by_key = new HashTable<string, Reminders.Group> (str_hash, str_equal);
			for (uint i = 0; i < today_select.get_n_items (); i++) {
				var it = (TodayItem) today_select.get_item (i);
				if (it.when_needed) continue;
				int64 key = Time.to_ms (Time.at_time (Time.now (), it.hour, it.minute));
				var g = by_key.lookup (key.to_string ());
				if (g == null) {
					g = new Reminders.Group () { date_key = key, hour = it.hour, minute = it.minute };
					by_key.insert (key.to_string (), g);
					groups.add (g);
				}
				g.items.add (it);
			}
			return groups;
		}

		public void schedule_notifications (string? action) {
			var groups = today_groups ();
#if ANDROID
			Reminders.schedule_android (groups, store.treatments);
#else
			scheduled.foreach ((k, id) => Source.remove (id));
			scheduled.remove_all ();

			foreach (var g in groups) {
				int64 diff = g.date_key - Time.now_ms ();
				var group = g;
				int interval = g.recurring_interval ();
				if (interval > 0) {
					schedule_recurring (group, diff, interval * 60 * 1000, action);
				} else {
					string key = g.date_key.to_string ();
					scheduled.insert (key, Timeout.add ((uint) int64.max (0, diff), () => {
						scheduled.remove (key);
						notify_group (group, action, diff);
						return Source.REMOVE;
					}));
				}
			}
#endif
		}

#if !ANDROID
		private void schedule_recurring (Reminders.Group g, int64 diff, int64 interval_ms, string? action) {
			string key = g.date_key.to_string ();
			scheduled.insert (key, Timeout.add ((uint) int64.max (0, diff), () => {
				notify_group (g, action, diff);
				schedule_recurring (g, interval_ms, interval_ms, action);
				return Source.REMOVE;
			}));
		}

		private GLib.Notification new_notification () {
			var n = new GLib.Notification (_("Dosage"));
			n.set_icon (new GLib.ThemedIcon.from_names ({
				"preferences-system-time-symbolic", "alarm-symbolic", "appointment-soon-symbolic" }));
			n.set_default_action ("app.open");
			return n;
		}

		private void notify_group (Reminders.Group g, string? action, int64 diff) {
			// past notifications would fire instantly after every reschedule (save/add/remove);
			// only send them at startup or after waking from sleep
			if (action != null && action != "sleep" && diff < 0) return;

			var app = application;
			bool single = g.items.length == 1;
			string key = g.date_key.to_string ();

			var n = new_notification ();
			n.set_title (Reminders.title (g));
			n.set_body (Reminders.body (g));
			if (settings.get_boolean ("confirm-button"))
				n.add_button (single ? _("Confirm") : _("Confirm All"), "app.confirm" + key);
			if (settings.get_boolean ("skip-button"))
				n.add_button (single ? _("Skip") : _("Skip All"), "app.skip" + key);
			if (g.increase_priority ()) n.set_priority (GLib.NotificationPriority.URGENT);

			var confirm = new GLib.SimpleAction ("confirm" + key, null);
			confirm.activate.connect (() => on_notification_action (g, 1));
			var skip = new GLib.SimpleAction ("skip" + key, null);
			skip.activate.connect (() => on_notification_action (g, 0));
			app.add_action (confirm);
			app.add_action (skip);

			if (settings.get_boolean ("sound") && action != "sleep" && !played) {
				var ding = Gtk.MediaFile.for_resource ("/io/github/diegopvlk/Dosage/sounds/ding.ogg");
				ding.play ();
				// when using notification buttons, all past items from today are notified;
				// avoid playing the sound for each one
				played = true;
				Timeout.add (5000, () => { played = false; return Source.REMOVE; });
			}

			app.withdraw_notification (key);
			app.send_notification (key, n);
		}

		private void on_notification_action (Reminders.Group g, int taken) {
			add_notif_items_to_history (g, taken);
			update_everything (true, true, false);
			application.withdraw_notification (g.date_key.to_string ());
			schedule_notifications (null);
		}
#endif

		private void withdraw_notification_at (int hour, int minute) {
#if !ANDROID
			int64 key = Time.to_ms (Time.at_time (Time.now (), hour, minute));
			application.withdraw_notification (key.to_string ());
#endif
		}

		// --- Treatments page ---------------------------------------------------------

		private void setup_treatments_list () {
			treatmentsList.factory = TreatmentsFactory.create (this);
			treatmentsList.remove_css_class ("view");
			treatmentsList.add_css_class ("background");
			treatmentsList.model = new Gtk.NoSelection (store.treatments);

#if !ANDROID
			// press a letter to jump to the first treatment starting with it
			var keys = new Gtk.EventControllerKey ();
			keys.key_pressed.connect ((keyval, keycode, state) => {
				if (viewStack.visible_child_name != "treatments-page") return false;
				unichar c = Gdk.keyval_to_unicode (keyval);
				if (c == 0) return false;
				string letter = c.to_string ().down ();
				for (uint i = 0; i < store.treatments.get_n_items (); i++) {
					if (((Treatment) store.treatments.get_item (i)).name.down ().has_prefix (letter)) {
						treatmentsList.scroll_to (i, Gtk.ListScrollFlags.FOCUS, null);
						return true;
					}
				}
				return false;
			});
			((Gtk.Widget) this).add_controller (keys);
#endif
		}

		public void sort_treatments (string sorting) {
			store.treatments.sort ((a, b) => compare_treatments ((Treatment) a, (Treatment) b, sorting));
			scroll_treatments_to (0);
		}

		public void scroll_treatments_to (uint pos) {
			if (store.treatments.get_n_items () > 0)
				treatmentsList.scroll_to (uint.min (pos, store.treatments.get_n_items () - 1),
				                          Gtk.ListScrollFlags.FOCUS, null);
		}

		// position < 0: new treatment
		public void present_med_dialog (int position = -1, bool duplicate = false) {
			// avoid opening multiple dialogs on double click
			if (delay_dialog) return;
			delay_dialog = true;
			Timeout.add (500, () => { delay_dialog = false; return Source.REMOVE; });

			Treatment? source = position >= 0 ? (Treatment) store.treatments.get_item (position) : null;
			new MedDialog (this, source, duplicate).present (this);
		}

		public void present_refill_dialog (Treatment t) {
			if (delay_dialog) return;
			delay_dialog = true;
			Timeout.add (500, () => { delay_dialog = false; return Source.REMOVE; });
			new RefillDialog (this, t).present (this);
		}

		public void confirm_delete (Treatment t, uint position, Adw.Dialog? med_dialog) {
			var dialog = new Adw.AlertDialog (_("Are You Sure?"), null);
			dialog.body_use_markup = true;
			// TRANSLATORS: %s is a placeholder for the name of the treatment
			dialog.body = _("%s will be deleted").replace ("%s", "<b>" + GLib.Markup.escape_text (t.name) + "</b>");
			dialog.add_response ("cancel", _("Cancel"));
			dialog.add_response ("delete", _("Delete"));
			dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
			dialog.response.connect ((response) => {
				if (response != "delete") return;
				Haptics.click ();
				uint pos;
				if (store.treatments.find (t, out pos)) store.treatments.remove (pos);
				med_dialog?.force_close ();
				update_everything (false, true, true);
				schedule_notifications ("deleting");
				scroll_treatments_to (pos > 0 ? pos - 1 : 0);
			});
			dialog.present (med_dialog != null ? (Gtk.Widget) med_dialog : this);
		}

		[GtkCallback (name = "_presentMedDialog")]
		private void on_present_med_dialog (Gtk.ListView list, uint position) {
			present_med_dialog ((int) position, false);
		}

		[GtkCallback (name = "_presentMedDialogNew")]
		private void on_present_med_dialog_new () {
			present_med_dialog ();
		}

		// --- History page ---------------------------------------------------------------

		private Gtk.CustomFilter history_filter;
		private Gtk.FilterListModel history_filtered;
		private Gtk.MultiSelection hist_select;
		private GenericArray<HistoryEntry> hist_items_to_rm = new GenericArray<HistoryEntry> ();
		private bool show_all_hist;
		private bool hist_query;
		private bool hist_more_than_7;
		private bool ctrl_pressed;
		private string query = "";
		private GLib.SimpleAction show_search_action;

		private void setup_history_list () {
			history_filter = new Gtk.CustomFilter (null);
			history_filtered = new Gtk.FilterListModel (store.history, history_filter);
			var sorted = new Gtk.SortListModel (history_filtered, null);
			sorted.section_sorter = new HistorySectionSorter ();
			hist_select = new Gtk.MultiSelection (sorted);

			historyList.remove_css_class ("view");
			historyList.add_css_class ("background");
#if ANDROID
			historyList.enable_rubberband = false;
#endif
			historyList.header_factory = HistoryFactory.header ();
			historyList.factory = HistoryFactory.items (hist_select);
			historyList.model = hist_select;

			hist_select.selection_changed.connect (() => {
				hist_items_to_rm = new GenericArray<HistoryEntry> ();
				var bits = hist_select.get_selection ();
				for (uint i = 0; i < hist_select.get_n_items (); i++)
					if (bits.contains (i)) hist_items_to_rm.add ((HistoryEntry) hist_select.get_item (i));
				bool none = hist_items_to_rm.length == 0;
				removeHistItemsBtn.visible = !none;
				unselectHistItemsBtn.visible = !none;
				toggleHistAmountBtn.visible = none && hist_more_than_7 && !hist_query;
			});

			// search
			buttonSearch.clicked.connect (() => searchBar.search_mode_enabled = !searchBar.search_mode_enabled);
			searchBar.notify["search-mode-enabled"].connect (() => buttonSearch.active = searchBar.search_mode_enabled);
			history_filtered.items_changed.connect (() => {
				bool no_results = history_filtered.get_n_items () == 0;
				emptyHistory.visible = no_results;
				emptyHistory.title = hist_query && no_results ? _("No Results Found") : _("No History");
			});
			searchEntry.search_changed.connect (on_search_changed);

			show_search_action = new GLib.SimpleAction ("showSearch", null);
			show_search_action.activate.connect (() => {
				if (viewStack.visible_child_name != "history-page") return;
				searchBar.search_mode_enabled = true;
				searchEntry.grab_focus ();
			});

			store.history.items_changed.connect (() => {
				hist_more_than_7 = history_has_more_than_7_days ();
				update_history_empty ();
			});

#if !ANDROID
			// ctrl + click selects items to remove
			var keys = new Gtk.EventControllerKey ();
			keys.key_pressed.connect ((keyval, keycode, state) => {
				if (keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R) ctrl_pressed = true;
				return false;
			});
			keys.key_released.connect ((keyval, keycode, state) => {
				if (keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R) ctrl_pressed = false;
			});
			historyList.add_controller (keys);
#endif
		}

		private void update_history_empty () {
			var app = (Gtk.Application) application;
			if (store.history.get_n_items () == 0) {
				searchBar.search_mode_enabled = false;
				emptyHistory.title = _("No History");
				emptyHistory.visible = true;
				buttonSearch.sensitive = false;
				app?.remove_action ("showSearch");
			} else {
				buttonSearch.sensitive = true;
				buttonSearch.visible = viewStack.visible_child_name == "history-page";
				if (app != null) {
					app.add_action (show_search_action);
					app.set_accels_for_action ("app.showSearch", { "<primary>f" });
				}
			}
		}

		// called after loading or editing history
		public void history_changed () {
			hist_more_than_7 = history_has_more_than_7_days ();
			set_show_history_amount ();
			update_history_empty ();
		}

		private void setup_view_stack () {
			viewStack.notify["visible-child"].connect (() => {
				string page = viewStack.visible_child_name;
				btnWhenNeeded.visible = page == "today-page" && has_when_needed;
				buttonSearch.visible = page == "history-page";
				searchBar.visible = page == "history-page";
				buttonTreatmentsSorter.visible = page == "treatments-page";
				Haptics.tick ();
			});
		}

		private static string remove_diacritics (string s) {
			var sb = new StringBuilder ();
			string nfd = s.down ().normalize (-1, GLib.NormalizeMode.NFD);
			unichar c;
			int i = 0;
			while (nfd.get_next_char (ref i, out c))
				if (c.type () != GLib.UnicodeType.NON_SPACING_MARK) sb.append_unichar (c);
			return sb.str;
		}

		private void on_search_changed () {
			query = remove_diacritics (searchEntry.text.strip ());
			if (query == "") {
				hist_query = false;
				show_all_hist = false;
				set_show_history_amount ();
				emptyHistory.visible = false;
				scroll_history_to (0);
				return;
			}
			hist_query = true;
			toggleHistAmountBtn.visible = false;
			string q = query;
			history_filter.set_filter_func ((obj) => remove_diacritics (((HistoryEntry) obj).name).contains (q));
		}

		private bool history_has_more_than_7_days () {
			var days = new GenericSet<string> (str_hash, str_equal);
			for (uint i = 0; i < store.history.get_n_items (); i++) {
				days.add (Time.day_ms (((HistoryEntry) store.history.get_item (i)).taken_at).to_string ());
				if (days.length > 7) return true;
			}
			return false;
		}

		// Show only the last 7 days unless "Show All"
		private void set_show_history_amount () {
			if (hist_query) return;
			unselect_hist_items ();
			toggleHistAmountBtn.visible = hist_more_than_7;
			toggleHistAmountBtn.label = _("Show All");

			if (hist_more_than_7) historyList.remove_css_class ("list-no-extra-padding-bottom");
			else historyList.add_css_class ("list-no-extra-padding-bottom");

			if (!show_all_hist && hist_more_than_7) {
				// the 7 most recent days
				var days = new GenericArray<int64?> ();
				for (uint i = 0; i < store.history.get_n_items () && days.length < 7; i++) {
					int64 d = Time.day_ms (((HistoryEntry) store.history.get_item (i)).taken_at);
					bool known = false;
					foreach (var x in days) if (x == d) known = true;
					if (!known) days.add (d);
				}
				int64 oldest = days[days.length - 1];
				history_filter.set_filter_func ((obj) => Time.day_ms (((HistoryEntry) obj).taken_at) >= oldest);
			} else if (show_all_hist) {
				toggleHistAmountBtn.label = _("Show Less");
				history_filter.set_filter_func (null);
			} else {
				toggleHistAmountBtn.visible = false;
				history_filter.set_filter_func (null);
			}
		}

		public void scroll_history_to (uint pos) {
			Timeout.add (100, () => {
				if (hist_select.get_n_items () > 0)
					historyList.scroll_to (uint.min (pos, hist_select.get_n_items () - 1), Gtk.ListScrollFlags.NONE, null);
				return Source.REMOVE;
			});
		}

		[GtkCallback (name = "_editHistoryItem")]
		private void on_edit_history_item (Gtk.ListView list, uint position) {
			if (ctrl_pressed) {
				if (hist_select.is_selected (position)) hist_select.unselect_item (position);
				else hist_select.select_item (position, false);
				return;
			}
			if (delay_dialog) return;
			delay_dialog = true;
			Timeout.add (500, () => { delay_dialog = false; return Source.REMOVE; });
			new EditHistDialog (this, (HistoryEntry) hist_select.get_item (position)).present (this);
		}

		[GtkCallback (name = "toggleHistoryAmount")]
		private void on_toggle_history_amount () {
			show_all_hist = !show_all_hist;
			set_show_history_amount ();
		}

		[GtkCallback (name = "unselectHistItems")]
		private void unselect_hist_items () {
			hist_select?.unselect_all ();
			hist_items_to_rm = new GenericArray<HistoryEntry> ();
			removeHistItemsBtn.visible = false;
			unselectHistItemsBtn.visible = false;
			toggleHistAmountBtn.visible = hist_more_than_7 && !hist_query;
		}

		// Removing today's entries makes those doses due again and restores stock.
		[GtkCallback (name = "removeHistItems")]
		private void on_remove_hist_items () {
			Haptics.click ();
			int64 today = Time.today_ms ();
			foreach (var e in hist_items_to_rm) {
				if (Time.day_ms (e.taken_at) == today) {
					for (uint i = 0; i < store.treatments.get_n_items (); i++) {
						var t = (Treatment) store.treatments.get_item (i);
						if (t.name != e.name) continue;
						foreach (var td in t.dosage)
							if (td.hour == e.hour && td.minute == e.minute) td.last_taken = null;
						if (t.inv_enabled && (e.taken_state == 1 || e.taken_state == 2)) t.inv_current += e.dose;
						t.changed ();
						break;
					}
				}
				uint pos;
				if (store.history.find (e, out pos)) store.history.remove (pos);
			}
			unselect_hist_items ();
			update_everything (false, true, false);
			schedule_notifications ("removing");
		}

		public void show_page (string name) {
			viewStack.visible_child_name = name;
		}
	}
}
