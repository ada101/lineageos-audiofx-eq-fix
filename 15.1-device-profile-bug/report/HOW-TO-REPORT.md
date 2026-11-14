# How (and whether) to report this to LineageOS

## The honest situation

- **LineageOS 15.1 has been end-of-life for years**, and your build is an *unofficial* GSI, not an
  official LineageOS build for this phone.
- LineageOS's [bug-report guide](https://wiki.lineageos.org/how-to/bugreport/) treats reports about
  unofficial builds (and builds not from the official download portal) as out of scope; an issue
  filed against 15.1 on GitLab will most likely be closed on those grounds, even though it's real.
  (I couldn't open the wiki page directly while writing this, so check its current wording.)
- **But the bug is in code that still exists upstream.** The faulty line is unchanged on
  `lineage-24.0` (the newest AudioFX branch when I checked). That makes it worth reporting as a
  *code defect*, not as "15.1 is broken".

## My recommendation (in order of effectiveness)

### 1. Send the patch to Gerrit (best)

LineageOS accepts code changes only through Gerrit (`review.lineageos.org`). A one-line fix with a
clear explanation is easy to review, and it sidesteps the "unsupported version" problem.

Official guides: [Submitting patches](https://wiki.lineageos.org/how-to/submitting-patches/),
[Using Gerrit](https://wiki.lineageos.org/how-to/using-gerrit/),
[Contributing to apps](https://wiki.lineageos.org/how-to/contributing-apps).

Outline:

1. Create an account at <https://review.lineageos.org> and add an SSH public key.
2. Clone the AudioFX repo on the current default branch (check which; at time of writing the newest
   branches are `lineage-23.x` / `lineage-24.0`) and apply `patches/lineage-24.0-SessionManager.patch`.
3. Commit with the Change-Id hook installed (Gerrit's setup page gives the `curl` command), message e.g.:

   ```
   AudioFX: read prefs for the SessionManager's current device

   updateBackendLocked() read the saved settings via
   DevicePreferenceManager.getCurrentDevicePrefs(), which tracks the current
   output device separately from SessionManager and the UI. On devices that
   expose more than one output (e.g. speaker + wired headset) these can
   disagree, so the service applies a stale/default profile and the
   equalizer stops following the UI (no effect on new sessions, effect
   lost after any slider change).

   Use the profile for SessionManager's own device instead.
   ```

4. Push for review: `git push ssh://<user>@review.lineageos.org:29418/LineageOS/android_packages_apps_AudioFX HEAD:refs/for/<branch>`
   (or `repo upload .` if you work inside a full source tree).
5. Be ready to be asked for a test on a current build, or to be told the right fix is different
   (e.g. unify the device state). Reply on the change.

**Be upfront in the review** that you reproduced it only on 15.1 and the fix is verified there;
the report text in `lineageos-report.md` already says so.

### 2. File a GitLab issue (lower odds, still useful)

Tracker: <https://gitlab.com/LineageOS/issues/android>. Use their template (reports that don't follow
it are closed automatically). Use `report/lineageos-report.md` as the body; it frames this as a
code defect with a proposed patch. Expect it may be closed as unsupported; if so, link the Gerrit
change in the closed issue so people hitting the same symptom can find the fix.

### 3. Get a second data point (strongest evidence)

If you or someone you know has a **currently supported** device that shows the same
"no effect until I open AudioFX / breaks after moving a slider" pattern, run the check in
`docs/REPRODUCE.md` (compare which `shared_prefs/*.xml` file changes when you move a slider with what
the service applies) on that device. A reproduction on an official current build is what turns
this from "old unofficial build" into a bug the maintainers can't dismiss.

### 4. Publish the repo

Link your GitHub repo from the Gerrit change / issue so others on EOL versions (the people who
actually need it) can apply the module.

## What not to do

- Don't write "+1" or "affects me too" on existing issues (their guide asks people not to).
- Don't claim it's reproduced on current versions; say it's by code inspection.
- Don't attach private data (device serial, account info) from logs.
