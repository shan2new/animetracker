#!/usr/bin/env python3
"""Film a tab tap and measure, in frames, when the tab bar's highlight moves and when the content
changes. Usage: tapvideo.py <tag> [--args "-perfNoDefer 1"]
Taps Schedule, Library, Search in turn from a fresh launch (10 s settle); one video per tap."""
import os, subprocess, sys, time, signal, json
from PIL import Image, ImageChops, ImageStat

P = os.environ.get('PERF_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'build', 'perf'))
U = os.environ.get('PERF_UDID', 'C2AED006-C1A7-49DF-B7B4-764B35373C11'); B = 'com.anitrack.app'
IDB = os.environ.get('IDB', os.path.expanduser('~/Library/Python/3.9/bin/idb'))
IOS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# idb needs SimulatorKit at <Xcode>/Contents/Developer/Library/PrivateFrameworks — the shadow bundle
# `simkit_shadow.sh` builds (the release Xcode is gone; Xcode-beta keeps SimulatorKit elsewhere).
ENV = dict(os.environ, DEVELOPER_DIR=os.environ.get('IDB_DEVELOPER_DIR', os.path.join(IOS_DIR, 'build', 'Xcode-shadow.app', 'Contents', 'Developer')))
# xcrun keeps xcode-select's Xcode.
ENV_SIM = {k: v for k, v in os.environ.items() if k != 'DEVELOPER_DIR'}
tag = sys.argv[1]
extra = sys.argv[sys.argv.index('--args') + 1].split() if '--args' in sys.argv else []
OUT = f'{P}/tap-{tag}'; os.makedirs(OUT, exist_ok=True)
TAPS = [('schedule', 137, 812), ('library', 245, 812), ('search', 338, 812)]

def sh(*a, **k): return subprocess.run(a, env=ENV_SIM if a and a[0] == 'xcrun' else ENV, capture_output=True, text=True, **k)
sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(0.5)
sh('xcrun', 'simctl', 'launch', U, B, '-perfProbe', '1', *extra); time.sleep(10)
results = []
for name, x, y in TAPS:
    mp4 = f'{OUT}/{name}.mp4'
    if os.path.exists(mp4): os.remove(mp4)
    rec = subprocess.Popen(['xcrun', 'simctl', 'io', U, 'recordVideo', '--codec', 'h264', '--force', mp4], env=ENV_SIM,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2.0)
    sh(IDB, 'ui', 'tap', str(x), str(y), '--udid', U)
    time.sleep(2.5)
    rec.send_signal(signal.SIGINT); rec.wait(timeout=20)
    fd = f'{OUT}/{name}-frames'; os.makedirs(fd, exist_ok=True)
    for f in os.listdir(fd): os.remove(f'{fd}/{f}')
    sh('ffmpeg', '-loglevel', 'error', '-y', '-i', mp4, '-vf', 'fps=60,scale=393:-1', f'{fd}/%04d.png')
    frames = sorted(os.listdir(fd))
    if not frames: results.append({'tap': name, 'error': 'no frames'}); continue
    base = Image.open(f'{fd}/{frames[0]}').convert('L')
    W, H = base.size
    bar = (0, int(H * 0.905), W, int(H * 0.965))       # the tab pill
    body = (0, int(H * 0.14), W, int(H * 0.82))        # the content
    def diff(img, box):
        a = base.crop(box); b = img.crop(box)
        return ImageStat.Stat(ImageChops.difference(a, b)).mean[0]
    first_bar = first_body = None
    series = []
    for i, fn in enumerate(frames):
        img = Image.open(f'{fd}/{fn}').convert('L')
        db, dc = diff(img, bar), diff(img, body)
        series.append((i, round(db, 1), round(dc, 1)))
        if first_bar is None and db > 2.0: first_bar = i
        if first_body is None and dc > 4.0: first_body = i
    r = {'tap': name, 'frames': len(frames), 'bar_frame': first_bar, 'body_frame': first_body,
         'body_after_bar_ms': None if first_bar is None or first_body is None else round((first_body - first_bar) * 1000 / 60)}
    results.append(r); print(r, flush=True)
    json.dump(series, open(f'{OUT}/{name}-series.json', 'w'))
    time.sleep(1.5)
sh('xcrun', 'simctl', 'terminate', U, B)
json.dump(results, open(f'{OUT}/results.json', 'w'), indent=1)
