#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h:h}"
source "$RB_ROOT/Installer/common.sh"
[[ "$EUID" != 0 ]] || rb_fail 'Run as the logged-in user, not root.'
rb_app="${1:?application path required}"
rb_dest="$HOME/Applications/RemoteBuddy.app"
rb_agent="$HOME/Library/LaunchAgents/$RB_LABEL.plist"
/usr/bin/codesign --verify --deep --strict "$rb_app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$rb_app/Contents/Info.plist")" == "$RB_LABEL" ]] || rb_fail 'Unexpected application bundle ID.'
for rb_previous in "$rb_dest" "$HOME/Applications/RemoteMic.app"; do
  if [[ -e "$rb_previous" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$rb_previous/Contents/Info.plist")" == "$RB_LABEL" ]] || rb_fail "Unrelated application at $rb_previous"
  fi
done
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rb_stage="$(mktemp -d "$HOME/Applications/.RemoteBuddy-install.XXXXXX")"
/usr/bin/ditto "$rb_app" "$rb_stage/RemoteBuddy.app"
# Use the exact plist generated and validated for the target account.
cp "${2:?generated user agent required}" "$rb_stage/agent.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$rb_stage/agent.plist")" == "$rb_dest/Contents/MacOS/RemoteBuddy" ]] || rb_fail 'User agent path does not match this account.'
launchctl bootout "gui/$UID/$RB_LABEL" 2>/dev/null || true
rb_backup="$HOME/Library/Application Support/RemoteMic/Backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$rb_backup"
if [[ -e "$rb_dest" ]]; then mv "$rb_dest" "$rb_backup/RemoteBuddy.app"; fi
if [[ -e "$HOME/Applications/RemoteMic.app" ]]; then mv "$HOME/Applications/RemoteMic.app" "$rb_backup/RemoteMic.app"; fi
if [[ -f "$rb_agent" ]]; then cp "$rb_agent" "$rb_backup/agent.plist"; fi
mv "$rb_stage/RemoteBuddy.app" "$rb_dest"
mv "$rb_stage/agent.plist" "$rb_agent"
rmdir "$rb_stage"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$rb_dest"
launchctl bootstrap "gui/$UID" "$rb_agent"
print -r -- "Installed: $rb_dest"
