#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
python3 scripts/generate-project.py --source-build
xcodebuild -project NoBadge.xcodeproj -scheme NoBadge -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/SourceData \
  build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
  'OTHER_CODE_SIGN_FLAGS=--timestamp=none'
print '\nBuilt: build/SourceData/Build/Products/Release/NoBadge.app'
print 'Quit any running NoBadge copy before opening this build.'
