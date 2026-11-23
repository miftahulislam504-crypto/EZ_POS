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

# Receipt printers: Bluetooth (Android 12+ run-time permissions, older versions use the legacy ones) and USB host
python3 - <<'PY'
import os
manifest = 'android/app/src/main/AndroidManifest.xml'
if os.path.exists(manifest):
    s = open(manifest).read()
    if 'BLUETOOTH_CONNECT' not in s:
        add = ('    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>\n'
               '    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>\n'
               '    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>\n'
               '    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>\n'
               '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>\n'
               '    <uses-feature android:name="android.hardware.bluetooth" android:required="false"/>\n'
               '    <uses-feature android:name="android.hardware.usb.host" android:required="false"/>\n')
        s = s.replace('<application', add + '    <application', 1)
        open(manifest, 'w').write(s)
        print('Android manifest: Bluetooth and USB printer permissions added')

plist = 'ios/Runner/Info.plist'
if os.path.exists(plist):
    s = open(plist).read()
    if 'NSBluetoothAlwaysUsageDescription' not in s:
        add = ('\n\t<key>NSBluetoothAlwaysUsageDescription</key>\n\t<string>EZ POS connects to your Bluetooth receipt printer.</string>'
               '\n\t<key>NSBluetoothPeripheralUsageDescription</key>\n\t<string>EZ POS connects to your Bluetooth receipt printer.</string>')
        s = s.replace('<dict>', '<dict>' + add, 1)
        open(plist, 'w').write(s)
        print('iOS Info.plist: Bluetooth printer description added')
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
