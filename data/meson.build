pkgdatadir = join_paths(get_option('datadir'), meson.project_name())
datadir = get_option('prefix') / get_option('datadir')

blueprints = custom_target(
	'blueprints',
	input: files(
		'ui/edit-hist-dialog.blp',
		'ui/med-dialog.blp',
		'ui/one-time-dialog.blp',
		'ui/preferences.blp',
		'ui/refill-dialog.blp',
		'ui/shortcuts-dialog.blp',
		'ui/window.blp',
	),
	output: '.',
	command: [
		find_program('blueprint-compiler'),
		'batch-compile',
		'@OUTPUT@',
		'@CURRENT_SOURCE_DIR@',
		'@INPUT@',
	],
)

# Compiled into the binary (simpler for Android than an installed bundle).
data_res = gnome.compile_resources(
	'dosage-resources',
	'io.github.diegopvlk.Dosage.data.gresource.xml',
	c_name: 'dosage',
	dependencies: blueprints,
)

desktop_file = i18n.merge_file(
	input: 'io.github.diegopvlk.Dosage.desktop.in',
	output: 'io.github.diegopvlk.Dosage.desktop',
	type: 'desktop',
	po_dir: '../po',
	install: true,
	install_dir: join_paths(get_option('datadir'), 'applications'),
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
	test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
	input: 'io.github.diegopvlk.Dosage.appdata.xml.in',
	output: 'io.github.diegopvlk.Dosage.appdata.xml',
	po_dir: '../po',
	install: true,
	install_dir: join_paths(get_option('datadir'), 'metainfo'),
)

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
	test(
		'Validate appstream file',
		appstreamcli,
		args: ['validate', '--no-net', '--explain', appstream_file],
	)
endif

# Pixiewood reads the metainfo with the metainfo XML namespace; add it for Android.
if is_android
	custom_target(
		'android-metainfo',
		input: appstream_file,
		output: 'io.github.diegopvlk.Dosage.android.metainfo.xml',
		command: [
			find_program('sed'),
			'-e', 's|<component type="desktop">|<component type="desktop-application" xmlns="https://specifications.freedesktop.org/metainfo/1.0">|',
			# the Android package name comes from <id>; drop the legacy ".desktop" suffix
			'-e', 's|<id>io.github.diegopvlk.Dosage.desktop</id>|<id>io.github.diegopvlk.Dosage</id>|',
			'@INPUT@',
		],
		capture: true,
		build_by_default: true,
	)
endif

install_data(
	'io.github.diegopvlk.Dosage.gschema.xml',
	install_dir: join_paths(get_option('datadir'), 'glib-2.0/schemas'),
	install_tag: 'runtime', # Pixiewood only bundles runtime-tagged files
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
	test(
		'Validate schema file',
		compile_schemas,
		args: ['--strict', '--dry-run', meson.current_source_dir()],
	)
endif

subdir('icons')

if is_android
	# GNOME's UI font; Android only ships Roboto. (SIL Open Font License)
	adwaita_sans = files(
		'/usr/share/fonts/adwaita-sans-fonts/AdwaitaSans-Regular.ttf',
		'/usr/share/fonts/adwaita-sans-fonts/AdwaitaSans-Italic.ttf',
	)
	install_data(adwaita_sans, install_dir: get_option('datadir') / 'fonts', install_tag: 'runtime')
endif
