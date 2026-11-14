# Applying the fix to a fresh LineageOS installation

Pick the route that matches your situation.

| You have | Use |
|----------|-----|
| A running phone with Magisk (or can install it) | [Route 1: Magisk module](#route-1-magisk-module-recommended) |
| You build LineageOS yourself | [Route 2: source patch](#route-2-source-patch-rom-builders) |
| Root but no Magisk | [Route 3: replace the APK by hand](#route-3-root-without-magisk) (riskiest) |

Only the **AudioFX** app changes. No effects config, firmware or vendor partition is touched.

## Route 1: Magisk module (recommended)

### Prerequisites

- LineageOS installed and booted once; Magisk installed (the module system is what lets us
  overlay a file in `/system` without modifying the partition).
- A computer with `adb`, `java`, `python3`, `curl`, `openssl`, `keytool`, `zip`, `unzip`
  (only needed to *build*; installing the prebuilt zip needs none of them).

### 1. Check that the prebuilt zip matches your AudioFX

The prebuilt module (`dist/audiofx-prefs-fix.zip`) contains a complete replacement AudioFX built
from **AudioFX 2.2.0, versionCode 20200** (LineageOS 15.1, June 2018). Check yours:

```bash
adb shell dumpsys package org.lineageos.audiofx | grep -E "versionCode|versionName"
```

- `versionCode=20200`: you can use the prebuilt zip (jump to step 3).
- Anything else: build your own from your ROM's APK (step 2). A different build with a different
  `SessionManager` will make the script stop with an explanatory error rather than produce a
  broken APK.

### 2. Build the module from your own stock APK

Get the **stock** APK, not one that is already patched:

```bash
adb pull /system/priv-app/AudioFX/AudioFX.apk
# (If you already installed this module, disable it in Magisk and reboot first, or extract
#  AudioFX.apk from your ROM zip: system/priv-app/AudioFX/AudioFX.apk)
scripts/build.sh ./AudioFX.apk
# -> build/audiofx-prefs-fix.zip
```

The script verifies the APK is signed with the public AOSP platform key (the key that signs the
stock AudioFX on these builds). If it is signed with anything else it aborts, because re-signing
with a different key can change which permissions the app keeps.

### 3. Install

```bash
adb push build/audiofx-prefs-fix.zip /sdcard/       # or dist/audiofx-prefs-fix.zip
```

Magisk app → **Modules** → **Install from storage** → select the zip → **Reboot**.

### 4. Verify

After the reboot:

```bash
adb shell su -c "ls -l /system/priv-app/AudioFX/AudioFX.apk"     # size/date differ from stock
adb shell dumpsys package org.lineageos.audiofx | grep -iE "signatures|PRIVILEGED"
```

Then, with a music app (and set a *very* exaggerated EQ so the effect is obvious, e.g. one band
+12 dB and the rest -12 dB):

1. Reboot, start playing music, **do not** open AudioFX. The effect should already be audible.
2. Open AudioFX. It should stay working.
3. Move sliders (small and large). The sound should follow them.
4. Toggle the on/off switch and change presets. Both should work.

### Undo

Magisk app → Modules → remove the module → reboot. The stock AudioFX is untouched underneath.

### After a ROM update

The module replaces AudioFX wholesale, so it would hide the AudioFX in a newer ROM. After each
ROM update: remove the module, boot, pull the new stock APK, rebuild with `scripts/build.sh`, and
install the new module (Route 1, step 2).

## Route 2: source patch (ROM builders)

Apply the one-line patch to `packages/apps/AudioFX`:

```bash
cd packages/apps/AudioFX
patch -p1 < /path/to/audiofx-fix/patches/lineage-24.0-SessionManager.patch   # or lineage-15.1-...
```

`patches/` contains one for `lineage-15.1` and one for `lineage-24.0`. The line being changed is
present unchanged on the other branches I looked at (16.0, 18.1, 22.2, 23.0), so one of the two
patches should apply (I only dry-run-verified those two). If `patch` fails on your branch, apply by hand:

```java
// src/org/lineageos/audiofx/service/SessionManager.java, in updateBackendLocked():
final SharedPreferences prefs = mDevicePrefs.prefsFor(getCurrentDeviceIdentifier());
```

## Route 3: root without Magisk

Not recommended; only if you understand the risk of editing `/system`.

1. Build the patched APK with `scripts/build.sh` (it is `build/module/system/priv-app/AudioFX/AudioFX.apk`).
2. Remount `/system` read-write (device specific; on GSI/Treble builds this may need
   `adb disable-verity`/`remount` or a dynamic-partition tool), then copy the APK over
   `/system/priv-app/AudioFX/AudioFX.apk` (mode 0644, owner root, label `system_file`).
3. Reboot.

If anything goes wrong the stock APK is gone, so **keep a copy of the original first**.

## Testing without rebooting (developers)

You can try a build without installing anything permanent: bind-mount it over the system APK
and restart the AudioFX process. It lasts until reboot.

```bash
adb push build/signed/unsigned-aligned-signed.apk /data/local/tmp/afx.apk
adb shell su -c "chmod 644 /data/local/tmp/afx.apk; chcon u:object_r:system_file:s0 /data/local/tmp/afx.apk; \
  mount --bind /data/local/tmp/afx.apk /system/priv-app/AudioFX/AudioFX.apk"
adb shell su -c "kill \$(pidof org.lineageos.audiofx)"     # it respawns immediately with the new APK
```

## Gotchas learned the hard way

- **AudioFX is a `persistent` system app.** `am force-stop` does *not* restart it; it keeps running
  with whatever settings it had cached. To restart it, `kill` the process as root (it respawns
  at once). If you edit `shared_prefs/*.xml` while it runs, the change is ignored (and may be
  overwritten).
- On some Magisk setups, root access to `/data/data/<pkg>` can be flaky. `su -mm -c "..."` (a
  single command) worked when plain `su -c` was denied.
- If you stack several bind mounts on the same path, `umount` fails with "busy"; just reboot.
