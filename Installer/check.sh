#!/bin/zsh
# Read-only; does not connect to the helper or capture Bluetooth traffic.
set -euo pipefail
RB_ROOT="${0:A:h:h}"
source "$RB_ROOT/Installer/common.sh"
print 'RemoteBuddy installation check / 安装检查'
rb_failed=0
if rb_verify_dependencies; then print 'OK: bundled dependencies'; else print 'MISSING: run Scripts/fetch-dependencies.sh'; rb_failed=1; fi
if [[ "${1:-}" == --bundle-only ]]; then exit "$rb_failed"; fi
if [[ -d /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver ]]; then print 'OK: BlackHole 2ch'; else print 'MISSING: BlackHole 2ch'; rb_failed=1; fi
if rb_python_ready; then print 'OK: independent Python runtime'; else print 'MISSING: Python 3.13.15+ runtime'; rb_failed=1; fi
if [[ -f "$RB_SERVICE/hci-config.json" ]]; then print 'OK: remote configuration'; else print 'MISSING: remote configuration'; rb_failed=1; fi
if launchctl print "gui/$UID/$RB_LABEL" >/dev/null 2>&1; then print 'OK: user launch job'; else print 'MISSING: user launch job'; rb_failed=1; fi
if [[ -S "/var/run/$RB_LABEL.hci.sock" ]]; then print 'OK: helper socket'; else print 'MISSING: helper socket'; rb_failed=1; fi
print 'Manually verify the compatibility profile, Bluetooth/Accessibility permissions and a real button press.'
print '请另行确认兼容描述文件、蓝牙/辅助功能权限，并实际测试按键与语音。'
exit "$rb_failed"
