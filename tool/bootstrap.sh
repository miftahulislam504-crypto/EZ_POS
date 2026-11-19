#!/usr/bin/env bash
# One-time setup: generates the Android/iOS/Web platform folders and adds the permissions EZ POS needs.
# Run from anywhere:  bash tool/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v flutter >/dev/null || { echo "Flutter is not installed or not on PATH."; exit 1; }

if [ ! -d android ] && [ ! -d ios ] && [ ! -d web ]; then
  flutter create --project-name ez_pos --org com.ezpos --platforms=android,ios,web .
fi

python3 - <<'PY'
import os, re

manifest = 'android/app/src/main/AndroidManifest.xml'
if os.path.exists(manifest):
    s = open(manifest).read()
    if 'android.permission.CAMERA' not in s:
        add = ('    <uses-permission android:name="android.permission.INTERNET"/>\n'
               '    <uses-permission android:name="android.permission.CAMERA"/>\n'
               '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
               '    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>\n')
        if 'android.permission.INTERNET' in s:
            add = add.replace('    <uses-permission android:name="android.permission.INTERNET"/>\n', '')
        s = s.replace('<application', add + '    <application', 1)
        open(manifest, 'w').write(s)
        print('Android manifest updated')

plist = 'ios/Runner/Info.plist'
if os.path.exists(plist):
    s = open(plist).read()
    if 'NSCameraUsageDescription' not in s:
        add = ('\n\t<key>NSCameraUsageDescription</key>\n\t<string>EZ POS uses the camera to scan product barcodes and take product photos.</string>'
               '\n\t<key>NSPhotoLibraryUsageDescription</key>\n\t<string>EZ POS lets you choose product photos and your shop logo.</string>')
        s = s.replace('<dict>', '<dict>' + add, 1)
        open(plist, 'w').write(s)
        print('iOS Info.plist updated')
PY

# mobile_scanner needs iOS 15.5 or newer
python3 - <<'PY'
import os, re
p = 'ios/Podfile'
if os.path.exists(p):
    s = open(p).read()
    if re.search(r"^\s*#?\s*platform :ios", s, re.M):
        s = re.sub(r"^\s*#?\s*platform :ios.*$", "platform :ios, '15.5'", s, count=1, flags=re.M)
        open(p, 'w').write(s)
        print('iOS deployment target set to 15.5')
PY

flutter pub get
echo
echo "Done. Next: copy dart_defines.example.json to dart_defines.json, fill it in, then run:"
echo "  flutter run --dart-define-from-file=dart_defines.json"
