#!/usr/bin/env bash
# Build the patched AudioFX Magisk module from the AudioFX.apk on a device.
#
#   scripts/build.sh                 # pulls /system/priv-app/AudioFX/AudioFX.apk over adb
#   scripts/build.sh path/to/AudioFX.apk
#
# Output: build/audiofx-prefs-fix.zip  (flash it in the Magisk app, then reboot)
#
# Requires: java, python3, curl, openssl, keytool, zip, unzip (and adb unless you pass an APK).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$HERE/build"
TOOLS="$BUILD/tools"
mkdir -p "$TOOLS" "$BUILD/in"

APKTOOL_URL="https://github.com/iBotPeaches/Apktool/releases/download/v2.9.3/apktool_2.9.3.jar"
APKTOOL_SHA256="7956eb04194300ce0d0a84ad18771eebc94b89fb8d1ddcce8ea4c056818646f4"
UAS_URL="https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar"
UAS_SHA256="e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835"
# Public AOSP platform key. The stock AudioFX in AOSP-signed builds (incl. LineageOS 15.1
# GSI-style builds) is signed with it; signing with the same key keeps its permissions.
KEY_BASE="https://android.googlesource.com/platform/build/+/refs/tags/android-8.1.0_r1/target/product/security"
PLATFORM_CERT_SHA256="C8:A2:E9:BC:CF:59:7C:2F:B6:DC:66:BE:E2:93:FC:13:F2:FC:47:EC:77:BC:6B:2B:0D:52:C1:1F:51:19:2A:B8"

fetch() { # url dest [sha256]
  [ -f "$2" ] || curl -fsSL -o "$2" "$1"
  if [ -n "${3:-}" ]; then
    echo "$3  $2" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $2" >&2; rm -f "$2"; exit 1; }
  fi
}

echo "[1/6] tools"
fetch "$APKTOOL_URL" "$TOOLS/apktool.jar" "$APKTOOL_SHA256"
fetch "$UAS_URL"     "$TOOLS/uas.jar"     "$UAS_SHA256"
for f in platform.pk8 platform.x509.pem; do
  [ -f "$TOOLS/$f" ] || curl -fsSL "$KEY_BASE/$f?format=TEXT" | base64 -d > "$TOOLS/$f"
done
got="$(openssl x509 -in "$TOOLS/platform.x509.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
[ "$got" = "$PLATFORM_CERT_SHA256" ] || { echo "unexpected platform cert: $got" >&2; exit 1; }
if [ ! -f "$TOOLS/platform.jks" ]; then
  openssl pkcs8 -inform DER -nocrypt -in "$TOOLS/platform.pk8" -out "$TOOLS/platform.key.pem"
  openssl pkcs12 -export -inkey "$TOOLS/platform.key.pem" -in "$TOOLS/platform.x509.pem" \
    -out "$TOOLS/platform.p12" -passout pass:android -name p
  keytool -importkeystore -srckeystore "$TOOLS/platform.p12" -srcstoretype PKCS12 -srcstorepass android \
    -destkeystore "$TOOLS/platform.jks" -deststorepass android -destkeypass android -alias p >/dev/null 2>&1
fi

echo "[2/6] input APK"
if [ "${1:-}" ]; then cp "$1" "$BUILD/in/AudioFX.apk"
else adb pull /system/priv-app/AudioFX/AudioFX.apk "$BUILD/in/AudioFX.apk" >/dev/null; fi
cert="$(unzip -p "$BUILD/in/AudioFX.apk" 'META-INF/*.RSA' | openssl pkcs7 -inform DER -print_certs \
        | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)"
if [ "$cert" != "$PLATFORM_CERT_SHA256" ]; then
  echo "This AudioFX.apk is not signed with the AOSP platform key ($cert)." >&2
  echo "Re-signing it with another key may change its permissions. Aborting." >&2
  exit 1
fi

echo "[3/6] decompile"
rm -rf "$BUILD/src"
java -jar "$TOOLS/apktool.jar" d -f "$BUILD/in/AudioFX.apk" -o "$BUILD/src" >/dev/null

echo "[4/6] patch SessionManager.updateBackendLocked"
python3 "$HERE/scripts/patch_smali.py" "$BUILD/src/smali/org/lineageos/audiofx/service/SessionManager.smali"

echo "[5/6] rebuild + sign"
java -jar "$TOOLS/apktool.jar" b "$BUILD/src" -o "$BUILD/unsigned.apk" >/dev/null
rm -rf "$BUILD/signed"
java -jar "$TOOLS/uas.jar" -a "$BUILD/unsigned.apk" --ks "$TOOLS/platform.jks" --ksAlias p \
  --ksPass android --ksKeyPass android -o "$BUILD/signed" --allowResign >/dev/null

echo "[6/6] package Magisk module"
MOD="$BUILD/module"
rm -rf "$MOD"; mkdir -p "$MOD/system/priv-app/AudioFX"
cp "$HERE/module/module.prop" "$MOD/module.prop"
cp "$BUILD/signed/unsigned-aligned-signed.apk" "$MOD/system/priv-app/AudioFX/AudioFX.apk"
rm -f "$BUILD/audiofx-prefs-fix.zip"
(cd "$MOD" && zip -qr "$BUILD/audiofx-prefs-fix.zip" .)
echo "done: $BUILD/audiofx-prefs-fix.zip"
