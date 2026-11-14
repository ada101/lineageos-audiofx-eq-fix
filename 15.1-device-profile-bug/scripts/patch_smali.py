#!/usr/bin/env python3
"""Apply the AudioFX fix to the baksmali output of SessionManager.

Java equivalent (SessionManager.updateBackendLocked):

    -  final SharedPreferences prefs = mDevicePrefs.getCurrentDevicePrefs();
    +  final SharedPreferences prefs = mDevicePrefs.prefsFor(getCurrentDeviceIdentifier());

(The smali below calls Context.getSharedPreferences with the same device identifier, which is
what DevicePreferenceManager.prefsFor() does.)
"""
import sys

path = sys.argv[1]
s = open(path).read()

old = """    iget-object v8, p0, Lorg/lineageos/audiofx/service/SessionManager;->mDevicePrefs:Lorg/lineageos/audiofx/service/DevicePreferenceManager;

    invoke-virtual {v8}, Lorg/lineageos/audiofx/service/DevicePreferenceManager;->getCurrentDevicePrefs()Landroid/content/SharedPreferences;

    move-result-object v3
"""
new = """    iget-object v8, p0, Lorg/lineageos/audiofx/service/SessionManager;->mContext:Landroid/content/Context;

    invoke-virtual {p0}, Lorg/lineageos/audiofx/service/SessionManager;->getCurrentDeviceIdentifier()Ljava/lang/String;

    move-result-object v9

    const/4 v10, 0x0

    invoke-virtual {v8, v9, v10}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;

    move-result-object v3
"""

if new in s:
    sys.exit("patch_smali: this APK is already patched (is the Magisk module active? Disable it, "
             "or extract the stock AudioFX.apk from your ROM zip, and run again).")
if s.count(old) != 1:
    sys.exit("patch_smali: expected snippet not found exactly once; this AudioFX build differs "
             "from the one the patch was written for (lineage-15.1, versionCode 20200). "
             "See docs/REPRODUCE.md to port the change by hand.")
open(path, "w").write(s.replace(old, new))
print("patched", path)
