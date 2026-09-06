#!/usr/bin/env python3
"""Type into Search at human speed and measure the field's latency and the main thread's stalls.
Usage: typing_test.py <tag> [--args "..."] [--query "one piece"] [--gap 0.16]
Films at 30 fps; per keystroke: when the field region changed (the letter appeared) relative to
the keystroke; plus every hitch/stall in the typing window with the app's frames."""
import os, sys, time, json, subprocess, signal, shutil
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
query = sys.argv[sys.argv.index('--query') + 1] if '--query' in sys.argv else 'one piece'
gap = float(sys.argv[sys.argv.index('--gap') + 1]) if '--gap' in sys.argv else 0.16
OUT = f'{P}/typing-{tag}'; os.makedirs(OUT, exist_ok=True)
def sh(*a, **k): return subprocess.run(a, env=ENV_SIM if a and a[0] == 'xcrun' else ENV, capture_output=True, text=True, **k)
def now(): return int(time.time() * 1000)
perf_path = os.path.join(sh('xcrun', 'simctl', 'get_app_container', U, B, 'data').stdout.strip(), 'Documents', 'perf.jsonl')
if os.path.exists(perf_path): os.remove(perf_path)
sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(0.5)
sh('xcrun', 'simctl', 'launch', U, B, '-perfProbe', '1', '-openTab', 'discover', *extra); time.sleep(9)
mp4 = f'{OUT}/typing.mp4'
rec = subprocess.Popen(['xcrun', 'simctl', 'io', U, 'recordVideo', '--codec', 'h264', '--force', mp4], env=ENV_SIM, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.0)
t_focus = now(); sh(IDB, 'ui', 'tap', '196', '137', '--udid', U); time.sleep(1.5)
keys = []
for ch in query:
    t = now(); sh(IDB, 'ui', 'text', ch, '--udid', U); keys.append({'ch': ch, 't': t})
    time.sleep(gap)
time.sleep(2.5)
t_end = now()
rec.send_signal(signal.SIGINT); rec.wait(timeout=20)
sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(1)
shutil.copy(perf_path, f'{OUT}/perf.jsonl')
json.dump({'focus': t_focus, 'keys': keys, 'end': t_end}, open(f'{OUT}/keys.json', 'w'))
# ---- the film: when did the field's text region change?
fd = f'{OUT}/frames'; os.makedirs(fd, exist_ok=True)
for f in os.listdir(fd): os.remove(f'{fd}/{f}')
sh('ffmpeg', '-loglevel', 'error', '-y', '-i', mp4, '-vf', 'fps=30,scale=393:-1', f'{fd}/%04d.png')
frames = sorted(os.listdir(fd))
# The recording began ~when `rec` started; frame 0 ≈ start + latency. Anchor on the FOCUS tap
# instead: the first frame where the field region changes after the keyboard appears is the
# focus; keystroke changes follow. We report changes relative to each other and to the tap.
field = (30, 36, 330, 68)   # the focused field row (y ≈ 52 pt)
prev = None; changes = []
for i, fn in enumerate(frames):
    im = Image.open(f'{fd}/{fn}').convert('L').crop(field)
    if prev is not None:
        d = ImageStat.Stat(ImageChops.difference(prev, im)).mean[0]
        if d > 1.5: changes.append((i, round(d, 1)))
    prev = im
print('field-region change frames (30 fps):', changes[:40])
# ---- the probe: hitches and stalls in the typing window
ev = [json.loads(l) for l in open(f'{OUT}/perf.jsonl') if l.strip()]
t0, t1 = keys[0]['t'] - 200, t_end
hs = [e for e in ev if e['event'] == 'hitch' and t0 <= e['t'] <= t1]
st = [e for e in ev if e['event'] == 'stall' and t0 <= e['t'] <= t1 + 300]
print(f"typing window {t1 - t0} ms: hitches {len(hs)} (worst {max([h['ms'] for h in hs], default=0)} ms, sum {sum(h['ms'] for h in hs)} ms); stalls {[s['ms'] for s in st]}")
import collections
def is_app(f): return f != '?' and not f.startswith('[')
incl = collections.Counter(); leaf = collections.Counter(); n = 0
for s in st:
    for smp in s['samples']:
        n += 1; seen = set()
        leaf[smp['frames'][0][:70]] += 1
        for f in smp['frames']:
            if is_app(f) and f not in seen: seen.add(f); incl[f] += 1
print('leaves:', leaf.most_common(6))
names = sorted(incl)
if names:
    r = subprocess.run(['xcrun', 'swift-demangle', '--compact'], input='\n'.join(names), capture_output=True, text=True,
                       env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer'))
    dem = dict(zip(names, r.stdout.splitlines()))
    import re
    print(f'app frames on the stack during typing stalls ({n} samples):')
    for f, c in incl.most_common(28):
        d = re.sub(r'\(.*?\)', '()', dem.get(f, f)); d = d.replace('AniTrack.', '')
        print(f'  {100 * c / n:5.1f}%  {d[:150]}')
