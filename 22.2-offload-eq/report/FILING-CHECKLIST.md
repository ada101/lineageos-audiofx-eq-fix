# Filing checklist for the 22.2 / dumpling report

Written against the rules on <https://wiki.lineageos.org/how-to/bugreport/> (re-read them before filing; they may change).

| Rule | Where we stand |
|------|----------------|
| Official build only | Yes: `lineage-22.2-20261110-nightly-dumpling-signed` from the official portal (`ro.lineage.releasetype=NIGHTLY`). **Do not report 15.1 / the Huawei GSI / the A70: all unofficial.** |
| No modified devices | **Not yet satisfied.** The 5T now has a changed `/vendor/etc/audio_effects.xml` and verity disabled. Before filing: undo it (restore the original file, or dirty-flash the latest official nightly) and reproduce on the untouched build. No Magisk/gapps is installed (good). `adb root` debugging is an official developer option. |
| Search first; no "+1" | Search GitLab for existing AudioFX/equalizer/offload reports on dumpling/cheeseburger before filing. |
| **No AI output** | **The text of the report must be yours, in your own words.** Everything in `lineageos-report.md` was drafted by Claude: use it as notes only, do not paste it. Leave out the DSP/ACDB guesses entirely. |
| One issue per report | Only the Twelve/offload EQ problem. Musicolet is a player setting, not a bug. |
| English only, template filled exactly | Read the template on the "New issue" page; codename is `dumpling`. |
| Logcat required, captured right after reproducing | See below. |

## Facts for the template (verified from the device)

- Codename: `dumpling` (OnePlus 5T)
- Version: `22.2-20261110-NIGHTLY-dumpling`, Android 15, security patch 2026-10-01, userdebug (official builds are)
- Kernel: `4.4.302-perf+`; baseband: `.c4.7-00070-8998_GEN_PACK-2.271073.1.277412.1`
- AudioFX 2.2.0; player: Twelve (stock)
- No Magisk, no GApps

## Reproduce on the clean build and capture the logs

1. Make the device stock again (see the "no modified devices" row).
2. `adb logcat -c`
3. Play an MP3 longer than 30 s in Twelve, open AudioFX, switch it on, set one band to +15 dB and the others to -15 dB. Listen: the EQ does nothing; toggling bass boost/virtualizer is audible.
4. Straight away: `adb logcat -d > logcat.txt` (see <https://wiki.lineageos.org/how-to/logcat/>)
5. Attach also `adb shell dumpsys media.audio_flinger > audio_flinger.txt` (taken while the song is playing).
   Check both files for anything personal (account names, Wi-Fi names, location) before uploading.

## What to write (in your own words, plain English)

Short and factual, e.g.: what you did, what you heard, and the one A/B you could do with `adb root` (disabling
offload makes the EQ work). Say that a software-only EQ in `audio_effects.xml` also made it work, and attach the
patch if you want. You don't need to explain *why*.
