#!/usr/bin/env python3
"""Search's transitions: tap the field (focus, keyboard), cancel, tap again, type one letter,
cancel — filmed at 30 fps with the stall sampler on. Usage: focus_test.py <tag> [--args "..."]
Scores hitches and stalls per phase and lists each stall's frames."""
import os, sys, time, json, subprocess, signal, shutil, re, collections
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
OUT = f'{P}/focus-{tag}'; os.makedirs(OUT, exist_ok=True)
def sh(*a, **k): return subprocess.run(a, env=ENV_SIM if a and a[0] == 'xcrun' else ENV, capture_output=True, text=True, **k)
def now(): return int(time.time() * 1000)
perf_path = os.path.join(sh('xcrun', 'simctl', 'get_app_container', U, B, 'data').stdout.strip(), 'Documents', 'perf.jsonl')
if os.path.exists(perf_path): os.remove(perf_path)
sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(0.5)
sh('xcrun', 'simctl', 'launch', U, B, '-perfProbe', '1', '-openTab', 'discover', *extra); time.sleep(9)
mp4 = f'{OUT}/focus.mp4'
rec = subprocess.Popen(['xcrun', 'simctl', 'io', U, 'recordVideo', '--codec', 'h264', '--force', mp4], env=ENV_SIM, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.0)
phases = []
def phase(name, fn, settle):
    t = now(); fn(); time.sleep(settle); phases.append({'phase': name, 'start': t, 'end': now()}); print('  ', name, flush=True)
phase('focus-1', lambda: sh(IDB, 'ui', 'tap', '196', '137', '--udid', U), 2.5)
phase('cancel-1', lambda: sh(IDB, 'ui', 'tap', '372', '52', '--udid', U), 2.5)
phase('focus-2', lambda: sh(IDB, 'ui', 'tap', '196', '137', '--udid', U), 2.0)
phase('type-b', lambda: sh(IDB, 'ui', 'text', 'b', '--udid', U), 2.0)
phase('cancel-2', lambda: sh(IDB, 'ui', 'tap', '372', '52', '--udid', U), 2.5)
phase('focus-3', lambda: sh(IDB, 'ui', 'tap', '196', '137', '--udid', U), 2.0)
phase('cancel-3', lambda: sh(IDB, 'ui', 'tap', '372', '52', '--udid', U), 2.0)
rec.send_signal(signal.SIGINT); rec.wait(timeout=20)
sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(1)
shutil.copy(perf_path, f'{OUT}/perf.jsonl'); json.dump(phases, open(f'{OUT}/phases.json', 'w'))
ev = [json.loads(l) for l in open(f'{OUT}/perf.jsonl') if l.strip()]
def is_app(f): return f != '?' and not f.startswith('[')
names = sorted({f for e in ev if e['event'] == 'stall' for smp in e['samples'] for f in smp['frames'] if is_app(f)})
dem = {}
if names:
    r = subprocess.run(['xcrun', 'swift-demangle', '--compact'], input='\n'.join(names), capture_output=True, text=True,
                       env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer'))
    dem = dict(zip(names, r.stdout.splitlines()))
for ph in phases:
    a, b = ph['start'], ph['end']
    hs = [e for e in ev if e['event'] == 'hitch' and a <= e['t'] <= b]
    st = [e for e in ev if e['event'] == 'stall' and a <= e['t'] <= b + 200]
    print(f"{ph['phase']:<9} hitches {len(hs):2d} sum {sum(h['ms'] for h in hs):4d} worst {max([h['ms'] for h in hs], default=0):4d} | stalls {[s['ms'] for s in st]}")
    for s in st:
        if s['ms'] < 80: continue
        incl = collections.Counter()
        for smp in s['samples']:
            seen = set()
            for f in smp['frames']:
                if is_app(f) and 'main' not in f and f not in seen: seen.add(f); incl[f] += 1
        def short(f): return re.sub(r'\(.*?\)', '()', dem.get(f, f)).replace('AniTrack.', '')[:70]
        top = [short(f) + f" ({c})" for f, c in incl.most_common(5)]
        leaves = collections.Counter(smp['frames'][0][:40] for smp in s['samples']).most_common(3)
        print(f"    stall {s['ms']} ms: {leaves}")
        for t in top: print(f"        {t}")
