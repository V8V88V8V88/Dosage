# Dosage on Android

The same Vala code builds for the desktop (meson/Flatpak) and for Android, using
GTK's Android backend and [Pixiewood](https://github.com/sp1ritCS/gtk-android-builder).

```sh
android/build.sh --install
```

Requirements: Android SDK + NDK, Android Studio (for Pixiewood's Svg2Avd), Java >= 17,
meson >= 1.9, valac, blueprint-compiler, and Pixiewood's Perl dependencies.

## Android-specific pieces

- `java/`: AlarmManager reminders, notification Confirm/Skip actions, reboot
  rescheduling, haptics, permissions. Called from `src/android/dosage-android.c` (JNI).
- `apply-overlay.py`: adds the Java code, receivers and permissions to Pixiewood's
  generated Gradle project (Pixiewood has no hook for this).
- `patches/`: GTK fixes, applied by `build.sh`.
- `install-translations.py`: bundles translations (Pixiewood only ships "runtime" files).

## Things GTK/GLib don't handle on Android (worked around in src/)

| Problem | Fix |
|---|---|
| GTK can't get vsync (AChoreographer fetched on the GTK thread) | `patches/gtk-choreographer-ui-thread.patch` |
| fontconfig looks for `/etc/fonts`; GTK extracts the config elsewhere | set `FONTCONFIG_FILE` in `main()` |
| no `XDG_CACHE_HOME`: fontconfig rescans all system fonts each launch | set it to the app cache dir |
| GSettings can't create its dir under `Android/data` | keep config in internal storage |
| GLib has no Android tzdata: local time = UTC | offset from `java.util.TimeZone` |
| no `LANG` | locale from `java.util.Locale` |
| background process gets killed/frozen (ColorOS etc.) | `AlarmManager.setAlarmClock` + battery exemption |
