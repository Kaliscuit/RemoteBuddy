#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h:h}"
cd "$RB_ROOT"
source Installer/common.sh
rb_variant=Public
rb_packetlogger=""
case "${1:-}" in
  --personal-complete)
    [[ $# == 2 ]] || rb_fail 'Usage: Scripts/package-release.sh --personal-complete /path/to/PacketLogger.app'
    rb_variant=Personal-Complete
    rb_packetlogger="${2:A}"
    rb_verify_apple_tool "$rb_packetlogger"
    ;;
  --local-offline)
    [[ $# == 1 ]] || rb_fail 'Usage: Scripts/package-release.sh --local-offline'
    rb_variant=Local-Offline
    ;;
  '') [[ $# == 0 ]] || rb_fail 'Unexpected argument.' ;;
  *) rb_fail 'Usage: Scripts/package-release.sh [--local-offline | --personal-complete /path/to/PacketLogger.app]' ;;
esac
Scripts/audit-source.sh
rb_verify_dependencies
app="$RB_ROOT/dist/RemoteBuddy.app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/RemoteBuddy" -verify_arch arm64 x86_64
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
name="RemoteBuddy-$version-$rb_variant"
mkdir -p "$RB_ROOT/work"
stage="$(mktemp -d "$RB_ROOT/work/release.XXXXXX")"
trap '/bin/rm -rf "$stage"' EXIT
bundle="$stage/$name"
mkdir -p "$bundle/Resources" "$bundle/Dependencies" "$bundle/Scripts" "$bundle/Source"
/usr/bin/ditto "$app" "$bundle/RemoteBuddy.app"
for folder in Installer Helpers ThirdParty docs; do
  /usr/bin/rsync -a --exclude '__pycache__' --exclude '*.pyc' "$folder/" "$bundle/$folder/"
done
cp Install.command Check.command Uninstall.command README.md README.en.md LICENSE "$bundle/"
cp Resources/RemoteBuddy-Bluetooth.mobileconfig "$bundle/Resources/"
mkdir -p "$bundle/Resources/Artwork"
cp Resources/Artwork/AppIcon-source.png "$bundle/Resources/Artwork/"
cp Scripts/fetch-dependencies.sh "$bundle/Scripts/"
cp Dependencies/README*.md "$bundle/Dependencies/"
while IFS=$'\t' read -r filename checksum url; do
  [[ -z "$filename" || "$filename" == \#* ]] && continue
  if [[ "$filename" == BlackHole2ch-*.pkg && "$rb_variant" == Public ]]; then continue; fi
  cp "Dependencies/$filename" "$bundle/Dependencies/"
done < Installer/dependencies.tsv
# Explicit source allowlist: never recursively package the working directory.
for folder in Sources Tests Helpers Installer Scripts Resources ThirdParty docs .github; do
  /usr/bin/rsync -a --exclude '__pycache__' --exclude '*.pyc' "$folder/" "$bundle/Source/$folder/"
done
cp Package.swift README.md README.en.md LICENSE .gitignore "$bundle/Source/"
mkdir -p "$bundle/Source/Dependencies"
cp Dependencies/README*.md "$bundle/Source/Dependencies/"
cp ./*.command "$bundle/Source/"
if [[ "$rb_variant" != Public ]]; then
  print 'PRIVATE LOCAL SETUP ONLY — contains the official BlackHole installer. Do not upload this archive.' > "$bundle/LOCAL-USE-ONLY.txt"
fi
if [[ "$rb_variant" == Personal-Complete ]]; then
  mkdir -p "$bundle/PrivateDependencies"
  /usr/bin/ditto "$rb_packetlogger" "$bundle/PrivateDependencies/PacketLogger.app"
  rb_verify_apple_tool "$bundle/PrivateDependencies/PacketLogger.app"
  cat > "$bundle/LOCAL-USE-ONLY.txt" <<'NOTICE'
PERSONAL MIGRATION / DEVELOPMENT TESTING ONLY — NOT FOR PUBLIC DISTRIBUTION.
This archive includes your original, Apple-signed PacketLogger and the official
BlackHole installer. Keep it on your own authorized Macs. Do not upload it to
GitHub, Releases, websites or another distribution service.
PacketLogger retains Apple's license and copyright; it is not covered by RemoteBuddy's GPL.
Apple terms: https://www.apple.com/legal/sla/docs/xcode.pdf
Install.command automatically uses the bundled PacketLogger. You still need to
enter your remote's address and confirm the profile and permissions on the new Mac.

仅供本人设备迁移与开发测试，不用于公开分发。
包含原版 PacketLogger 和 BlackHole 安装器，请勿上传 GitHub 或分享为公共下载。
NOTICE
fi
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "$bundle" "$RB_ROOT/dist/$name.zip"
(cd dist && shasum -a 256 "$name.zip" > "$name.zip.sha256")
print -r -- "Created dist/$name.zip"
