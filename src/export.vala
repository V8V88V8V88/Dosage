/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// History (CSV/HTML) and treatments (HTML) export, ports of
// utils/getHistoryExportFile.js, utils/getTreatmentsExportFile.js and utils/saveFiles.js.

namespace Dosage.Export {
	private string esc (string s) {
		return s.replace ("&", "&amp;").replace ("<", "&lt;").replace (">", "&gt;")
			.replace ("\"", "&quot;").replace ("'", "&#39;");
	}

	private string csv (string s) {
		return "\"" + s.replace ("\"", "\"\"") + "\"";
	}

	private string date_string (int64 ms, bool iso) {
		var d = Time.from_ms (ms);
		return iso ? d.to_utc ().format ("%Y-%m-%d") : d.format ("%x");
	}

	private string status_of (HistoryEntry e, out string css_class, out string time_confirmed) {
		time_confirmed = "";
		css_class = "status-confirmed";
		switch (e.taken_state) {
			case -1: css_class = "status-missed"; return _("Missed");
			case 0: css_class = "status-skipped"; return _("Skipped");
			case 1:
				var t = Time.from_ms (e.taken_at);
				time_confirmed = Locale.format_time (t.get_hour (), t.get_minute ());
				return _("Confirmed");
			case 2: return _("Auto-Confirmed");
			default: return _("Confirmed") + " (%s)".printf (_("Time Unknown"));
		}
	}

	private string[] header () {
		return { _("Date"), _("Time"), _("Name"), _("Dose"), _("Status"), _("Time Confirmed") };
	}

	public string history_csv (GLib.ListModel history, bool iso) {
		var sb = new StringBuilder ();
		string[] h = {};
		foreach (var s in header ()) h += s;
		sb.append (string.joinv (",", h));
		for (uint i = 0; i < history.get_n_items (); i++) {
			var e = (HistoryEntry) history.get_item (i);
			string cls, confirmed;
			string status = status_of (e, out cls, out confirmed);
			sb.append ("\n");
			sb.append (string.joinv (",", {
				csv (date_string (e.taken_at, iso)), csv (Locale.format_time (e.hour, e.minute)),
				csv (e.name), csv ("%s %s".printf (format_number (e.dose), e.unit)),
				csv (status), csv (confirmed) }));
		}
		return sb.str;
	}

	public string history_html (GLib.ListModel history, bool iso) {
		var sb = new StringBuilder ();
		sb.append ("<style>:root{color-scheme:light dark;}");
		sb.append (".history-table{width:100%;border-collapse:collapse;font-family:'Adwaita Sans',Inter,Roboto,Arial,system-ui,sans-serif;font-feature-settings:'tnum';overflow-x:auto;}");
		sb.append (".history-table th,.history-table td{padding:0.4rem;border:1px solid light-dark(#77767B,#5E5C64);}");
		sb.append (".history-table thead th{background-color:light-dark(#5E5C64,#9A9996);color:light-dark(#FFFFFF,#000000);font-weight:700;position:sticky;top:0;z-index:2;}");
		sb.append (".history-table tbody tr:nth-child(even){background-color:light-dark(#F6F5F4,#2b2b2b);}");
		sb.append (".history-table tbody tr:hover{background-color:light-dark(#C0BFBC,#4c4c4c);}");
		sb.append (".status-missed{color:light-dark(#C01C28,#ff6b6b);font-weight:600;}");
		sb.append (".status-skipped{color:light-dark(#3D3846,#DEDDDA);font-weight:600;}");
		sb.append (".status-confirmed{color:light-dark(#26A269,#2EC27E);font-weight:600;}</style>");
		sb.append ("<table class=\"history-table\"><thead><tr>");
		foreach (var label in header ()) sb.append ("<th>%s</th>".printf (esc (label)));
		sb.append ("</tr></thead><tbody>");
		for (uint i = 0; i < history.get_n_items (); i++) {
			var e = (HistoryEntry) history.get_item (i);
			string cls, confirmed;
			string status = status_of (e, out cls, out confirmed);
			sb.append ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class=\"%s\">%s</td><td>%s</td></tr>".printf (
				esc (date_string (e.taken_at, iso)), esc (Locale.format_time (e.hour, e.minute)), esc (e.name),
				esc ("%s %s".printf (format_number (e.dose), e.unit)), cls, esc (status), esc (confirmed)));
		}
		sb.append ("</tbody></table>");
		return sb.str;
	}

	private string color_css (string color) {
		switch (color) {
			case "blue": return "light-dark(#3584e4, #6ab9ff)";
			case "red": return "light-dark(#e62d42, #ff7077)";
			case "yellow": return "light-dark(#c88800, #eba93d)";
			case "purple": return "light-dark(#9141ac, #e391ff)";
			case "cyan": return "light-dark(#2190a4, #64c8dd)";
			case "green": return "light-dark(#3a944a, #57e389)";
			case "orange": return "light-dark(#ed5b00, #ff8542)";
			default: return "light-dark(#4a4a52, #dfe0eb)";
		}
	}

	private string fmt_date (int64 ms) {
		return Time.from_ms (ms).format ("%-e %b %Y");
	}

	private string group_html (string title, GenericArray<Treatment> list, bool when_needed, bool ended) {
		if (list.length == 0) return "";
		var sb = new StringBuilder ();
		sb.append ("<div style=\"padding-top: 24px;\"><h2 style=\"margin-bottom: 8px; color: light-dark(#555, #ccc); break-before: page;\">%s</h2>".printf (esc (title)));
		sb.append ("<div style=\"display: flex; flex-wrap: wrap; gap: 12px;\">");
		foreach (var t in list) {
			string freq = "";
			switch (t.frequency) {
				case "daily": freq = _("Daily"); break;
				case "specific-days":
					string[] names = {};
					foreach (var d in t.days) names += Locale.day_label (d, true);
					freq = string.joinv (", ", names);
					break;
				// TRANSLATORS: Context: 2 day(s) on, 1 day(s) off
				case "day-of-month": freq = _("Day of Month") + ": %d".printf (t.month_day); break;
				case "cycle": freq = "%d %s, %d %s".printf (t.cycle[0], _("day(s) on"), t.cycle[1], _("day(s) off")); break;
			}

			string dosage;
			string duration = "";
			if (when_needed) {
				dosage = "<p><b>%s %s</b> %s</p>".printf (format_number (t.dosage[0].dose), esc (t.unit), esc (_("As Needed")));
			} else {
				string[] lines = {};
				// TRANSLATORS: Context: 1 Pill at 19:00
				foreach (var td in t.dosage)
					lines += "<b>%s %s</b> %s %s".printf (format_number (td.dose), esc (t.unit), esc (_("at")),
					                                     Locale.format_time (td.hour, td.minute));
				dosage = "<p>%s</p>".printf (string.joinv ("<br>", lines));
				if (t.dur_enabled) {
					duration = "<p><b>%s:</b><br>%s<br>%s</p>".printf (esc (_("Duration")),
						ended ? esc (_("Started on")) + " " + fmt_date (t.dur_start) : esc (_("Start")) + ": " + fmt_date (t.dur_start),
						ended ? esc (_("Ended on")) + " " + fmt_date (t.dur_end) : esc (_("End")) + ": " + fmt_date (t.dur_end));
				}
			}
			string notes = t.notes != ""
				? "<p style=\"font-style: italic; color: light-dark(#555, #aaa);\"><b>%s:</b> %s</p>".printf (esc (_("Notes")), esc (t.notes))
				: "";

			sb.append ("<div style=\"border: 1px solid light-dark(#ccc, rgba(0,0,0,0.3)); border-left: 5px solid %s; padding: 10px 10px 0 10px; border-radius: 12px; width: 286px; box-shadow: 2px 2px 8px light-dark(rgba(0,0,0,0.15), rgba(0,0,0,0.3)); background-color: light-dark(#ffffff, #343437); color: light-dark(#000, #eee); break-inside: avoid;\">".printf (color_css (t.color)));
			sb.append ("<h3 style=\"margin-top: -4px; margin-bottom: 6px; color: light-dark(#333, #fff);\">%s</h3>".printf (esc (t.name)));
			sb.append ("<hr style=\"border: none; border-bottom: 1px solid light-dark(#ccc, #17171a); margin: 0 -10px 8px -10px;\">");
			sb.append ("<p>%s</p>%s%s%s</div>".printf (ended ? "" : "<b>%s</b>".printf (esc (freq)), dosage, notes, duration));
		}
		sb.append ("</div></div>");
		return sb.str;
	}

	public string treatments_html (GLib.ListModel treatments) {
		int64 now = Time.now_ms ();
		var ongoing = new GenericArray<Treatment> ();
		var ended = new GenericArray<Treatment> ();
		var as_needed = new GenericArray<Treatment> ();
		var sorted = new GenericArray<Treatment> ();
		for (uint i = 0; i < treatments.get_n_items (); i++) sorted.add ((Treatment) treatments.get_item (i));
		sorted.sort ((a, b) => a.name.collate (b.name));
		foreach (var t in sorted) {
			if (t.is_when_needed) as_needed.add (t);
			else if (t.dur_enabled && t.dur_end < now) ended.add (t);
			else ongoing.add (t);
		}
		string title = esc (_("Dosage")) + " - " + esc (_("Treatments"));
		var sb = new StringBuilder ();
		sb.append ("<style>p {margin: 8px auto; font-size: 14px;} :root {color-scheme: light dark;} * {font-family: 'Adwaita Sans', Inter, Roboto, Arial, system-ui, sans-serif;font-feature-settings: 'tnum';} body {background-color: light-dark(#fafafb, #222226)}</style>");
		sb.append ("<title>%s</title><br><div style=\"padding: 0 16px 16px 16px; color: light-dark(#000, #eee);\"><h1>%s</h1>".printf (title, title));
		sb.append ("<h2>%s %s</h2>".printf (esc (_("Generated on")), fmt_date (now)));
		sb.append (group_html (_("Ongoing"), ongoing, false, false));
		sb.append (group_html (_("Non-scheduled"), as_needed, true, false));
		sb.append (group_html (_("Finished"), ended, false, true));
		sb.append ("</div>");
		return sb.str;
	}

	// Ask where to save, then write. Gtk.FileDialog uses the portal on desktop and
	// Android's document picker on Android.
	public async void save (Gtk.Window parent, string initial_name, string contents) {
		var dialog = new Gtk.FileDialog () { initial_name = initial_name };
		try {
			var file = yield dialog.save (parent, null);
			yield file.replace_contents_async (contents.data, null, false, GLib.FileCreateFlags.NONE, null, null);
		} catch (Error e) {
			if (!(e is Gtk.DialogError.DISMISSED)) warning ("export: %s", e.message);
		}
	}
}
