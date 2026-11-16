i18n.gettext('dosage', preset: 'glib')

if is_android
	# Pixiewood only bundles "runtime"-tagged files; i18n.gettext() uses the "i18n" tag.
	meson.add_install_script(
		find_program('python3'),
		meson.project_source_root() / 'android' / 'install-translations.py',
		meson.current_source_dir(),
		get_option('datadir') / 'locale',
		install_tag: 'runtime',
	)
endif
