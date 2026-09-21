#!/bin/zsh
# Privileged part only. Called after the visible install plan is confirmed.
set -euo pipefail
RB_ROOT="${1:?staged release required}"
source "$RB_ROOT/Installer/common.sh"
[[ "$EUID" == 0 ]] || rb_fail 'Administrator privileges required.'
rb_user="${2:?target user required}"
rb_address="${3:?remote address required}"
rb_attribute="${4:-0x46}"
[[ "$rb_user" =~ '^[a-zA-Z_][a-zA-Z0-9_.-]*$' ]] || rb_fail 'Invalid account name.'
[[ "$(id -u "$rb_user")" -ge 501 ]] || rb_fail 'Select a normal user account.'
rb_verify_dependencies
rb_verify_apple_tool "$RB_ROOT/PacketLogger.app"
/usr/sbin/pkgutil --check-signature "$RB_ROOT/Dependencies/BlackHole2ch-0.7.1.pkg"
/usr/sbin/pkgutil --check-signature "$RB_ROOT/Dependencies/python-3.13.15-macos11.pkg"
if ! rb_python_ready; then
  /usr/sbin/installer -pkg "$RB_ROOT/Dependencies/python-3.13.15-macos11.pkg" -target /
fi
# python.org defaults this framework to group-admin writable. A root service
# needs a read-only runtime. Limit the change to 3.13 and its parent directories;
# other installed Python versions are not traversed. Keep normal apps readable.
rb_framework=/Library/Frameworks/Python.framework
[[ ! -L "$rb_framework" && ! -L "$rb_framework/Versions" && ! -L "$rb_framework/Versions/3.13" ]] || rb_fail 'Unexpected symlink in the Python framework path.'
chown root:wheel "$rb_framework" "$rb_framework/Versions"
chmod go-w "$rb_framework" "$rb_framework/Versions"
chown -R root:wheel "$rb_framework/Versions/3.13"
chmod -R go-w "$rb_framework/Versions/3.13"
# Verify the root service will not execute a user-writable interpreter.
"$RB_PYTHON" -I -S -c '
import os, pathlib, stat, sys
p = pathlib.Path(sys.executable).resolve()
for item in [p, *p.parents]:
    s = item.stat()
    if s.st_uid != 0 or s.st_mode & 0o022:
        raise SystemExit("Python runtime path must be root-owned and not writable by other users: " + str(item))
'
"$RB_PYTHON" -I -S "$RB_ROOT/Installer/configure.py" --user "$rb_user" --address "$rb_address" \
  --attribute "$rb_attribute" --output "$RB_ROOT/generated"
if [[ ! -d /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver ]]; then
  /usr/sbin/installer -pkg "$RB_ROOT/Dependencies/BlackHole2ch-0.7.1.pkg" -target /
fi
# Do not overwrite Apple's protected application on upgrades.
if [[ -e "$RB_SERVICE/PacketLogger.app" ]]; then rb_verify_apple_tool "$RB_SERVICE/PacketLogger.app"; fi
launchctl bootout "system/$RB_LABEL.hci" 2>/dev/null || true
mkdir -p "$RB_SERVICE"
if [[ -f "$RB_SERVICE/hci-config.json" ]]; then
  rb_backup="$RB_SERVICE/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$rb_backup"
  cp "$RB_SERVICE/hci-config.json" "$rb_backup/"
  for rb_old in hci_helper.py hci-helper.py; do
    if [[ -f "$RB_SERVICE/$rb_old" ]]; then cp "$RB_SERVICE/$rb_old" "$rb_backup/"; fi
  done
fi
if [[ ! -d "$RB_SERVICE/PacketLogger.app" ]]; then
  /usr/bin/ditto "$RB_ROOT/PacketLogger.app" "$RB_SERVICE/PacketLogger.app"
  chown -R root:wheel "$RB_SERVICE/PacketLogger.app"
  chmod -R go-w "$RB_SERVICE/PacketLogger.app"
fi
cp "$RB_ROOT/Helpers/hci_helper.py" "$RB_SERVICE/hci_helper.py"
cp "$RB_ROOT/generated/hci-config.json" "$RB_SERVICE/hci-config.json"
cp "$RB_ROOT/generated/daemon.plist" "/Library/LaunchDaemons/$RB_LABEL.hci.plist"
chown root:wheel "$RB_SERVICE" "$RB_SERVICE/hci_helper.py" "$RB_SERVICE/hci-config.json" "/Library/LaunchDaemons/$RB_LABEL.hci.plist"
chmod 755 "$RB_SERVICE"
chmod 644 "$RB_SERVICE/hci_helper.py" "$RB_SERVICE/hci-config.json" "/Library/LaunchDaemons/$RB_LABEL.hci.plist"
launchctl bootstrap system "/Library/LaunchDaemons/$RB_LABEL.hci.plist"
print 'System components installed. Bluetooth capture starts only when the app connects.'
