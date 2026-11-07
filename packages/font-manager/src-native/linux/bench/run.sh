#!/bin/bash
# Builds libfontmanager.so (release) and the C benchmark linked against it, then runs it.
# Usage: bench/run.sh [fixtures dir]
set -euo pipefail
cd "$(dirname "$0")/.."
FIXTURES="${1:-$PWD/../android/fontmanager/src/main/res/font}"
cargo build --release
cc -O2 -Wall -Wextra -std=c11 -D_DEFAULT_SOURCE -Iinclude bench/bench.c -Ltarget/release -lfontmanager \
    -Wl,-rpath,"$PWD/target/release" -lpthread -o target/release/fm-bench
target/release/fm-bench "$FIXTURES"
