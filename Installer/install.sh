#!/bin/zsh
# Interactive clean install. Requires no Xcode, Homebrew, or preinstalled Python.
set -euo pipefail
RB_ROOT="${0:A:h:h}"
source "$RB_ROOT/Installer/common.sh"
[[ "$EUID" != 0 ]] || rb_fail 'Run Install.command as your normal logged-in user, not with sudo.'
[[ "$(uname -s)" == Darwin ]] || rb_fail 'RemoteBuddy requires macOS.'
rb_os="$(sw_vers -productVersion)"
[[ "${rb_os%%.*}" -ge 13 ]] || rb_fail 'RemoteBuddy requires macOS 13 or later; PacketLogger may require a newer version.'
rb_app="$RB_ROOT/RemoteBuddy.app"
[[ -d "$rb_app" ]] || rb_app="$RB_ROOT/dist/RemoteBuddy.app"
[[ -d "$rb_app" ]] || rb_fail 'Application missing. Use the release archive, or run Scripts/build-app.sh.'
/usr/bin/codesign --verify --deep --strict "$rb_app"
if [[ ! -f "$RB_ROOT/Dependencies/BlackHole2ch-0.7.1.pkg" ]]; then
  print '从官方网站下载 BlackHole 2ch / Downloading BlackHole 2ch from its official website…'
  /bin/zsh "$RB_ROOT/Scripts/fetch-dependencies.sh"
fi
rb_verify_dependencies
rb_tool="${1:-}"
rb_address="${2:-}"
rb_attribute="${3:-0x46}"
if [[ -z "$rb_tool" && -d "$RB_ROOT/PrivateDependencies/PacketLogger.app" ]]; then
  rb_tool="$RB_ROOT/PrivateDependencies/PacketLogger.app"
  print '使用自用包中的原版 PacketLogger / Using the original PacketLogger from this personal package.'
fi
if [[ -z "$rb_tool" ]]; then
  print '从 Apple Developer 下载 Additional Tools for Xcode，找到 PacketLogger.app。'
  print 'Download Additional Tools for Xcode from Apple Developer and locate PacketLogger.app:'
  print 'https://developer.apple.com/download/all/?q=Additional%20Tools'
  read -r 'rb_tool?PacketLogger.app 完整路径 / full path (without quotes): '
fi
rb_verify_apple_tool "$rb_tool"
rb_tool_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$rb_tool/Contents/Info.plist")"
autoload -Uz is-at-least
is-at-least "$rb_tool_min" "$rb_os" || rb_fail "This PacketLogger version requires macOS $rb_tool_min or later."
/usr/bin/lipo "$rb_tool/Contents/Resources/packetlogger" -verify_arch "$(uname -m)"
if [[ -z "$rb_address" ]]; then
  print '请先在 macOS 蓝牙设置中配对遥控器。系统信息 → 蓝牙中可查看设备地址。'
  print 'Pair the remote in Bluetooth settings. Find its address in System Information → Bluetooth.'
  read -r 'rb_address?遥控器蓝牙地址 / remote Bluetooth address (AA:BB:CC:DD:EE:FF): '
fi
[[ "$rb_address" =~ '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$' ]] || rb_fail 'Invalid Bluetooth address.'
[[ "$rb_attribute" =~ '^(0x[0-9a-fA-F]{1,4}|[0-9]{1,5})$' ]] || rb_fail 'Invalid ATT report handle.'
rb_user="$(id -un)"
print '即将安装 / Will install:'
print -r -- "  RemoteBuddy → $HOME/Applications (login startup)"
print '  BlackHole 2ch + Python 3.13 (install if missing/outdated)'
print '  Python 3.13 framework: root-owned, read-only to other users for the system helper'
print '  A system HCI helper restricted to your user and remote'
print -r -- "  Remote: $rb_address; ATT handle: $rb_attribute"
print '蓝牙兼容描述文件和蓝牙/辅助功能权限需要在系统设置中手动确认。'
print 'The Bluetooth profile and Bluetooth/Accessibility permissions require confirmation in System Settings.'
read -r 'rb_answer?继续安装？/ Continue? [y/N] '
[[ "$rb_answer" == [yY] ]] || exit 0
rb_stage="$(mktemp -d /private/tmp/remotebuddy-install.XXXXXX)"
# Stage outside Documents so the privileged installer does not need access to personal folders.
for rb_dir in Installer Helpers Dependencies; do /usr/bin/ditto "$RB_ROOT/$rb_dir" "$rb_stage/$rb_dir"; done
/usr/bin/ditto "$rb_app" "$rb_stage/RemoteBuddy.app"
/usr/bin/ditto "$rb_tool" "$rb_stage/PacketLogger.app"
# Keep the stage on failure for diagnosis; remove after a successful install.
sudo /bin/zsh "$rb_stage/Installer/install-system.sh" "$rb_stage" "$rb_user" "$rb_address" "$rb_attribute"
/bin/zsh "$RB_ROOT/Installer/install-user.sh" "$rb_stage/RemoteBuddy.app" "$rb_stage/generated/agent.plist"
open "$RB_ROOT/Resources/RemoteBuddy-Bluetooth.mobileconfig"
print '在系统设置中安装 RemoteBuddy Bluetooth Compatibility，然后重启 Mac。'
print 'Install RemoteBuddy Bluetooth Compatibility in System Settings, then restart the Mac.'
print '允许 RemoteBuddy 使用蓝牙与辅助功能；在语音应用中选择 BlackHole 2ch 为麦克风。'
print 'Allow Bluetooth and Accessibility for RemoteBuddy; select BlackHole 2ch as your microphone in voice apps.'
sudo /bin/rm -rf "$rb_stage"
