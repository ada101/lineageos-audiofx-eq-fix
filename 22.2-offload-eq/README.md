# AudioFX on LineageOS 22.2 (OnePlus 5T): EQ silent on offloaded playback

Found and verified on a **OnePlus 5T (dumpling), official `lineage-22.2-20261110-nightly-dumpling-signed`**
(userdebug build, `adb root` available; AudioFX 2.2.0), with the stock player (Twelve) and Musicolet.

## Symptoms

- **Twelve (stock player):** AudioFX turns on, but only **bass boost, virtualizer, reverb and the on/off
  switch** have an (often mild) audible effect. **The equalizer does nothing**, whatever the sliders say.
- **Musicolet:** AudioFX has no effect at all. (Different cause, see below.)

## Causes (two separate things)

### 1. Twelve: the EQ runs on the offload (DSP) path, where it has no audible effect

Twelve plays compressed MP3 through the hardware **offload** output (`AUDIO_OUTPUT_FLAG_COMPRESS_OFFLOAD`).
For offloaded playback, AudioFlinger attaches the **hardware (offload) implementation** of each effect via
the effect proxies in `audio_effects.xml` (`libqcompostprocbundle`). On this device that implementation of the
**equalizer** has no audible effect (bass boost, virtualizer and reverb do work, mildly).

Evidence:

- On the offload thread the chain is healthy (EQ `ACTIVE`, no errors in logcat) yet silent:
  [`evidence/chain-offload-stock.txt`](evidence/chain-offload-stock.txt).
- **A/B on the same device and player** (listening test):

  | Setup | Output thread | EQ audible? |
  |-------|---------------|-------------|
  | stock | `OFFLOAD` | no |
  | offload disabled (`audio.offload.disable=true`, `vendor.audio.offload.track.enable=false`, audio services restarted) | `MIXER` | yes, full strength |
  | stock offload, **EQ made software-only** in `audio_effects.xml` | `MIXER` | **yes, full strength** |

- With the EQ software-only the equalizer is **not offloadable**, so audio policy keeps the track off the
  offload output while the EQ is enabled: [`evidence/chain-mixer-sw-eq.txt`](evidence/chain-mixer-sw-eq.txt)
  (EQ flags `00000048`, no "offloadable", on a `MIXER` thread).
- Because AudioFX enables the EQ only while it is switched on, offload (and its battery saving) should come
  back when AudioFX is off. (I did not measure battery use.)

**Why the offload EQ is silent is not established.** What was ruled out:

- *Device never sent to the EQ.* The offload EQ context's `device` stays 0 unless it receives
  `EFFECT_CMD_SET_DEVICE`, and Android only sends that to effects whose descriptor has
  `EFFECT_FLAG_DEVICE_IND` (bass boost and virtualizer have it; the EQ and reverb don't, and the proxy copies
  the *software* effect's flags). I tested giving the EQ that flag (binary-patched descriptors in
  `libqcompostprocbundle.so`, and in `libbundlewrapper.so` so the proxy exposed it: Android then reported
  `device indication: requires updates` for the EQ). **No change**: still silent.
- Errors / rejected commands: none logged; the effect is `ACTIVE` and AudioFX gets no failure from `setBandLevel`.

Remaining suspects (untested): the DSP topology for this device/route has no EQ module active in the
compress-offload path; the parameter format sent by `eq_send_params` (`post_proc/effect_api.c`) not matching what the
DSP firmware expects for the 5-band EQ. A fix at that level would need DSP/ACDB or Qualcomm-HAL debugging.

### 2. Musicolet: it doesn't announce its audio session

AudioFX 22.2 attaches **only** when a player broadcasts `android.media.action.OPEN_AUDIO_EFFECT_CONTROL_SESSION`.
Twelve does (the activity-manager broadcast history shows it); Musicolet doesn't by default.
In Musicolet: **⋮ → Settings → Audio → Equalizer → "System Equalizer"** makes it announce its session; after that
AudioFX works in Musicolet (verified on the device). Manual check:

```bash
adb shell dumpsys activity broadcasts | grep -A1 OPEN_AUDIO_EFFECT_CONTROL_SESSION
# you should see android.media.extra.PACKAGE_NAME=<your player>
```

(Other players may need similar configuration; Wavelet's player-setup docs list known ones.)

## The fix for (1)

Make the equalizer a plain software effect in `audio_effects.xml`:

```diff
-        <effectProxy name="equalizer" library="proxy" uuid="c8e70ecd-48ca-456e-8a4f-0002a5d5c51b">
-            <libsw library="bundle" uuid="ce772f20-847d-11df-bb17-0002a5d5c51b"/>
-            <libhw library="offload_bundle" uuid="a0dac280-401c-11e3-9379-0002a5d5c51b"/>
-        </effectProxy>
+        <effect name="equalizer" library="bundle" uuid="ce772f20-847d-11df-bb17-0002a5d5c51b"/>
```

- Patch against the LineageOS device tree file (`android_device_oneplus_msm8998-common`, `audio/audio_effects.xml`, `lineage-22.2`):
  [`patches/dumpling-audio_effects-sw-equalizer.patch`](patches/dumpling-audio_effects-sw-equalizer.patch)
  (dry-run applies to the real file).
- **Trade-off:** while AudioFX's EQ is on, music is decoded and mixed by the CPU instead of the DSP offload
  path, so battery use during playback is probably somewhat higher.

### Try it on your own phone (userdebug build with `adb root`)

```bash
scripts/try-sw-eq.sh      # bind-mounts the modified config until the next reboot; nothing is written to a partition
adb reboot                # revert
```

Then force-close the player and start it again. Verified from a clean boot on the 5T.

Making it permanent on a userdebug build means `adb disable-verity` + remount of `/vendor` and
replacing `/vendor/etc/audio_effects.xml`; an OTA update will overwrite it. That is not scripted here.

## What this is *not*

This is not the bug in [`../15.1-device-profile-bug/`](../15.1-device-profile-bug/). I looked for it on
22.2 (instrumented AudioFX: 362 checks across a speaker↔headset change, **0 mismatches**) and did not find it.

## Environment

- OnePlus 5T, `lineage-22.2-20261110-nightly-dumpling` (Android 15, `userdebug`), vendor blobs from OxygenOS 10
- Device tree: `LineageOS/android_device_oneplus_msm8998-common` (`audio/audio_effects.xml`, `vendor.prop`:
  `vendor.audio.offload.track.enable=true`, `audio.offload.min.duration.secs=30`)
- Offload effect library built from `hardware/qcom` msm8998 audio `post_proc/` (`equalizer.c`, `effect_api.c`)
- Players: Twelve (stock), Musicolet; wired headphones
