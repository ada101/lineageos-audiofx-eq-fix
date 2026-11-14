#!/usr/bin/env bash
# Temporarily make the equalizer software-only on a device running a *userdebug* LineageOS
# build (needs `adb root`). Nothing is written to a partition: the modified
# /vendor/etc/audio_effects.xml is bind-mounted over the real one and disappears on reboot.
#
#   scripts/try-sw-eq.sh            # apply
#   adb reboot                      # revert (back to stock)
#
# Set ANDROID_SERIAL if more than one device is attached.
set -euo pipefail

adb root >/dev/null; sleep 2
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { echo "adb root failed (needs a userdebug build)" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
adb pull /vendor/etc/audio_effects.xml "$TMP/ae.xml" >/dev/null

python3 - "$TMP/ae.xml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
pat = re.compile(r'[ \t]*<effectProxy name="equalizer"[^>]*>.*?</effectProxy>\n', re.S)
m = pat.findall(s)
if len(m) != 1:
    sys.exit("expected exactly one equalizer effectProxy block, found %d" % len(m))
sw = re.search(r'<libsw library="([^"]+)" uuid="([^"]+)"', m[0])
if not sw:
    sys.exit("no libsw in the equalizer proxy")
new = '        <effect name="equalizer" library="%s" uuid="%s"/>\n' % sw.groups()
open(p, "w").write(pat.sub(new, s))
print("equalizer ->", new.strip())
PY

adb push "$TMP/ae.xml" /data/local/tmp/audio_effects.xml >/dev/null
adb shell "chmod 644 /data/local/tmp/audio_effects.xml
           chcon u:object_r:vendor_configs_file:s0 /data/local/tmp/audio_effects.xml
           mount --bind /data/local/tmp/audio_effects.xml /vendor/etc/audio_effects.xml
           kill \$(pidof android.hardware.audio.service) \$(pidof audioserver)"
sleep 8
# AudioFX (persistent app) must be restarted so it re-creates its effects on the new audio server.
adb shell 'kill $(pidof org.lineageos.audiofx)' || true

echo "Applied until the next reboot. Force-close your music player and start it again."
echo "Check: dumpsys media.audio_flinger  ->  the Equalizer flags should be 00000048 (no 'offloadable')"
echo "       and the player's session should be on a MIXER output thread."
