# dumpling: AudioFX equalizer has no effect on offloaded playback (Twelve); fix: software-only EQ in audio_effects.xml

**Device:** OnePlus 5T (dumpling)  **Build:** official `lineage-22.2-20261110-nightly-dumpling-signed`

## Summary

With the stock music player (Twelve), AudioFX's **equalizer has no audible effect**. Bass boost, virtualizer
and reverb change the sound (weakly), but moving the EQ sliders or choosing EQ presets does nothing.
The problem is specific to **compressed offload** playback: disabling offload, or making the EQ a
software-only effect, restores a fully working EQ.

## Steps to reproduce

1. Play an MP3 longer than 30 s in Twelve (it uses the offload output).
2. Open AudioFX, switch it on, set an exaggerated EQ (one band +15 dB, the others -15 dB).
3. Listen: no EQ effect. Toggle bass boost/virtualizer: audible.

## What I found

`dumpsys media.audio_flinger` for the playing session:

```
Output thread ... name AudioOut_6D, type 4 (OFFLOAD)
  5 effects for session 121          (Equalizer ACTIVE, Dynamic Bass Boost ACTIVE, ...)
  Equalizer flags: 00400048 (... offloadable)
```

The effect chain is healthy and AudioFX gets no errors, but the offload (`libqcompostprocbundle`) equalizer
has no audible effect.

A/B on the same device, same player:

| Setup | Output thread | EQ audible |
|-------|---------------|-----------|
| stock | OFFLOAD | no |
| `audio.offload.disable=true` + `vendor.audio.offload.track.enable=false` + audioserver/audio HAL restarted | MIXER | yes |
| stock, EQ changed to a software-only effect in `audio_effects.xml` | MIXER | yes |

With the EQ software-only (non-offloadable), audio policy keeps the track on the mixer output while the EQ is
enabled (`Equalizer flags: 00000048`, no "offloadable"), so offload comes back when AudioFX is switched off.

## Proposed change

`android_device_oneplus_msm8998-common`, `audio/audio_effects.xml`: replace the equalizer `effectProxy` with a plain
software effect (patch attached; `patch --dry-run` applies to `lineage-22.2`):

```diff
-        <effectProxy name="equalizer" library="proxy" uuid="c8e70ecd-48ca-456e-8a4f-0002a5d5c51b">
-            <libsw library="bundle" uuid="ce772f20-847d-11df-bb17-0002a5d5c51b"/>
-            <libhw library="offload_bundle" uuid="a0dac280-401c-11e3-9379-0002a5d5c51b"/>
-        </effectProxy>
+        <effect name="equalizer" library="bundle" uuid="ce772f20-847d-11df-bb17-0002a5d5c51b"/>
```

Trade-off: while AudioFX's EQ is on, playback is processed by the CPU rather than the DSP offload path
(more battery use during playback).

## What I ruled out

The offload EQ context's `device` stays 0 unless `EFFECT_CMD_SET_DEVICE` arrives, and AudioFlinger only sends it when
the descriptor has `EFFECT_FLAG_DEVICE_IND`, which the EQ lacks (bass boost and virtualizer have it; the proxy copies
the software effect's flags). I tested adding the flag (patched descriptor in both libraries; Android then reported
"device indication: requires updates" for the EQ): **no change**, so that is not the cause (or not the only one).

## Not established

*Why* the offload EQ is silent. Remaining ideas: no EQ module in this device's compress-offload DSP topology/ACDB, or the
parameters `eq_send_params()` (`post_proc/effect_api.c`) sends not matching what the DSP expects. I can test patches
or debug builds on the device (userdebug, `adb root` available).

## Related, not a LineageOS bug

AudioFX 22.2 only attaches when a player broadcasts `OPEN_AUDIO_EFFECT_CONTROL_SESSION`. Musicolet doesn't unless
set to "System Equalizer" (Settings → Audio → Equalizer). Twelve does.

## Environment

- LineageOS 22.2-20261110 nightly (official), `userdebug`, Android 15
- AudioFX 2.2.0; vendor blobs OxygenOS 10; Twelve (stock), Musicolet
- Full evidence, patch and scripts: https://github.com/ada101/lineageos-audiofx-eq-fix/tree/main/22.2-offload-eq
