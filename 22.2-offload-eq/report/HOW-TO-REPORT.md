# Reporting the 22.2 / dumpling offload-EQ problem

Unlike the 15.1 bug, this one is reproduced on an **official build of a supported device**, so it fits the
LineageOS bug tracker's rules (their [bug-report guide](https://wiki.lineageos.org/how-to/bugreport/) covers official
builds; check its current wording before filing).

1. **Search first** at <https://gitlab.com/LineageOS/issues/android> for existing reports about AudioFX/equalizer on
   dumpling/cheeseburger (the 5T and 5 share `msm8998-common`). Don't post "+1" comments.
2. **File an issue** with their template, using `lineageos-report.md` as the body. Attach a bug report from the
   device if the template asks (`adb bugreport`) and review it for personal data first.
3. **Send the patch to Gerrit** (<https://review.lineageos.org>, repo `LineageOS/android_device_oneplus_msm8998-common`,
   branch `lineage-22.2` or the current one): `patches/dumpling-audio_effects-sw-equalizer.patch`. Guides:
   [Submitting patches](https://wiki.lineageos.org/how-to/submitting-patches/),
   [Using Gerrit](https://wiki.lineageos.org/how-to/using-gerrit/). Say plainly that it is a workaround (software EQ,
   CPU-decoded playback while AudioFX's EQ is on) and that the underlying reason for the silent offload EQ is unknown;
   maintainers may prefer a DSP/HAL-level fix or a different trade-off.
4. Mention that a **second device** (e.g. the OnePlus 5) would be useful confirmation, and offer to test patches.
