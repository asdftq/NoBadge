#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift test --package-path Packages/NoBadgeCore
if [[ -d NoBadge.xcodeproj ]]; then
  xcodebuild -project NoBadge.xcodeproj -scheme NoBadge -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO
fi
