#!/usr/bin/env python3
"""Android: compile po/*.po into <prefix>/share/locale/<lang>/LC_MESSAGES/dosage.mo.

Pixiewood only bundles files installed with the "runtime" tag, while
i18n.gettext() uses the "i18n" tag, so translations are installed by this
script (registered with install_tag: 'runtime').
"""
import os
import subprocess
import sys

po_dir, localedir = sys.argv[1], sys.argv[2]
destdir = os.environ.get("MESON_INSTALL_DESTDIR_PREFIX", "")
root = os.path.join(destdir, localedir.lstrip("/")) if destdir else localedir

with open(os.path.join(po_dir, "LINGUAS")) as f:
    langs = [l.strip() for l in f if l.strip() and not l.startswith("#")]

for lang in langs:
    out = os.path.join(root, lang, "LC_MESSAGES")
    os.makedirs(out, exist_ok=True)
    subprocess.run(["msgfmt", "-o", os.path.join(out, "dosage.mo"),
                    os.path.join(po_dir, lang + ".po")], check=True)
print("installed %d translations to %s" % (len(langs), root))
