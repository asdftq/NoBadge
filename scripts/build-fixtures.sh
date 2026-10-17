#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p Lab/Artifacts
swiftc -parse-as-library Lab/BadgeFixture.swift -o Lab/Artifacts/Fixture -framework Cocoa -framework UserNotifications
for suffix in a b; do
  dest="Lab/Artifacts/NoBadge Test ${suffix:u}.app"
  mkdir -p "$dest/Contents/MacOS" "$dest/Contents/Resources"
  cp Lab/Artifacts/Fixture "$dest/Contents/MacOS/Fixture"
  cp NoBadge/Resources/AppIcon.icns "$dest/Contents/Resources/Fixture.icns"
  /usr/bin/python3 - "$dest" "$suffix" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]);s=sys.argv[2]
d={'CFBundleIdentifier':f'com.asdftq.nobadge.fixture.{s}','CFBundleExecutable':'Fixture','CFBundleName':f'NoBadge Test {s.upper()}','CFBundleDisplayName':f'NoBadge Test {s.upper()}','CFBundlePackageType':'APPL','CFBundleVersion':'3','CFBundleShortVersionString':'1.2','CFBundleIconFile':'Fixture.icns','LSMinimumSystemVersion':'15.0','NSHighResolutionCapable':True}
(p/'Contents/Info.plist').write_bytes(plistlib.dumps(d))
PY
  codesign --force --sign 'Developer ID Application: Hwechul Cho (G83X74Z537)' --options runtime --timestamp "$dest"
done
