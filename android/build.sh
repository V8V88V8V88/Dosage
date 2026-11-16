#!/bin/sh
# Build the Android APK with Pixiewood. Usage: android/build.sh [--install]
#   PIXIEWOOD=/path/to/gtk-android-builder/pixiewood  (default: ../pixiewood/pixiewood)
#   ANDROID_SDK=~/Android/Sdk  ANDROID_STUDIO=~/android-studio
set -e
cd "$(dirname "$0")/.."
PW=${PIXIEWOOD:-../pixiewood/pixiewood}
SDK=${ANDROID_SDK:-$HOME/Android/Sdk}
STUDIO=${ANDROID_STUDIO:-$HOME/android-studio}
GTK_TAG=4.24.1

if [ ! -d .pixiewood ]; then
	"$PW" prepare -s "$SDK" -a "$STUDIO" pixiewood.xml
fi

# Pixiewood's GTK wrap tracks main; pin a release and apply our fixes.
if [ "$(git -C subprojects/gtk describe --tags 2>/dev/null)" != "$GTK_TAG" ]; then
	git -C subprojects/gtk fetch --depth 1 origin tag "$GTK_TAG"
	git -C subprojects/gtk checkout -f "$GTK_TAG"
fi
for p in android/patches/gtk-*.patch; do
	git -C subprojects/gtk apply --check "../../$p" 2>/dev/null && git -C subprojects/gtk apply "../../$p" && echo "applied $p"
done

"$PW" generate
python3 android/apply-overlay.py

log=$(mktemp)
if "$PW" build >"$log" 2>&1 && grep -q "BUILD SUCCESSFUL" "$log"; then
	echo "BUILD OK"; rm -f "$log"
else
	grep -E "error|FAILED" "$log" | head -20; echo "BUILD FAILED (log: $log)"; exit 1
fi

apk=.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
[ "$1" = "--install" ] && adb install -r "$apk"
echo "$apk"
