#!/bin/zsh
# Shared by dependency fetching and the installer; no commands from manifest rows.
set -euo pipefail
RB_PYTHON=/Library/Frameworks/Python.framework/Versions/3.13/bin/python3
RB_LABEL=local.codex.RemoteMic
RB_SERVICE='/Library/Application Support/RemoteMic'
rb_fail() { print -u2 -r -- "$*"; return 1; }
rb_verify_file() {
  local filename="$1" expected="$2" actual
  [[ -f "$filename" && ! -L "$filename" ]] || { rb_fail "Missing regular file: $filename"; return 1; }
  actual="$(/usr/bin/shasum -a 256 "$filename")"
  [[ "${actual%% *}" == "$expected" ]] || rb_fail "SHA-256 mismatch: $filename"
}
rb_verify_dependencies() {
  local filename checksum url
  while IFS=$'\t' read -r filename checksum url; do
    [[ -z "$filename" || "$filename" == \#* ]] && continue
    rb_verify_file "$RB_ROOT/Dependencies/$filename" "$checksum" || return 1
  done < "$RB_ROOT/Installer/dependencies.tsv"
}
rb_verify_apple_tool() {
  local tool="$1"
  [[ -d "$tool" && -x "$tool/Contents/Resources/packetlogger" ]] || { rb_fail "Select Apple's original PacketLogger.app"; return 1; }
  /usr/bin/codesign --verify --deep --strict -R='anchor apple' "$tool"
}
rb_python_ready() {
  # Inspect metadata before executing an existing interpreter, especially as root.
  [[ -x "$RB_PYTHON" ]] || return 1
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Library/Frameworks/Python.framework/Versions/3.13/Resources/Info.plist 2>/dev/null)" || return 1
  autoload -Uz is-at-least
  is-at-least 3.13.15 "$version"
}
