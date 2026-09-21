#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h:h}"
cd "$RB_ROOT"
mkdir -p work/clang-cache work/swift-cache
export CLANG_MODULE_CACHE_PATH="$RB_ROOT/work/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$RB_ROOT/work/clang-cache"
if [[ "${1:-}" == --regenerate-icons ]]; then
  swift Scripts/build-icons.swift "$RB_ROOT"
  iconutil -c icns work/icon-build/AppIcon.iconset -o Resources/AppIcon.icns
fi
# A single release supports both Apple Silicon and Intel Macs.
flags=(-c release --arch arm64 --arch x86_64 --disable-sandbox --cache-path "$RB_ROOT/work/swift-cache")
swift build "${flags[@]}"
bin_dir="$(swift build "${flags[@]}" --show-bin-path)"
app="$RB_ROOT/dist/RemoteBuddy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/RemoteBuddy" "$app/Contents/MacOS/RemoteBuddy"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/StatusBarTemplate*.png "$app/Contents/Resources/"
for language in en zh-Hans; do
  mkdir -p "$app/Contents/Resources/$language.lproj"
  cp Resources/$language.lproj/*.strings "$app/Contents/Resources/$language.lproj/"
done
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  # Use Apple's default certificate-bound requirement for public Developer ID builds.
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
  codesign --force --sign - --requirements '=designated => identifier "local.codex.RemoteMic"' "$app"
fi
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/RemoteBuddy" -verify_arch arm64 x86_64
print -r -- "Built $app"
