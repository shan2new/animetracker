#!/bin/bash
# Build the production-pointed Debug app for the QA sim and install it. Usage: build.sh <tag> [Release]
set -u
TAG="$1"; CONFIG="${2:-Debug}"
IOS="$(cd "$(dirname "$0")/../.." && pwd)"
P="${PERF_DIR:-$IOS/build/perf}"; mkdir -p "$P"
U="${PERF_UDID:-C2AED006-C1A7-49DF-B7B4-764B35373C11}"
cd "$IOS"
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# "Release" keeps the probe through -D PERFPROBE (inherited, so the packages keep their own flags).
# "opt" is the measurement build that matters: the Debug configuration (DEBUG launch arguments,
# the probe) compiled at -O whole-module, i.e. release-speed code with the debug conveniences.
EXTRA=()
if [ "$CONFIG" = "Release" ]; then EXTRA=('OTHER_SWIFT_FLAGS=$(inherited) -D PERFPROBE'); fi
if [ "$CONFIG" = "opt" ]; then CONFIG=Debug; EXTRA=("SWIFT_OPTIMIZATION_LEVEL=-O" "SWIFT_COMPILATION_MODE=wholemodule" "GCC_OPTIMIZATION_LEVEL=s"); fi
xcodebuild -project AniTrack.xcodeproj -scheme AniTrack -configuration "$CONFIG" \
  -destination "platform=iOS Simulator,id=$U" -derivedDataPath build/DerivedData \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  "API_BASE_URL=https://anime.cognipin.com" \
  "CLERK_PUBLISHABLE_KEY=pk_test_bGVnaWJsZS1nb2JibGVyLTU3LmNsZXJrLmFjY291bnRzLmRldiQ" \
  build > "$P/build-$TAG.log" 2>&1
rc=$?
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$P/build-$TAG.log" | grep -v "^warning" | tail -8
if [ $rc -ne 0 ]; then echo "xcodebuild exit $rc"; exit $rc; fi
xcrun simctl install $U "build/DerivedData/Build/Products/$CONFIG-iphonesimulator/AniTrack.app" && echo "installed $TAG ($CONFIG)"
