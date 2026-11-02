#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/module-cache"
/usr/bin/swiftc -parse-as-library \
  -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" -target arm64-apple-macosx14.0 \
  -module-cache-path "$ROOT/build/module-cache" \
  -framework AppKit -framework SwiftUI -framework Combine \
  "$ROOT/Sources/YunduoPet/PetModel.swift" \
  "$ROOT/Sources/YunduoPet/PetEconomy.swift" \
  "$ROOT/Sources/YunduoPet/CodexBridge.swift" \
  "$ROOT/Tests/EnergySkinTests.swift" -o "$ROOT/build/EnergySkinTests"
"$ROOT/build/EnergySkinTests"
