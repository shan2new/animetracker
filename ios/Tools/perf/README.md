# Perf tooling — measuring smoothness on the QA simulator

Instruments cannot attach to the iOS 27 simulator (`xctrace` records an empty trace from either
Xcode, and the Animation Hitches template refuses simulators), so the app carries its own
instruments and this directory drives them. Everything writes under `ios/build/perf/` (or
`$PERF_DIR`); the sim is `$PERF_UDID` (default: the Previously QA 14 Pro), idb is `$IDB`.

## The instruments (in the app)

`Sources/App/PerfProbe.swift`, compiled in DEBUG (or with `-D PERFPROBE`), armed by the launch
argument `-perfProbe 1`:

- a `CADisplayLink` **hitch logger** — every gap between presented frames ≥ 34 ms is a line in
  `Documents/perf.jsonl`, stamped with the screen (`.perfScreen("…")` hooks in `RootView`);
- a **main-thread stall sampler** — a watchdog thread that, once the main thread has not
  heartbeat for 40 ms, suspends it, copies its frame-pointer chain into a preallocated buffer,
  resumes it, and only then symbolicates with `dladdr`; the stacks ride in the same log.

A/B switches (launch arguments, DEBUG): `-perfNoShelfMask 1`, `-perfNoMaterial 1`,
`-perfNoDrift 1`.

## The scripts

```bash
Tools/perf/build.sh <tag> [Debug|Release|opt]   # build + install; "opt" = Debug config at -O whole-module
Tools/perf/flow.py <tag> [--args "-perfNoX 1"] [--main-only] [--no-stage]   # the scripted flow, scored
Tools/perf/compare.py <tagA> <tagB> [...]       # side by side (hitches / dropped / worst ms / >100 ms; CPU)
Tools/perf/stalls.py <tag> --min 150 [--step tab-search]   # the sampled stacks per step, demangled
Tools/perf/tapvideo.py <tag> [--args "..."]     # films a tab tap: the frame the highlight moves vs the frame content lands
Tools/perf/hero_check.sh <dir>                  # photographs the billboards and films a Search query (12-fps contact sheet)
Tools/perf/typing_test.py <tag> [--gap 0.16]   # types into Search at human speed: per-key latency on film + the stalls' stacks
Tools/perf/typing_report.py <tag>              # scores a typing test: hitches against the keystrokes, each stall's frames
Tools/perf/focus_test.py <tag>                 # (older) Search's transitions with blind taps — superseded by focus_film.py
Tools/perf/focus_film.py <tag> --scenario cycles|warm|cold [--args "-perfNoWarm 1"]
                                                # Search's focus: every tap verified on screen, latencies from the app's marks
                                                # (touch-down → search-presented → keyboard-will-show → did-show), the film's
                                                # per-frame series + a sheet per phase; refuses to score without a keyboard
Tools/perf/film_events.py <film-dir>            # the transitions in any recorded film, found from the frames (runs + sheets)
Tools/perf/simkit_shadow.sh                     # (re)build build/Xcode-shadow.app so idb finds SimulatorKit under Xcode-beta
Tools/perf/warmup_check.py <tag> [--film]       # the keyboard warm-up must be UNSEEN: every frame of a launch scanned for a keyboard
Tools/perf/hero_pairs.py <before> <after> <png> # before/after sheet of the billboards
Tools/perf/sheet.py <capture-dir> [out.png]     # contact sheet of a capture set (the loop's capture_ios.sh names)
```

The flow: launch → idle → scroll Today → Schedule → Library (shelf, scroll, a push, the show
page, pop) → Search (scroll, type, clear) → Today → Profile (open, scroll, close); then anchored
launches for the shelves (`-todayAnchor upnext`, `-openDetail … -detailAnchor trailers`) and
the trailer stage. Positions are FIXED, read off screenshots of those states.

## Driving the simulator (6 Sep)

- **idb needs `build/Xcode-shadow.app`.** The release Xcode left this machine on 5 Sep; idb's
  companion loads SimulatorKit from `<Xcode>/Contents/Developer/Library/PrivateFrameworks`, and
  Xcode-beta keeps it under `Contents/SharedFrameworks`. `simkit_shadow.sh` builds a bundle of
  symlinks with the one extra link; the scripts point idb at it (`IDB_DEVELOPER_DIR` overrides)
  and leave `xcrun` on xcode-select's Xcode. After an Xcode update, rerun the script.
- **The simulator drops into a no-software-keyboard mode on its own.** `idb ui text` is a
  HARDWARE keyboard to it, and so is the Mac's keyboard while the Simulator window has focus:
  after either, a focused field shows a caret and no keyboard, across app relaunches, until
  `xcrun simctl shutdown` + `boot`. A run in that state measures nothing — `focus_film.py`
  checks for the keyboard on the first focus and exits 3 — and it is also what a person sees
  on the QA sim after typing into it from the Mac. Type by tapping keys, or reboot first.
- **Every tap is verified.** The dismiss control of the focused field sits at (355, 89) on this
  build, the avatar at the same x when the field is at rest: a blind "cancel" opened Profile.
  `focus_film.py` reads the field's state off a screenshot before and after each tap.
- **The recorder can wedge.** "Host recording is already in progress" from `simctl io
  recordVideo` after a recorder was killed: only a simulator reboot clears it.
- **A loaded host starves the sim's keyboard.** With the Android emulator up and a load average
  in the hundreds (6 Sep), launches took 26 s, taps landed seconds late and NO focus showed a
  keyboard even right after a reboot — the keyboard is composited outside the app on iOS 26+ and
  its process does not come up. Measure on a quiet machine or the numbers are the host's.
- Half-size frames (197 px) and deleted after analysis: a full-size 60-fps frame set is
  300 MB per film and the disk was down to nothing once.

## What the numbers are not

- **Never call `idb ui describe-all` in a measured run.** It switches accessibility on in the
  process (the AX bundles load, every layout is taxed) and it stays on until the simulator is
  shut down and booted again. `--calibrate` is the only mode that asks the tree.
- A fast short swipe (0.22 s) registers as a tap; a rightward swipe from x=40 is the interactive
  pop. The flow uses 0.35 s and starts at x=80.
- Run-to-run noise is large (±50 % on a step). Compare totals, repeat runs, read the stacks.
- `-O` changes the app's own code only; the first render of a root is mostly SwiftUI,
  AttributeGraph and Swift-runtime work under `$main`, so an optimised build on the simulator
  is not much faster than a Debug one there. A device is.
