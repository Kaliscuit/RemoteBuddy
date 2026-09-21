#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h:h}"
source "$RB_ROOT/Installer/common.sh"
[[ "$EUID" != 0 ]] || rb_fail 'Run as your normal logged-in user.'
print 'This disables RemoteBuddy login startup, the system helper and its Bluetooth capture profile.'
print '这会停用 RemoteBuddy 自启、系统辅助服务及蓝牙兼容描述文件。'
print 'Your app, mappings, backups, BlackHole and Python are preserved.'
print '保留应用、映射、备份及可供其他软件使用的 BlackHole / Python。'
read -r 'rb_answer?继续？/ Continue? [y/N] '
[[ "$rb_answer" == [yY] ]] || exit 0
launchctl bootout "gui/$UID/$RB_LABEL" 2>/dev/null || true
rb_agent="$HOME/Library/LaunchAgents/$RB_LABEL.plist"
if [[ -f "$rb_agent" ]]; then mv "$rb_agent" "$rb_agent.disabled"; fi
rb_stage="$(mktemp -d /private/tmp/remotebuddy-uninstall.XXXXXX)"
cp "$RB_ROOT/Installer/disable-system.sh" "$rb_stage/disable-system.sh"
sudo /bin/zsh "$rb_stage/disable-system.sh"
rm "$rb_stage/disable-system.sh"
rmdir "$rb_stage"
print 'Disabled. You can now move ~/Applications/RemoteBuddy.app to Trash.'
