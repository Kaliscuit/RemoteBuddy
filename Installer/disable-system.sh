#!/bin/zsh
set -euo pipefail
[[ "$EUID" == 0 ]] || exit 1
label=local.codex.RemoteMic.hci
launchctl bootout "system/$label" 2>/dev/null || true
plist="/Library/LaunchDaemons/$label.plist"
if [[ -f "$plist" ]]; then mv "$plist" "$plist.disabled"; fi
if /usr/bin/profiles list -type configuration | /usr/bin/grep -Fq "$label"; then
  /usr/bin/profiles remove -identifier "$label"
fi
print 'Helper and RemoteBuddy profile disabled. Shared dependencies were preserved.'
