#!/bin/bash
# idb's companion loads SimulatorKit from <Xcode>/Contents/Developer/Library/PrivateFrameworks,
# where the release Xcode kept it; Xcode-beta ships it under Contents/SharedFrameworks, and the
# release Xcode left this machine on 5 Sep. This builds a SHADOW Xcode bundle of symlinks
# (build/Xcode-shadow.app, gitignored) whose Developer dir mirrors the selected Xcode's and adds
# the one link idb needs. Nothing inside the real Xcode bundle changes. Point idb at it with
#   export DEVELOPER_DIR="$(cd "$(dirname "$0")/../.." && pwd)/build/Xcode-shadow.app/Contents/Developer"
# (the perf scripts do this themselves through IDB_DEVELOPER_DIR); xcrun keeps xcode-select's Xcode.
set -eu
IOS="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${1:-$(xcode-select -p)}"; SRC="$(cd "$SRC/../.." && pwd)"   # …/Xcode-beta.app
APP="$IOS/build/Xcode-shadow.app"; DEV="$APP/Contents/Developer"
shopt -s nullglob
rm -rf "$APP"; mkdir -p "$DEV/Library/PrivateFrameworks"
for e in "$SRC"/Contents/*; do n=$(basename "$e"); [ "$n" = Developer ] || ln -s "$e" "$APP/Contents/$n"; done
for e in "$SRC"/Contents/Developer/*; do n=$(basename "$e"); [ "$n" = Library ] || ln -s "$e" "$DEV/$n"; done
for e in "$SRC"/Contents/Developer/Library/*; do n=$(basename "$e"); [ "$n" = PrivateFrameworks ] || ln -s "$e" "$DEV/Library/$n"; done
for e in "$SRC"/Contents/Developer/Library/PrivateFrameworks/*; do ln -s "$e" "$DEV/Library/PrivateFrameworks/$(basename "$e")"; done
[ -e "$DEV/Library/PrivateFrameworks/SimulatorKit.framework" ] || ln -s "$SRC/Contents/SharedFrameworks/SimulatorKit.framework" "$DEV/Library/PrivateFrameworks/SimulatorKit.framework"
echo "$DEV"
