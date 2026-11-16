/*
 * Copyright 2023 Diego Povliuk
 * SPDX-License-Identifier: GPL-3.0-only
 */

// Loading, saving and upgrading dosage-treatments.json / dosage-history.json.

namespace Dosage {
	public class Store : Object {
		public GLib.ListStore treatments = new GLib.ListStore (typeof (Treatment));
		public GLib.ListStore history = new GLib.ListStore (typeof (HistoryEntry));

		public string last_update;
		public int treatments_version = -1;
		public int history_version = -1;
		// Never overwrite files we failed to read.
		public bool error_loading = false;

		// Shown to the user by the window.
		public signal void load_error (string message);

		private static Store? instance;

		public static Store get_default () {
			if (instance == null) instance = new Store ();
			return instance;
		}

		private Store () {
			last_update = Time.now_iso ();
		}

		public GLib.File data_dir () {
			var dir = GLib.File.new_for_path (GLib.Environment.get_user_data_dir ());
			try {
				dir.make_directory_with_parents ();
			} catch (Error e) {
				// already exists
			}
			return dir;
		}

		private GLib.File file_for (string type) {
			return data_dir ().get_child ("dosage-%s.json".printf (type));
		}

		// --- loading ------------------------------------------------------------

		public void load () {
			load_file ("treatments");
			load_file ("history");
		}

		private void load_file (string type) {
			var file = file_for (type);
			if (!file.query_exists ()) {
				try {
					string initial = type == "treatments"
						? "{ \"treatments\": [], \"lastUpdate\": \"%s\" }".printf (last_update)
						: "{ \"history\": {} }";
					file.replace_contents (initial.data, null, false, GLib.FileCreateFlags.NONE, null);
					message ("New %s file created at: %s", type, file.get_path ());
				} catch (Error e) {
					warning ("Failed to create new %s file: %s", type, e.message);
				}
			}

			Json.Object root;
			try {
				uint8[] contents;
				file.load_contents (null, out contents, null);
				var parser = new Json.Parser ();
				parser.load_from_data ((string) contents, contents.length);
				var node = parser.get_root ();
				if (node == null || node.get_node_type () != Json.NodeType.OBJECT)
					throw new DataError.INVALID ("not a JSON object");
				root = node.get_object ();
			} catch (Error e) {
				fail ("Error reading %s file.".printf (type), e.message);
				return;
			}

			bool upgraded = type == "treatments" ? Upgrade.treatments (root) : Upgrade.history (root);

			try {
				if (type == "treatments") {
					var list = new Treatment[0];
					var arr = root.get_array_member ("treatments");
					for (uint i = 0; i < arr.get_length (); i++)
						list += Treatment.from_json (arr.get_object_element (i));
					treatments.remove_all ();
					foreach (var t in list) treatments.append (t);
					if (J.is_string (root, "lastUpdate"))
						last_update = root.get_string_member ("lastUpdate");
					treatments_version = J.is_number (root, "version") ? (int) J.num (root, "version") : -1;
				} else {
					var list = new HistoryEntry[0];
					var arr = root.get_array_member ("history");
					for (uint i = 0; i < arr.get_length (); i++)
						list += HistoryEntry.from_json (arr.get_object_element (i));
					sort_newest_first (list);
					history.remove_all ();
					history.splice (0, 0, (Object[]) list);
					history_version = J.is_number (root, "version") ? (int) J.num (root, "version") : -1;
					if (upgraded) save_history ();
				}
			} catch (DataError e) {
				fail (e.message, null);
			}
		}

		private void fail (string message, string? detail) {
			error_loading = true;
			warning ("%s %s", message, detail ?? "");
			load_error (message);
		}

		// newest first (JS: sort((a, b) => b.taken[0] - a.taken[0]))
		private static void sort_newest_first (HistoryEntry[] list) {
			var arr = new GenericArray<HistoryEntry> ();
			foreach (var h in list) arr.add (h);
			arr.sort ((a, b) => a.taken_at < b.taken_at ? 1 : (a.taken_at > b.taken_at ? -1 : 0));
			for (int i = 0; i < list.length; i++) list[i] = arr[i];
		}

		// --- saving -------------------------------------------------------------

		public void save_treatments () {
			if (error_loading) return;
			var sorted = new GenericArray<Treatment> ();
			for (uint i = 0; i < treatments.get_n_items (); i++) sorted.add ((Treatment) treatments.get_item (i));
			sorted.sort ((a, b) => a.name.collate (b.name));

			var arr = new Json.Array ();
			foreach (var t in sorted) arr.add_element (t.to_json ());
			var root = new Json.Object ();
			root.set_array_member ("treatments", arr);
			last_update = Time.now_iso ();
			root.set_string_member ("lastUpdate", last_update);
			if (treatments_version >= 0) root.set_int_member ("version", treatments_version);
			write ("treatments", root);
		}

		public void save_history () {
			if (error_loading) return;
			var arr = new Json.Array ();
			for (uint i = 0; i < history.get_n_items (); i++)
				arr.add_element (((HistoryEntry) history.get_item (i)).to_json ());
			var root = new Json.Object ();
			root.set_array_member ("history", arr);
			if (history_version >= 0) root.set_int_member ("version", history_version);
			write ("history", root);
		}

		private void write (string type, Json.Object root) {
			var node = new Json.Node (Json.NodeType.OBJECT);
			node.set_object (root);
			var gen = new Json.Generator ();
			gen.set_root (node);
			var bytes = new GLib.Bytes (gen.to_data (null).data);
			var file = file_for (type);
			file.replace_contents_bytes_async.begin (bytes, null, false,
				GLib.FileCreateFlags.REPLACE_DESTINATION, null, (obj, res) => {
					try {
						file.replace_contents_async.end (res, null);
					} catch (Error e) {
						warning ("Update of dosage-%s.json failed: %s", type, e.message);
					}
				});
		}
	}
}
