# Dosage Android spike (Vala + libadwaita + Pixiewood)

Proof of concept for running Dosage on Android with real GTK 4 / libadwaita,
built with [Pixiewood](https://github.com/sp1ritCS/gtk-android-builder).

Verified on a OnePlus CPH2487 (Android 16, arm64):
- the libadwaita UI renders and handles touch input
- reminders fire on time with the app closed and battery-optimised (native
  `AlarmManager.setAlarmClock` + `BroadcastReceiver`), and tapping one opens the app

## Build

Requirements: Android SDK + NDK, Android Studio (for `Svg2Avd`), Java >= 17,
meson >= 1.9, valac, plus Pixiewood's dependencies (see its README; on Fedora:
`perl(Archive::Tar) perl(Glib) perl(Glib::Object::Introspection) perl(IPC::Run)
perl(Set::Scalar) glslc sassc`).

```sh
PW=path/to/gtk-android-builder/pixiewood
$PW prepare -s ~/Android/Sdk -a ~/android-studio pixiewood.xml
# Pin GTK to a stable release (Pixiewood's wrap tracks main):
git -C subprojects/gtk fetch --depth 1 origin tag 4.24.1 && git -C subprojects/gtk checkout 4.24.1
$PW generate
python3 android/apply-overlay.py   # after every `generate`
$PW build                          # check for "BUILD SUCCESSFUL"; failures are easy to miss
adb install -r .pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

Logs: `adb logcat` (GLib output is forwarded by GTK's runtime; stdout/stderr are discarded).
Note that `adb screencap` cannot capture GTK's surface, so screenshots come out blank.

## Workarounds found

| Problem | Fix |
|---|---|
| `{arch}` in the manifest's `build://` URI is rejected | use a literal arch: `build://aarch64/...` |
| Pixiewood looks for Android Studio in `/opt` | pass `-a ~/android-studio` |
| Cross builds have no libadwaita `.vapi` (introspection disabled) | `--pkg libadwaita-1` with the host vapi (`meson.build`) |
| No way to add Java code / manifest entries | `android/apply-overlay.py` symlinks `android/java` and patches the manifest |
| 40–60 s black screen on every launch | GTK doesn't set `XDG_CACHE_HOME`, so fontconfig rescans ~160 MB of system fonts each time; set it to `Context.getCacheDir()` in `main()` |
| Local time shown as UTC | GLib has no Android tzdata support; take the offset from `java.util.TimeZone` |
| libadwaita's 360 px minimum width > phone's 355 px | lower `width_request` |
| Reminders ~1–2 min late, process frozen (ColorOS) | `setAlarmClock()` instead of `setExactAndAllowWhileIdle()`, and ask for battery-optimisation exemption |
| `AChoreographer_getInstance() failed` warning | harmless; GTK falls back to an idle frame clock |

## Not done yet
- Reschedule reminders after reboot (`BOOT_COMPLETED` receiver)
- Notification actions (Confirm / Skip / Snooze)
