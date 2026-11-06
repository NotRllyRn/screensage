#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
XCODEGEN=${XCODEGEN:-xcodegen}
"$XCODEGEN" generate
xcodebuild -project ScreenSage.xcodeproj -scheme ScreenSage -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build > build-device.log 2>&1
rm -rf build/package
rm -f build/ScreenSage-unsigned.ipa
mkdir -p build/package/Payload
cp -R build/device/Build/Products/Release-iphoneos/ScreenSage.app build/package/Payload/
# Remove local/debug symbol paths from the public unsigned binary.
xcrun strip -S -x build/package/Payload/ScreenSage.app/ScreenSage
(cd build/package && /usr/bin/zip -qry ../ScreenSage-unsigned.ipa Payload)
(cd build && shasum -a 256 ScreenSage-unsigned.ipa > SHA256SUMS)
