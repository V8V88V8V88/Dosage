#!/usr/bin/env python3
"""Add Dosage's native Android pieces to the Gradle project Pixiewood generates.

Pixiewood has no hook for extra Java sources or manifest entries, so run this after
every `pixiewood generate` (and before `pixiewood build`). Safe to run repeatedly.
"""
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
app = os.path.join(root, ".pixiewood", "android", "app", "src", "main")

if not os.path.isdir(app):
    sys.exit("Run `pixiewood generate` first: %s not found" % app)

# 1. Java sources (symlinked, same as Pixiewood does for GTK's own glue code).
pkg_rel = os.path.join("io", "github", "diegopvlk", "dosage", "android")
src = os.path.join(here, "java", pkg_rel)
dst = os.path.join(app, "java", pkg_rel)
os.makedirs(os.path.dirname(dst), exist_ok=True)
if os.path.islink(dst):
    os.remove(dst)
os.symlink(src, dst)

# 2. Manifest: permissions + alarm receiver.
manifest = os.path.join(app, "AndroidManifest.xml")
with open(manifest) as f:
    xml = f.read()

permissions = [
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    "android.permission.VIBRATE",
    "android.permission.RECEIVE_BOOT_COMPLETED",
]
for p in permissions:
    tag = '<uses-permission android:name="%s"/>' % p
    if tag not in xml:
        xml = xml.replace("</manifest>", "  %s\n</manifest>" % tag)

receivers = [
    '<receiver android:name="io.github.diegopvlk.dosage.android.AlarmReceiver" android:exported="false"/>',
    '<receiver android:name="io.github.diegopvlk.dosage.android.ActionReceiver" android:exported="false"/>',
    '<receiver android:name="io.github.diegopvlk.dosage.android.BootReceiver" android:exported="true">'
    '<intent-filter>'
    '<action android:name="android.intent.action.BOOT_COMPLETED"/>'
    '<action android:name="android.intent.action.QUICKBOOT_POWERON"/>'
    '<action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>'
    '</intent-filter></receiver>',
]
for r in receivers:
    name = r.split('android:name="')[1].split('"')[0]
    if name not in xml:
        xml = xml.replace("</application>", "    %s\n  </application>" % r)

with open(manifest, "w") as f:
    f.write(xml)

print("overlay applied:", dst, "+", manifest)
