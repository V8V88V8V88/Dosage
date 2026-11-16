/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

namespace Dosage {
	public class Application : Adw.Application {
		private bool hidden;
		private GLib.Settings settings;

		public Application () {
			Object (application_id: Config.APP_ID,
			        flags: GLib.ApplicationFlags.DEFAULT_FLAGS,
			        resource_base_path: "/io/github/diegopvlk/Dosage/");

			add_main_option ("startup", 0, GLib.OptionFlags.NONE, GLib.OptionArg.NONE,
			                 "Start app hidden at startup", null);
		}

		private Window? window {
			get { return active_window as Window; }
		}

		protected override void startup () {
			base.startup ();
			settings = new GLib.Settings (Config.APP_ID);
#if ANDROID
			DosageAndroid.init ();
			// Use GNOME's font (bundled in the APK) instead of Android's Roboto.
			Gtk.Settings.get_default ().gtk_font_name = "Adwaita Sans 11";
#endif

			var sorter = new GLib.SimpleAction.stateful ("treatments-sorter", GLib.VariantType.STRING,
				new GLib.Variant.string (settings.get_string ("treatments-sorting")));
			sorter.activate.connect ((action, param) => {
				action.set_state (param);
				settings.set_string ("treatments-sorting", param.get_string ());
				window?.sort_treatments (param.get_string ());
			});
			add_action (sorter);

			add_simple ("preferences", { "<primary>comma" }, () => {
				// ported in phase 4
			});
			add_simple ("about", {}, show_about);
			add_simple ("new-one-time", { "<primary>t" }, () => {
				window.unselect_today_items ();
				window.show_page ("today-page");
				window.present_one_time_dialog ();
			});
			add_simple ("new-treatment", { "<primary>n" }, () => {
				window.show_page ("treatments-page");
				window.present_med_dialog ();
			});
			add_simple ("sh-when-needed", { "<primary>h" }, () => window.toggle_show_when_needed ());
			add_simple ("quit", { "<primary>q", "<primary>w" }, () => quit ());
			add_simple ("open", {}, () => {
				activate ();
				active_window?.present ();
			});
		}

		private delegate void ActionFunc ();

		private void add_simple (string name, string[] accels, owned ActionFunc func) {
			var action = new GLib.SimpleAction (name, null);
			action.activate.connect (() => func ());
			add_action (action);
			if (accels.length > 0) set_accels_for_action ("app." + name, accels);
		}

		protected override int handle_local_options (GLib.VariantDict options) {
			if (options.contains ("startup")) hidden = true;
			return -1; // continue
		}

		protected override void activate () {
			var win = active_window;
			if (win == null) {
				win = new Window (this);
#if !ANDROID
				win.hide_on_close = true;
#endif
			}
			if (hidden) {
				win.visible = false;
				hidden = false;
			} else {
				win.present ();
			}
		}

		private void show_about () {
			var about = new Adw.AboutDialog () {
				application_name = _("Dosage"),
				application_icon = Config.APP_ID,
				version = Config.VERSION,
				issue_url = "https://github.com/diegopvlk/Dosage/issues",
				license_type = Gtk.License.GPL_3_0_ONLY,
				copyright = "© 2023 Diego Povliuk",
				translator_credits = _("translator-credits")
			};
			about.add_acknowledgement_section (_("Thanks to These Projects!"), {
				"GNOME https://www.gnome.org/",
				"GTK https://www.gtk.org/",
				"Libadwaita https://gnome.pages.gitlab.gnome.org/libadwaita/",
				"Workbench https://apps.gnome.org/Workbench/",
				"Blueprint https://jwestman.pages.gitlab.gnome.org/blueprint-compiler/index.html",
				"Vala https://vala.dev/",
				"Pixiewood https://github.com/sp1ritCS/gtk-android-builder",
				"Flatpak https://github.com/flatpak/",
			});
			about.add_link ("Donate (PayPal)", "https://www.paypal.com/donate?hosted_button_id=DVL7H35GA66X6");
			about.add_link ("Doar (Pix): diego.pvlk@gmail.com", "diego.pvlk@gmail.com");
			about.add_other_app ("io.github.diegopvlk.Cine", "Cine", "Play your videos");
			about.add_other_app ("io.github.diegopvlk.Tomatillo", "Tomatillo", "Focus better, work smarter");
			about.present (active_window);
		}
	}
}

#if ANDROID
// fontconfig on Android only scans system fonts and XDG_DATA_HOME/fonts, but the APK's
// files land in XDG_DATA_DIRS. Copy GNOME's font (Adwaita Sans) over once.
void install_bundled_fonts () {
	var dest = GLib.File.new_for_path (GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "fonts"));
	foreach (var dir in GLib.Environment.get_system_data_dirs ()) {
		var src = GLib.File.new_for_path (GLib.Path.build_filename (dir, "fonts"));
		if (!src.query_exists ()) continue;
		try {
			dest.make_directory_with_parents ();
		} catch (Error e) {
			// exists
		}
		foreach (var name in new string[] { "AdwaitaSans-Regular.ttf", "AdwaitaSans-Italic.ttf" }) {
			var target = dest.get_child (name);
			if (target.query_exists ()) continue;
			try {
				src.get_child (name).copy (target, GLib.FileCopyFlags.NONE);
			} catch (Error e) {
				warning ("font %s: %s", name, e.message);
			}
		}
		break;
	}
}
#endif

public int main (string[] args) {
#if ANDROID
	// GTK's Android runtime doesn't set XDG_CACHE_HOME, so fontconfig can't save its
	// cache and rescans every system font on each launch (~40-60 s black screen).
	var cache = DosageAndroid.get_cache_dir ();
	if (cache != null) {
		GLib.Environment.set_variable ("XDG_CACHE_HOME", cache, true);
		// GTK points XDG_CONFIG_HOME into Android/data, whose parents apps can't stat,
		// so GLib can't create the GSettings keyfile dir there and settings were lost.
		// Keep config in internal (private) storage instead: <app>/files/config.
		var config = GLib.Path.build_filename (GLib.Path.get_dirname (cache), "files", "config");
		GLib.DirUtils.create_with_parents (GLib.Path.build_filename (config, "glib-2.0", "settings"), 0700);
		GLib.Environment.set_variable ("XDG_CONFIG_HOME", config, true);
	}
	install_bundled_fonts ();
#endif
	GLib.Intl.setlocale (GLib.LocaleCategory.ALL, "");
	GLib.Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
	GLib.Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
	GLib.Intl.textdomain (Config.GETTEXT_PACKAGE);
	return new Dosage.Application ().run (args);
}
