#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/build/酸奶悬浮宠物.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
MODULE_CACHE="$ROOT/build/module-cache"

# The app bundle is generated output. Recreate it on every build so deleted or
# renamed sprite frames cannot survive as stale resources in the next bundle.
if [[ -d "$APP" ]]; then
  /bin/rm -rf "$APP"
fi

mkdir -p \
  "$MACOS" \
  "$RESOURCES/Idle" \
  "$RESOURCES/IdleGrooming" \
  "$RESOURCES/IdleSleeping" \
  "$RESOURCES/IdleExhausted" \
  "$RESOURCES/ClickTail" \
  "$RESOURCES/ClickMeal" \
  "$RESOURCES/ClickTurn" \
  "$RESOURCES/Entering" \
  "$RESOURCES/DraggingRight" \
  "$RESOURCES/DraggingLeft" \
  "$RESOURCES/Working" \
  "$RESOURCES/WorkingPhone" \
  "$RESOURCES/WorkingCoke" \
  "$RESOURCES/WaitingForApproval" \
  "$MODULE_CACHE"

/usr/bin/swiftc \
  -parse-as-library \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$MODULE_CACHE" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  "$ROOT"/Sources/YunduoPet/*.swift \
  -o "$MACOS/YunduoPet"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$ROOT"/Sources/YunduoPet/Resources/Idle/*.png "$RESOURCES/Idle/"
cp "$ROOT"/Sources/YunduoPet/Resources/IdleGrooming/*.png "$RESOURCES/IdleGrooming/"
cp "$ROOT"/Sources/YunduoPet/Resources/IdleSleeping/*.png "$RESOURCES/IdleSleeping/"
cp "$ROOT"/Sources/YunduoPet/Resources/IdleExhausted/*.png "$RESOURCES/IdleExhausted/"
cp "$ROOT"/Sources/YunduoPet/Resources/ClickTail/*.png "$RESOURCES/ClickTail/"
cp "$ROOT"/Sources/YunduoPet/Resources/ClickMeal/*.png "$RESOURCES/ClickMeal/"
cp "$ROOT"/Sources/YunduoPet/Resources/ClickTurn/*.png "$RESOURCES/ClickTurn/"
cp "$ROOT"/Sources/YunduoPet/Resources/Entering/*.png "$RESOURCES/Entering/"
cp "$ROOT"/Sources/YunduoPet/Resources/DraggingRight/*.png "$RESOURCES/DraggingRight/"
cp "$ROOT"/Sources/YunduoPet/Resources/DraggingLeft/*.png "$RESOURCES/DraggingLeft/"
cp "$ROOT"/Sources/YunduoPet/Resources/Working/*.png "$RESOURCES/Working/"
cp "$ROOT"/Sources/YunduoPet/Resources/WorkingPhone/*.png "$RESOURCES/WorkingPhone/"
cp "$ROOT"/Sources/YunduoPet/Resources/WorkingCoke/*.png "$RESOURCES/WorkingCoke/"
cp "$ROOT"/Sources/YunduoPet/Resources/WaitingForApproval/*.png "$RESOURCES/WaitingForApproval/"

codesign --force --deep --sign - "$APP" >/dev/null
/usr/bin/touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1 || true
echo "$APP"
