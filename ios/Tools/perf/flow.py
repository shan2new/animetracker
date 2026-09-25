#!/usr/bin/env python3
"""Drive the app through one scripted flow on the QA sim and score its frame pacing.

Usage: flow.py <tag> [--no-stage] [--main-only] [--social] [--calibrate] [--profile] [--args "..."]
Writes perf/<tag>/{steps.jsonl, perf.jsonl, cpu.jsonl, summary.json} and prints the table.
The app must be built with the PerfProbe hooks and launched with -perfProbe 1 (done here).

Today is the feed (25 Sep): the flow scrolls the feed and swipes its stories tray, opens Profile
from the header's LEADING disc, and — in the anchored launches — lands on the Suggested module
(`-feedAnchor suggested`) and rests in the story viewer (`-feedStory first`, clock frozen).
`--social` adds a like tap on the first post and its undo (a real write, then its reversal, on
the account the sim is signed in as — off by default). `--calibrate` measures the feed's
positions through the accessibility tree once and saves them (see `fixed`).
"""
import os, json, subprocess, sys, threading, time, shutil, re

P = os.environ.get('PERF_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'build', 'perf'))
U = os.environ.get('PERF_UDID', 'C2AED006-C1A7-49DF-B7B4-764B35373C11')
B = 'com.anitrack.app'
IDB = os.environ.get('IDB', os.path.expanduser('~/Library/Python/3.9/bin/idb'))
GOT = 'c101456a-89e6-45e4-8842-4e4b07894b32'
IOS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# idb needs SimulatorKit at <Xcode>/Contents/Developer/Library/PrivateFrameworks — the shadow bundle
# `simkit_shadow.sh` builds (the release Xcode is gone; Xcode-beta keeps SimulatorKit elsewhere).
ENV = dict(os.environ, DEVELOPER_DIR=os.environ.get('IDB_DEVELOPER_DIR', os.path.join(IOS_DIR, 'build', 'Xcode-shadow.app', 'Contents', 'Developer')))
# xcrun keeps xcode-select's Xcode.
ENV_SIM = {k: v for k, v in os.environ.items() if k != 'DEVELOPER_DIR'}
# The app's bar (AppTabBar, 25 Sep): four equal slots, the 49-pt band centred at y 794 on a 393 × 852 phone.
TAB = {'today': (49, 794), 'schedule': (147, 794), 'library': (245, 794), 'discover': (344, 794)}

tag = sys.argv[1]
no_stage = '--no-stage' in sys.argv
profile = '--profile' in sys.argv
extra_args = sys.argv[sys.argv.index('--args') + 1].split() if '--args' in sys.argv else []
calibrate = '--calibrate' in sys.argv
social = '--social' in sys.argv          # the like tap: a real write (and its reversal) on the account
main_only = '--main-only' in sys.argv   # a Release build has no DEBUG launch arguments for the anchored sub-flows
CAL_PATH = f'{P}/calibration.json'
CAL = {} if calibrate else (json.load(open(CAL_PATH)) if os.path.exists(CAL_PATH) else {})

def pos(key, resolve):
    """A screen position. Calibrating: measured through the accessibility tree and saved.
    Measuring: read from the calibration — `describe-all` turns accessibility on in the app
    process, which loads the AX bundles and taxes every layout after; a measured run never asks."""
    if calibrate or key not in CAL:
        v = resolve(); CAL[key] = v
        json.dump(CAL, open(CAL_PATH, 'w'))
        return v
    return CAL[key]
def fixed(key, default, resolve):
    """A FIXED position for a measured run: the calibration file's value, else `default` (read off
    a QA 14 Pro screenshot). Only `--calibrate` asks the accessibility tree (`resolve`), on the
    screen that is up when this is called, and saves what it found — a measured run never asks."""
    if calibrate:
        try: v = resolve()
        except Exception as e: print(f'  calibrate {key}: {e!r}', flush=True); v = None
        if v:
            CAL[key] = list(v) if isinstance(v, (list, tuple)) else v
            json.dump(CAL, open(CAL_PATH, 'w'))
            print(f'  calibrated {key} = {v}', flush=True)
            return tuple(v) if isinstance(v, (list, tuple)) else v
    v = CAL.get(key, default)
    return tuple(v) if isinstance(v, list) else v
OUT = f'{P}/{tag}'
os.makedirs(OUT, exist_ok=True)
steps = []
cpu = []
stop_cpu = threading.Event()

def now(): return int(time.time() * 1000)
def sh(*a, **k): return subprocess.run(a, env=ENV_SIM if a and a[0] == 'xcrun' else ENV, capture_output=True, text=True, **k)
def simctl(*a): return sh('xcrun', 'simctl', *a)
def idb(*a): return sh(IDB, 'ui', *a, '--udid', U)
def tap(x, y): idb('tap', str(x), str(y)); 
def swipe(x1, y1, x2, y2, dur=0.25): idb('swipe', str(x1), str(y1), str(x2), str(y2), '--duration', str(dur))
def text(s): idb('text', s)

def app_pid():
    r = sh('pgrep', '-f', 'AniTrack.app/AniTrack')
    pids = [int(x) for x in r.stdout.split()]
    return pids[0] if pids else None

def bb_pid():
    r = sh('pgrep', '-f', 'iOS 27.0.simruntime/Contents/Resources/RuntimeRoot/usr/libexec/backboardd')
    pids = [int(x) for x in r.stdout.split()]
    return pids[0] if pids else None

def cpu_sampler():
    while not stop_cpu.is_set():
        a, b = app_pid(), bb_pid()
        pids = [p for p in (a, b) if p]
        if pids:
            r = sh('ps', '-o', 'pid=,pcpu=', '-p', ','.join(map(str, pids)))
            vals = {}
            for line in r.stdout.splitlines():
                parts = line.split()
                if len(parts) == 2: vals[int(parts[0])] = float(parts[1])
            cpu.append({'t': now(), 'app': vals.get(a), 'bb': vals.get(b)})
        time.sleep(0.3)

def launch(*args):
    simctl('terminate', U, B); time.sleep(0.6)
    r = simctl('launch', U, B, '-perfProbe', '1', *extra_args, *args)
    return r

def save_steps():
    json.dump(steps, open(f'{OUT}/steps.jsonl', 'w'))

def step(name, fn=None, settle=0.6):
    steps.append({'step': name, 'start': now()})
    if fn:
        try: fn()
        except Exception as e: print(f'  step {name} raised {e!r}', flush=True)
    time.sleep(settle)
    steps[-1]['end'] = now()
    save_steps()
    print(f'  step {name}', flush=True)

def scrolls(up=4, down=3, gap=0.55, x=196):
    def f():
        for _ in range(up): swipe(x, 720, x, 240, 0.22); time.sleep(gap)
        for _ in range(down): swipe(x, 260, x, 760, 0.22); time.sleep(gap)
    return f

def describe():
    r = idb('describe-all', '--json')
    try: d = json.loads(r.stdout)
    except Exception: return []
    out = []
    def walk(n):
        if isinstance(n, dict):
            f = n.get('frame'); lab = (n.get('AXLabel') or n.get('title') or '').replace('\xa0', ' ')
            if f: out.append((n.get('type'), lab, int(f['x']), int(f['y']), int(f['width']), int(f['height'])))
            for c in n.get('children', []) or []: walk(c)
        elif isinstance(n, list):
            for c in n: walk(c)
    walk(d); return out

def find(label_sub, types=None, below=None):
    for t, lab, x, y, w, h in describe():
        if types and t not in types: continue
        if below is not None and y < below: continue
        if label_sub.lower() in lab.lower() and 0 <= y < 852: return (x, y, w, h, lab)
    return None

def shelf_y(header):
    """Resolved BEFORE the timed step: `describe-all` walks the accessibility tree on the app's
    main thread and stalls it for hundreds of ms, which must not be scored as the shelf's."""
    h = find(header)
    y = (h[1] + h[3] + 120) if h else 560
    return min(max(y, 200), 760)

def shelf_swipes(y, n=2):
    # 0.35 s, not 0.22: a fast short swipe was read as a TAP on the card under the finger (perf1's
    # today-shelf stall was a show page being pushed), and the rest of the flow ran one level deep.
    def f():
        for _ in range(n): swipe(360, y, 40, y, 0.35); time.sleep(0.7)
        # From 80, not 40: a rightward swipe that starts near the leading edge is the interactive
        # pop, and it took the show page off the stack mid-step in perf1.
        swipe(80, y, 340, y, 0.35); time.sleep(0.7)
    return f

def container_perf_path():
    r = simctl('get_app_container', U, B, 'data')
    return os.path.join(r.stdout.strip(), 'Documents', 'perf.jsonl')

# ---------------------------------------------------------------- the flow
# Positions are FIXED (read off screenshots of the anchored states): a measured run never asks the
# accessibility tree, which would switch accessibility on in the process.
#   Today (the feed, 25 Sep): the header's account disc is the LEADING 44-pt target of its first
#     row (≈ 37,85 at 393 pt); the stories tray sits under the header's two rows (its top ≈ y 150,
#     the bubbles ≈ y 155-222, so the swipes run at ≈ 190). `--calibrate` measures both.
#   Library at rest: Returning shelf y 170-270, Watching shelf y 385-485 (first card at 103,435).
#   Detail `-detailAnchor trailers`: Cast row y 280-390, More like this y 480-640.
#   Search at rest: the field at (196,137); Cancel at (355,137) once focused.
perf_path = container_perf_path()
if os.path.exists(perf_path): os.remove(perf_path)
sampler = threading.Thread(target=cpu_sampler, daemon=True); sampler.start()

def to_top(n=3):
    for _ in range(n): swipe(196, 200, 196, 780, 0.2); time.sleep(0.45)

def centre(hit):
    return (hit[0] + hit[2] // 2, hit[1] + hit[3] // 2) if hit else None

def find_top(label_sub, max_y):
    """The first element whose label contains `label_sub` above `max_y` (the feed's header)."""
    for t, lab, x, y, w, h in describe():
        if label_sub.lower() in lab.lower() and 0 <= y < max_y: return (x, y, w, h, lab)
    return None

def find_any(subs, min_y=0):
    for t, lab, x, y, w, h in describe():
        if y >= min_y and any(s.lower() in lab.lower() for s in subs) and y < 852: return (x, y, w, h, lab)
    return None

print(f'[{tag}] launch', flush=True)
steps.append({'step': 'launch', 'start': now()}); launch(); time.sleep(11); steps[-1]['end'] = now(); save_steps()
# Resolved BEFORE the timed steps (only `--calibrate` asks the tree, and its numbers are not scored).
PROFILE_DISC = fixed('feed-profile-disc', (37, 85), lambda: centre(find_top('Profile', 140)))
TRAY_Y = fixed('feed-tray-y', 190, lambda: (centre(find_any([' new episode', ', watched'], 120)) or (0, None))[1])
LIKE = fixed('feed-first-like', None, lambda: centre(find_any(['Like'], 200))) if social else None
tp = None
if profile:
    pid = app_pid()
    tp = subprocess.Popen(['xcrun', 'xctrace', 'record', '--template', 'Time Profiler', '--device', U,
                           '--attach', str(pid), '--time-limit', '75s', '--output', f'{OUT}/tp.trace'],
                          env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
step('idle-feed', lambda: time.sleep(4), settle=0)
# The tray first, while the feed is at its top (the tray scrolls away with the posts).
step('feed-stories', shelf_swipes(TRAY_Y))
step('feed-scroll', scrolls(5, 3))
to_top(2)
if social:
    if LIKE:
        # Like, then unlike: the account ends where it started (the toggles are newest-word-wins).
        def like_twice():
            tap(*LIKE); time.sleep(1.2); tap(*LIKE)
        step('feed-like', like_twice, settle=1.2)
    else:
        print('  --social: no calibrated like position (run once with --calibrate --social)', flush=True)
step('tab-schedule', lambda: tap(*TAB['schedule']), settle=1.6)
step('schedule-scroll', scrolls(4, 3))
step('tab-library', lambda: tap(*TAB['library']), settle=1.6)
step('library-shelf', shelf_swipes(220))
step('library-scroll', scrolls(4, 4))
to_top()
step('push-detail', lambda: tap(103, 435), settle=2.6)
step('detail-scroll', scrolls(5, 2))
step('detail-pop', lambda: swipe(3, 420, 330, 420, 0.3), settle=1.8)
step('tab-search', lambda: tap(*TAB['discover']), settle=1.6)
step('search-scroll', scrolls(4, 2))
to_top(2)
def search_type():
    tap(196, 137); time.sleep(0.8); text('one piece'); time.sleep(3.2)
step('search-type', search_type, settle=0.4)
step('search-clear', lambda: tap(355, 137), settle=1.2)
step('tab-today', lambda: tap(*TAB['today']), settle=1.6)
to_top(2)
step('profile-open', lambda: tap(*PROFILE_DISC), settle=2.2)
step('profile-scroll', scrolls(3, 2))
step('profile-close', lambda: swipe(196, 140, 196, 760, 0.3), settle=1.8)

# The anchored launches (a fresh process each: the launch is scored too).
if main_only: no_stage = True
if not main_only:
    # The Suggested module (`-feedAnchor suggested`, 1.5 s after content): a vertical scroll
    # through it and the posts around it — the rows its Add controls live on.
    steps.append({'step': 'launch-suggested', 'start': now()}); launch('-feedAnchor', 'suggested'); time.sleep(12); steps[-1]['end'] = now(); save_steps()
    step('feed-suggested', scrolls(2, 2))
    # The story viewer at rest (§5.1's target: zero hitches), clock frozen by the capture flag,
    # then closed with the pull the viewer answers to.
    steps.append({'step': 'launch-story', 'start': now()}); launch('-feedStory', 'first'); time.sleep(12); steps[-1]['end'] = now(); save_steps()
    step('story-idle', lambda: time.sleep(5), settle=0)
    step('story-close', lambda: swipe(196, 300, 196, 780, 0.35), settle=1.8)
    steps.append({'step': 'launch-detail', 'start': now()}); launch('-openDetail', GOT, '-detailAnchor', 'trailers'); time.sleep(10); steps[-1]['end'] = now(); save_steps()
    step('detail-shelf', shelf_swipes(560))
    step('detail-cast', shelf_swipes(330))
if not no_stage:
    steps.append({'step': 'stage-launch', 'start': now()})
    launch('-openDetail', GOT, '-detailTrailer', '1'); time.sleep(9); steps[-1]['end'] = now(); save_steps()
    step('stage-idle', lambda: time.sleep(5), settle=0)
    step('stage-close', lambda: tap(36, 62), settle=2)
stop_cpu.set(); sampler.join(timeout=2)
if tp:
    try: tp.wait(timeout=60)
    except subprocess.TimeoutExpired:
        print('  profiler still running; terminating it', flush=True); tp.terminate()
        try: tp.wait(timeout=30)
        except subprocess.TimeoutExpired: tp.kill()
simctl('terminate', U, B)
time.sleep(1.5)
shutil.copy(perf_path, f'{OUT}/perf.jsonl')
save_steps()
json.dump(cpu, open(f'{OUT}/cpu.jsonl', 'w'))

# ---------------------------------------------------------------- the score
ev = [json.loads(l) for l in open(f'{OUT}/perf.jsonl') if l.strip()]
hitches = [e for e in ev if e['event'] == 'hitch']
frames = [e for e in ev if e['event'] == 'frames']
rows = []
for s in steps:
    a, b = s['start'], s['end']
    hs = [h for h in hitches if a <= h['t'] <= b]
    fr_before = [f for f in frames if f['t'] <= a]; fr_in = [f for f in frames if f['t'] <= b]
    n0 = fr_before[-1]['n'] if fr_before else 0; n1 = fr_in[-1]['n'] if fr_in else 0
    c = [x for x in cpu if a <= x['t'] <= b and x['app'] is not None]
    dropped = sum(max(0, h['ms'] / 16.7 - 1) for h in hs)
    rows.append({'step': s['step'], 'seconds': round((b - a) / 1000, 1), 'frames': n1 - n0, 'hitches': len(hs),
                 'dropped': round(dropped), 'worst_ms': max([h['ms'] for h in hs], default=0),
                 'over100': sum(1 for h in hs if h['ms'] >= 100),
                 'app_cpu': round(sum(x['app'] for x in c) / len(c), 1) if c else None,
                 'bb_cpu': round(sum((x['bb'] or 0) for x in c) / len(c), 1) if c else None})
tot = {'hitches': sum(r['hitches'] for r in rows), 'dropped': sum(r['dropped'] for r in rows),
       'worst_ms': max(r['worst_ms'] for r in rows), 'over100': sum(r['over100'] for r in rows)}
json.dump({'tag': tag, 'rows': rows, 'total': tot}, open(f'{OUT}/summary.json', 'w'), indent=1)
print(f"\n{'step':<16}{'s':>5}{'frames':>7}{'hitch':>6}{'drop':>5}{'worst':>6}{'>100':>5}{'app%':>7}{'bb%':>6}")
for r in rows:
    print(f"{r['step']:<16}{r['seconds']:>5}{r['frames']:>7}{r['hitches']:>6}{r['dropped']:>5}{r['worst_ms']:>6}{r['over100']:>5}{str(r['app_cpu']):>7}{str(r['bb_cpu']):>6}")
print(f"TOTAL hitches={tot['hitches']} dropped={tot['dropped']} worst={tot['worst_ms']}ms over100={tot['over100']}")
