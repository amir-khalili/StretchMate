#!/bin/bash
# Build StretchMate.app (release, universal arm64+x86_64), ad-hoc sign it.
#   ./make.sh            → build/StretchMate.app
#   ./make.sh install    → also copy to /Applications and launch
#   ARCHS=arm64 ./make.sh  → single-arch build
set -euo pipefail
cd "$(dirname "$0")"

APP="build/StretchMate.app"
ARCHS="${ARCHS:-arm64 x86_64}"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

bins=()
for arch in $ARCHS; do
  echo "==> swift build -c release --arch $arch"
  swift build -c release --arch "$arch"
  bins+=("$(swift build -c release --arch "$arch" --show-bin-path)/StretchMate")
done
lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/StretchMate"
strip -x "$APP/Contents/MacOS/StretchMate"

cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> icon"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
if swift Scripts/make-icon.swift build/icon-1024.png; then
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: icon generation failed; continuing without icon"
fi

echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP"
lipo -info "$APP/Contents/MacOS/StretchMate"

if [[ "${1:-}" == "install" ]]; then
  echo "==> installing to /Applications"
  pkill -x StretchMate 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/StretchMate.app
  ditto "$APP" /Applications/StretchMate.app
  open /Applications/StretchMate.app
  echo "Installed and launched /Applications/StretchMate.app"
fi
