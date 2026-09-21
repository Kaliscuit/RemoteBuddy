#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h}"
exec /bin/zsh "$RB_ROOT/Installer/check.sh"
