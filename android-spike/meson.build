project('dosage-spike', ['c', 'vala'],
	version: '0.1.0',
	meson_version: '>= 1.9.0',
)

app_id = 'io.github.diegopvlk.Dosage.Spike'

gtk_dep = dependency('gtk4')
adw_dep = dependency('libadwaita-1')

# Cross builds (Android) disable introspection, so the libadwaita subproject
# ships no .vapi and meson passes no --pkg for it. Use the host's vapi instead
# (declarations only, so it is architecture-independent).
if adw_dep.type_name() == 'internal'
	add_project_arguments('--pkg', 'libadwaita-1', language: 'vala')
endif

sources = ['src/main.vala']
extra_deps = []
if host_machine.system() == 'android'
	add_project_arguments('-D', 'ANDROID', language: 'vala')
	# JNI bridge to the Java reminder code in android/java/.
	sources += ['src/android/dosage-android.c', 'src/android/dosage-android.vapi']
	# JNI_GetCreatedJavaVMs (API 31+)
	extra_deps += meson.get_compiler('c').find_library('nativehelper')
endif

executable('dosage-spike',
	sources,
	include_directories: include_directories('src/android'),
	dependencies: [gtk_dep, adw_dep] + extra_deps,
	android_exe_type: 'application',
	install: true,
)

# Pixiewood reads the metainfo from the build dir (build://{arch}/...).
configure_file(
	input: 'data' / app_id + '.metainfo.xml',
	output: app_id + '.metainfo.xml',
	copy: true,
	install: true,
	install_dir: get_option('datadir') / 'metainfo',
)
