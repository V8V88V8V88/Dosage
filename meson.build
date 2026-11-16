project(
	'dosage',
	['c', 'vala'],
	version: '2.1.9',
	meson_version: '>= 1.9.0',
	default_options: [
		'warning_level=2',
		'werror=false',
	],
)

i18n = import('i18n')
gnome = import('gnome')

app_id = 'io.github.diegopvlk.Dosage'
is_android = host_machine.system() == 'android'

gtk_dep = dependency('gtk4', version: '>= 4.18')
adw_dep = dependency('libadwaita-1', version: '>= 1.7')
json_dep = dependency(
	'json-glib-1.0',
	fallback: ['json-glib', 'json_glib_dep'],
	default_options: ['introspection=disabled', 'tests=false', 'documentation=disabled', 'man=false', 'nls=disabled'],
)

# Cross builds (Android) disable introspection, so subprojects ship no .vapi and
# meson passes no --pkg for them. Use the host's vapis (declarations only).
foreach dep_pkg : [[adw_dep, 'libadwaita-1'], [json_dep, 'json-glib-1.0']]
	if dep_pkg[0].type_name() == 'internal'
		add_project_arguments('--pkg', dep_pkg[1], language: 'vala')
	endif
endforeach

if is_android
	add_project_arguments('-D', 'ANDROID', language: 'vala')
endif

add_project_arguments('-DGETTEXT_PACKAGE="dosage"', language: 'c')
# Vala-generated C is noisy; keep real warnings visible.
add_project_arguments(
	'-Wno-unused-parameter', '-Wno-unused-variable', '-Wno-unused-but-set-variable',
	'-Wno-discarded-qualifiers', '-Wno-incompatible-pointer-types', '-Wno-sign-compare',
	'-Wno-unused-label', '-Wno-missing-field-initializers',
	language: 'c',
)

subdir('data')
subdir('src')
subdir('po')

if not is_android
	gnome.post_install(
		glib_compile_schemas: true,
		gtk_update_icon_cache: true,
		update_desktop_database: true,
	)
endif
