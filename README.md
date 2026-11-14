# LineageOS AudioFX: investigations and fixes

Notes, evidence and fixes for AudioFX (the LineageOS system equalizer) not working properly.
There are **two separate problems** here; they have different causes and different audiences.

| | [`15.1-device-profile-bug/`](15.1-device-profile-bug/) | [`22.2-offload-eq/`](22.2-offload-eq/) |
|--|--|--|
| Where seen | Huawei Y6 2018 (ATU-L22), LineageOS 15.1 Treble GSI (unofficial) | OnePlus 5T (dumpling), official LineageOS 22.2 nightly (2026-11-10) |
| Symptom | EQ not applied after boot, works after opening AudioFX, **stops after any slider move** | With the stock player (Twelve) the **EQ is silent** (bass/virtualizer/reverb weak but audible); other players may not attach at all |
| Cause | AudioFX service reads settings from a different device profile than the UI writes | Offloaded (compressed) playback: the effect chain attaches but the offload (DSP) EQ has no audible effect. Players that don't announce their session (e.g. Musicolet) need a setting |
| Status | **Fixed** (patch + Magisk module, verified on the device) | **Workaround verified** (software-only EQ in `audio_effects.xml`); why the offload EQ is silent is still unknown |
| Present upstream? | Yes: same code in `lineage-24.0` (by inspection; not reproduced on 22.2) | Reproduced on a current official build |

Start with the folder that matches your situation. Both folders are self-contained.

## License

AudioFX is Apache-2.0 (LineageOS / CyanogenMod Project); everything here is under the same license
(see [`LICENSE`](LICENSE)).
