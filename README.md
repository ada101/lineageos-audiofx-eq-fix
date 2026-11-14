# LineageOS AudioFX: EQ not applying / stops working after a slider change

A fix for a long-standing LineageOS AudioFX bug, found and fixed on a **Huawei Y6 2018 (ATU-L22)
running a LineageOS 15.1 Treble GSI** (`phhgsi_arm64_a`, AudioFX 2.2.0, versionCode 20200).

## Symptoms

- After a reboot (or when a music app starts playing) AudioFX has **no effect**.
- Opening the AudioFX app makes the effect start working.
- Changing **any** EQ slider (even 0.5 dB) makes the effect stop again, while the UI still shows
  the settings you asked for.
- Changing presets re-applies the effect; the on/off switch does not.
- No errors in logcat, and `dumpsys media.audio_flinger` shows the effect enabled and active the
  whole time.

Reported by many people on many devices and LineageOS versions (15.1 → 17.1 at least).

## Cause

AudioFX keeps one settings file per output device (`shared_prefs/speaker.xml`, `headset.xml`, ...).

- The **UI** writes your changes to the profile for *its* idea of the current device.
- The **service** (`SessionManager.updateBackendLocked`) reads them back through
  `DevicePreferenceManager.getCurrentDevicePrefs()`, which tracks the current device
  *separately* from `SessionManager` and the UI.

On this phone the platform reports two output devices (the built-in speaker and a "wired headset"),
and the three components can end up on different ones. The service then applies a stale or
default profile:

| Moment                | Path used                                  | Result                         |
|-----------------------|--------------------------------------------|--------------------------------|
| Player starts         | service reads its profile                  | wrong values, no audible effect |
| You open AudioFX      | UI pushes each band directly to the effect | works                          |
| You move a slider     | service reads its profile again            | wrong values, effect "stops"   |

The one-line fix makes the service read the profile for the device `SessionManager` itself
reports (the same identifier it already uses for logging):

```diff
-        final SharedPreferences prefs = mDevicePrefs.getCurrentDevicePrefs();
+        final SharedPreferences prefs = mDevicePrefs.prefsFor(getCurrentDeviceIdentifier());
```

The same line is still present in `lineage-24.0` (checked 2026-11-15).

## What is in this repo

| Path | What |
|------|------|
| [`docs/INSTALL.md`](docs/INSTALL.md) | Apply the fix to a fresh LineageOS install |
| [`docs/REPRODUCE.md`](docs/REPRODUCE.md) | How the bug was diagnosed and how to reproduce the fix from scratch |
| `patches/` | Source patches for the AudioFX Java sources (`lineage-15.1`, `lineage-24.0`) |
| `scripts/build.sh` | Builds the patched APK + Magisk module from the stock `AudioFX.apk` |
| `dist/audiofx-prefs-fix.zip` | Prebuilt module for **the exact AudioFX build tested** (see below) |
| `report/` | Draft bug report for LineageOS and notes on how to file it |

## Quick start (rooted with Magisk)

```bash
# Option A: prebuilt (only valid for AudioFX 2.2.0 / versionCode 20200 from lineage-15.1, June 2018)
adb push dist/audiofx-prefs-fix.zip /sdcard/
# Magisk app -> Modules -> Install from storage -> pick the zip -> reboot

# Option B: build from your own stock AudioFX.apk (works for any build the patch applies to)
scripts/build.sh /path/to/stock/AudioFX.apk
```

Details, prerequisites and verification steps are in [`docs/INSTALL.md`](docs/INSTALL.md).

## Caveats

- Tested on **one device / one ROM build**. The prebuilt zip replaces AudioFX wholesale, so only use
  it with the same AudioFX build; otherwise build your own with `scripts/build.sh`.
- The exact reason the service's device and the UI's device diverge on this phone is **not pinned
  down**; the evidence is that the service log showed `dev=headset` while the values it read were
  the ones stored in `speaker.xml`, and that reading the profile via `SessionManager`'s own device
  fixed every symptom. See [`docs/REPRODUCE.md`](docs/REPRODUCE.md#evidence).
- This modifies a system app. Keep a way to undo it (remove the module in Magisk and reboot).

## License

AudioFX is Apache-2.0 (LineageOS / CyanogenMod Project); the patches, scripts and docs here are
under the same license (see [`LICENSE`](LICENSE)). The build script downloads Apktool (Apache-2.0),
uber-apk-signer (Apache-2.0) and the public AOSP platform signing key at build time; none of these
are redistributed in this repo.
