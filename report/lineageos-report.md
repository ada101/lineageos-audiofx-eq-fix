# AudioFX: service reads EQ settings from a different device profile than the UI writes (EQ stops applying)

## Summary

`SessionManager.updateBackendLocked()` reads the saved EQ/effect settings with
`mDevicePrefs.getCurrentDevicePrefs()`, i.e. from the profile of the device tracked by
`DevicePreferenceManager`. The UI writes settings to the profile of the device tracked by
`MasterConfigControl`, and `SessionManager` has its own `mCurrentDevice`. When these three
disagree, the service applies a stale/default profile and the equalizer appears to "stop working".

The line is unchanged in `lineage-24.0` (checked 2026-11-15; also on 16.0, 18.1, 22.2, 23.0 by
inspection), so I believe the bug is still present, but **I have only reproduced it on 15.1**
(see "Limitations").

## Symptoms (as seen on the affected device)

1. After boot, or when a player starts a new session: **no effect**.
2. Opening the AudioFX app: effect **starts working**.
3. Moving **any** EQ slider: effect **stops** again while the UI still shows the new settings.
4. Changing presets re-applies the effect; the on/off switch does not.
5. Nothing in logcat; `dumpsys media.audio_flinger` shows the same effect chain, EQ `ACTIVE`, in the
   working and the broken state.

Users report the same pattern on 15.1 to 17.1 across many devices (e.g. the "AudioFX not working
reliably" issues for 16.0/17.1).

## Analysis

Two paths set the band levels:

- **override path**: `EqualizerManager.setPreset()/setLevel(fromSystem)` → `MasterConfigControl.overrideEqLevels`
  → `SessionManager.setOverrideLevels` → `EffectSet.setEqualizerBandLevel`. Uses the UI's values. Runs
  when the app is opened or the preset changes.
- **service path**: `updateService(EQ_CHANGED)` (slider move) and every new session
  (`MSG_ADD_SESSION` → `updateBackendLocked(ALL_CHANGED)`) → reads
  `mDevicePrefs.getCurrentDevicePrefs()` → `setEqualizerLevelsDecibels`.

Opening the app runs both (override wins, so it works); a slider move or a new session runs only the
service path. Instrumenting the service showed:

```
SVC saved=13.679674;-15.0;-15.0;-15.0;-15.0 dev=headset flags=1     (every slider move)
headset.xml: audiofx.eq.preset.levels = 2.7467518;0.0;0.0;0.0;3.0    (what the UI had just saved)
speaker.xml: audiofx.eq.preset.levels = 13.679674;-15.0;-15.0;-15.0;-15.0
```

`SessionManager.getCurrentDeviceIdentifier()` said `headset`, but the values came from the
`speaker` profile, i.e. `DevicePreferenceManager.mCurrentDevice` was a different device than
`SessionManager.mCurrentDevice`. (Log lines are from an instrumented build, not stock.)

I could not establish exactly why the two diverge. On the affected phone the platform exposes two
outputs at once (`dumpsys audio` lists `speaker, headset` for the music stream; the primary output
device is `0x6 = SPEAKER|WIRED_HEADSET`), and
`AudioOutputChangeListener.getCurrentDevice()` (first connected output) and
`MasterConfigControl.getSystemDevice()` (first output matching `getDevicesForStream(STREAM_MUSIC)`)
use different rules for "the" current device.

## Proposed fix

Use a single source of truth in the service: read the profile for `SessionManager`'s own
current device.

```diff
-        final SharedPreferences prefs = mDevicePrefs.getCurrentDevicePrefs();
+        final SharedPreferences prefs = mDevicePrefs.prefsFor(getCurrentDeviceIdentifier());
```

With this change (patched into the stock 15.1 APK) the effect applies at playback start, after
opening the app, on every slider move, on/off and on preset changes, across clean reboots, with the
stock `audio_effects.conf`. Patch files for `lineage-15.1` and `lineage-24.0` and the full
investigation: <REPO URL>.

A more thorough fix would make `DevicePreferenceManager` and `SessionManager` share one device
state (or have the UI and service agree on which device is "current"), but I haven't attempted that.

## Environment

- Huawei Y6 2018 (ATU-L22), Qualcomm MSM8937, Huawei 8.0 vendor
- LineageOS `15.1-20180626-UNOFFICIAL` Treble GSI (`ro.lineage.device=phhgsi_arm64_a`, Android 8.1.0)
- AudioFX 2.2.0 (versionCode 20200), Magisk 29
- Effects: vendor `audio_effects.conf` with the bundle EQ behind `libeffectproxy` (offload disabled)

## Limitations / what I have *not* verified

- Reproduced only on this unofficial GSI build of 15.1, which is EOL and not an official build.
- Not reproduced on 22.x/23.x/24.x; the claim that it still applies there is from reading the source.
- The root cause of the *divergence* is not pinned down (see above); the fix is a mitigation that
  removes the dependency on the second copy of the device state.
- I am happy to test a proposed change or a debug build.
