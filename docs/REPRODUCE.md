# How the bug was found, and how to reproduce the fix from scratch

## Environment this was done on

| | |
|--|--|
| Device | Huawei Y6 2018, ATU-L22 (Qualcomm MSM8937), Huawei 8.0 vendor |
| ROM | `15.1-20180626-UNOFFICIAL` Treble GSI (`ro.lineage.device=phhgsi_arm64_a`) |
| AudioFX | 2.2.0, versionCode 20200, `/system/priv-app/AudioFX/AudioFX.apk` (persistent, privileged) |
| Root | Magisk 29 |
| Effects | vendor `/vendor/etc/audio_effects.conf` (Qualcomm: bundle EQ behind an offload proxy, Qualcomm bass boost/virtualizer/reverb) |

AudioFX is signed with the public AOSP **platform** key
(SHA-256 `C8:A2:E9:BC:CF:59:7C:2F:B6:DC:66:BE:E2:93:FC:13:F2:FC:47:EC:77:BC:6B:2B:0D:52:C1:1F:51:19:2A:B8`).

## 1. Reproduce the bug

1. Reboot. Start any music app. **No effect** (set a very exaggerated EQ so it is obvious).
2. Open AudioFX. The effect **starts**.
3. Move any slider. The effect **stops** (UI still shows your setting).
4. Change preset: the effect changes. Toggle the on/off switch: no change.

Seen with two different music apps (Eleven, Musicolet); each new player session repeats the cycle.

## 2. Things that were ruled out (so you don't repeat them)

| Hypothesis | How it was tested | Result |
|-----------|-------------------|--------|
| Effect not attached / disabled | `adb shell dumpsys media.audio_flinger` in each state: same 4 effects on the session, EQ state `ACTIVE`, identical in "working" and "broken" | ruled out |
| Offload effect proxy (`libeffectproxy`) | Magisk module pointing `equalizer` straight at `libbundlewrapper` | no change |
| Native library errors | `logcat` while reproducing | nothing logged by the EQ library or AudioFX |
| Race / timing between effect commands | patched APK with a 40 ms sleep after each EQ call | no change |
| Quickened/stale compiled code | `cmd package compile -f -m speed org.lineageos.audiofx` | no change |
| APK signature / rebuild | rebuilt unsigned, re-signed, original | **inconsistent results; ignore** |

The last row matters: during the investigation some *test builds* appeared to "fix" it only
because of an invalid test (AudioFX is a persistent app, so `force-stop` did not restart it; edits to
its prefs were ignored). Always restart the process with `su -c "kill <pid>"` and confirm the PID changed.

## 3. How the cause was identified

### 3.1 Read the app source

The AudioFX source for the branch is public (`LineageOS/android_packages_apps_AudioFX`). What matters:

- `EqualizerManager.setLevel()` (UI): on a user slider move it persists the levels with
  `setPref(DEVICE_AUDIOFX_EQ_PRESET_LEVELS, ...)` and calls `updateService(EQ_CHANGED)`.
  `setPreset()` / opening the app *also* sends each band to the service through
  `setOverrideLevels()` → `SessionManager` `MSG_UPDATE_EQ_OVERRIDE`.
- `SessionManager.updateBackendLocked()` (service): on `EQ_CHANGED`/`ALL_CHANGED` and on every new
  session it reads the saved levels from
  `mDevicePrefs.getCurrentDevicePrefs()` and calls `setBandLevel` on the effect.

So there are two ways levels reach the effect: **override path** (direct values, works) and
**service path** (reads a prefs file, broken). Opening the app triggers both (override wins);
a slider move triggers only the service path; a new playback session triggers only the service path.

### 3.2 Instrument the service

A small smali patch (log line after each `setBandLevel`, and in `updateBackendLocked`) printed what the
service read and which device it thought was current:

```
SVC saved=13.679674;-15.0;-15.0;-15.0;-15.0 dev=headset flags=1     <- repeated on every slider move
```

while the app's own profile files were:

```
headset.xml : audiofx.eq.preset.levels = 2.7467518;0.0;0.0;0.0;3.0     (what the UI had just written)
speaker.xml : audiofx.eq.preset.levels = 13.679674;-15.0;-15.0;-15.0;-15.0
```

The service claimed `dev=headset` (from `SessionManager.getCurrentDeviceIdentifier()`) yet kept
reading the **speaker** profile (from `DevicePreferenceManager.getCurrentDevicePrefs()`), so it never saw the slider
values. (The two profile files had been identical when the service started, because I had copied one over the other for a test, and diverged as soon as the UI saved a slider change; that is what made the mismatch visible.)

### 3.3 Confirm with the fix

Make the service read the profile for `SessionManager`'s own device. Every symptom disappeared
(effect on playback start, after opening the app, on every slider move, on/off, presets), and
it still worked with the stock effects config restored.

### Evidence

- Service log lines above (from an instrumented build, not the stock one).
- Two profile files diverging as shown.
- Behaviour before/after, tested by listening, across clean reboots.
- `AudioOutputChangeListener` logged a single device: `id: 8 type: 3 (TYPE_WIRED_HEADSET) name: ATU-L22`,
  while `dumpsys audio` listed both `speaker` and `headset` devices for the music stream and the
  primary output reported device `0x6` (`SPEAKER|WIRED_HEADSET`).

**Not established:** exactly *why* `DevicePreferenceManager.mCurrentDevice` ends up on a different
device than `SessionManager.mCurrentDevice` (both are registered for the same callback). It
happens on a phone that exposes two output devices at once; the fix removes the dependency on
the second copy of that state.

## 4. Reproduce the fix from scratch

### Option A: run the script (what produced `dist/`)

```bash
scripts/build.sh /path/to/stock/AudioFX.apk
```

It: downloads Apktool 2.9.3 and uber-apk-signer 1.3.0 (SHA-256 pinned), fetches the public AOSP
platform key and checks its fingerprint, decompiles the APK, applies `scripts/patch_smali.py`,
rebuilds, signs with the platform key, and packages `build/audiofx-prefs-fix.zip`.

### Option B: by hand

```bash
# 1. decompile
java -jar apktool.jar d AudioFX.apk -o src

# 2. edit src/smali/org/lineageos/audiofx/service/SessionManager.smali, in updateBackendLocked,
#    replace
#        iget-object v8, p0, ...;->mDevicePrefs:Lorg/lineageos/audiofx/service/DevicePreferenceManager;
#        invoke-virtual {v8}, ...DevicePreferenceManager;->getCurrentDevicePrefs()Landroid/content/SharedPreferences;
#        move-result-object v3
#    with
#        iget-object v8, p0, Lorg/lineageos/audiofx/service/SessionManager;->mContext:Landroid/content/Context;
#        invoke-virtual {p0}, Lorg/lineageos/audiofx/service/SessionManager;->getCurrentDeviceIdentifier()Ljava/lang/String;
#        move-result-object v9
#        const/4 v10, 0x0
#        invoke-virtual {v8, v9, v10}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
#        move-result-object v3
#    (v8-v10 are free there: v10 is only used by a later debug-log block that reassigns it.)

# 3. rebuild and sign with the same key as the stock app
java -jar apktool.jar b src -o unsigned.apk
java -jar uber-apk-signer.jar -a unsigned.apk --ks platform.jks --ksAlias p \
     --ksPass android --ksKeyPass android -o signed --allowResign
```

`platform.jks` is the public AOSP platform key (`platform.pk8` + `platform.x509.pem` from
`build/target/product/security` at tag `android-8.1.0_r1`) converted to a keystore. See
`scripts/build.sh` for the exact `openssl`/`keytool` commands.

### Test before installing

Use the bind-mount method in [`INSTALL.md`](INSTALL.md#testing-without-rebooting-developers).
Always confirm the AudioFX PID changed after the `kill`.

## 5. Ideas if you want to dig further

- Add a log in `DevicePreferenceManager.onAudioOutputChanged` and `SessionManager.onAudioOutputChanged`
  to see which device each receives and when, on a device that exposes two outputs.
- Compare `AudioOutputChangeListener.getCurrentDevice()` (`getConnectedOutputs().get(0)`) with
  `MasterConfigControl.getSystemDevice()` (first device matching `getDevicesForStream(STREAM_MUSIC)`): the
  service and the UI pick the "current" device with different rules.
