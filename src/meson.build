conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('VERSION', meson.project_version())
conf.set_quoted('GETTEXT_PACKAGE', 'dosage')
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
config_h = configure_file(output: 'config.h', configuration: conf)

sources = files(
	'application.vala',
	'models.vala',
	'reminders.vala',
	'store.vala',
	'today-factory.vala',
	'upgrade.vala',
	'utils.vala',
	'window.vala',
)
sources += [data_res, 'config.vapi']

deps = [gtk_dep, adw_dep, json_dep, dependency('gio-2.0'), meson.get_compiler('c').find_library('m')]
c_args = ['-include', 'config.h']
vala_args = ['--gresourcesdir', meson.project_build_root() / 'data']

if is_android
	# JNI bridge to the Java reminder code in android/java/.
	sources += files('android/dosage-android.c', 'android/dosage-android.vapi')
	deps += meson.get_compiler('c').find_library('nativehelper') # JNI_GetCreatedJavaVMs (API 31+)
else
	portal_dep = dependency('libportal-gtk4', required: false)
	if portal_dep.found()
		deps += [portal_dep, dependency('libportal')]
		vala_args += ['-D', 'HAVE_PORTAL']
	endif
endif

executable(
	'dosage',
	sources,
	include_directories: include_directories('.', 'android'),
	dependencies: deps,
	c_args: c_args,
	vala_args: vala_args,
	android_exe_type: 'application',
	install: true,
)
