#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h:h}"
cd "$RB_ROOT"
mkdir -p work/clang-cache work/swift-cache
export CLANG_MODULE_CACHE_PATH="$RB_ROOT/work/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$RB_ROOT/work/clang-cache"
swift test --disable-sandbox --scratch-path work/test-build --cache-path "$RB_ROOT/work/swift-cache"
"${PYTHON_FOR_TESTS:-python3}" -m unittest discover -s Tests/Python -v
for script in Scripts/*.sh Installer/*.sh ./*.command; do zsh -n "$script"; done
