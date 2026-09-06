#!/usr/bin/env python3
"""Film Search's focus transition and score it from the app's own clock.
Usage: focus_film.py <tag> --scenario cycles|warm|cold [--args "..."] [--keep-frames]
  cycles   launch on Search, three focus / cancel cycles (the steady state)
  warm     launch on Today, rest 4 s (the keyboard warm-up runs), Search tab, focus / cancel × 2
  cold     launch on Today with the warm-up OFF, Search tab at once, focus / cancel × 2

Every tap is VERIFIED against the screen (the field's position says whether it is focused; the
driver waits for the app before the first tap and never taps blind — an earlier version tapped a
Cancel position that had moved and opened the Profile sheet instead). Latencies come from the
probe's marks (`-perfProbe 1`): tap → `search-presented` (our binding flipped) → `keyboard-will-show`
(the system began the keyboard's animation) → `keyboard-did-show`, with the stalls and the
`search-body` re-runs in the window. The film (resampled at 60 fps, half size) gives the SHAPE:
the per-frame change of the bar band, the focused field row, the content and the keyboard band,
anchored on the first focus. Never uses `idb ui text`: to the simulator that is a hardware
keyboard, after which no focus shows the software keyboard until the simulator reboots."""
import os, sys, time, json, subprocess, signal, shutil, collections, re
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
scenario = sys.argv[sys.argv.index('--scenario') + 1] if '--scenario' in sys.argv else 'cycles'
extra = sys.argv[sys.argv.index('--args') + 1].split() if '--args' in sys.argv else []
OUT = f'{P}/film-{tag}-{scenario}'; os.makedirs(OUT, exist_ok=True)
def sh(*a, **k): return subprocess.run(a, env=ENV_SIM if a and a[0] == 'xcrun' else ENV, capture_output=True, text=True, **k)
def now(): return int(time.time() * 1000)
def tap(x, y):
    t = now(); sh(IDB, 'ui', 'tap', str(x), str(y), '--udid', U); return t

# ---- the screen, read
SHOT = f'{OUT}/_shot.png'
def shot():
    sh('xcrun', 'simctl', 'io', U, 'screenshot', SHOT)
    return Image.open(SHOT).convert('L').resize((393, 852))
def mean(im, box): return ImageStat.Stat(im.crop(box)).mean[0]
def pill_at(im, y):
    """The search field's pill is a lighter band nearly gutter to gutter; the gutter beside it is canvas."""
    return mean(im, (36, y - 5, 300, y + 5)) - mean(im, (2, y - 5, 14, y + 5))
def keyboard_visible(im):
    """The software keyboard's space bar: a wide, uniform, mid-grey bar at y ≈ 742–762. Without the
    keyboard that band is poster art (high variance). The simulator drops into a no-software-keyboard
    mode on its own (a hardware keyboard it believes is attached — typed text from idb does it,
    and so does something outside these runs); a run without a keyboard measures nothing."""
    st = ImageStat.Stat(im.crop((110, 744, 280, 760)))
    return st.stddev[0] < 10 and 55 < st.mean[0] < 140
def field_state(im):
    """'rest' (pill under the title, y 137), 'focused' (pill pinned at y 89, the X beside it), or None.
    Calibrated on real screenshots: the pill row reads ~50 above its gutter; the title row at rest
    ~5; the recents header that sits at y 137 once focused ~35 — so the focused test comes first."""
    if pill_at(im, 89) > 30: return 'focused'
    if pill_at(im, 137) > 30: return 'rest'
    return None
def wait_for(pred, timeout, every=0.25, what=''):
    t0 = now()
    while now() - t0 < timeout * 1000:
        if pred(): return now()
        time.sleep(every)
    print(f'   !! timed out waiting for {what}', flush=True); return None
def wait_ready(state, timeout=25):
    """The app is up and the field is in `state`, and the screen has stopped changing."""
    last = [None]
    def ok():
        im = shot()
        if field_state(im) != state: last[0] = im; return False
        stable = last[0] is not None and ImageStat.Stat(ImageChops.difference(last[0], im)).mean[0] < 0.6
        last[0] = im
        return stable
    return wait_for(ok, timeout, every=0.5, what=f'field {state}')
def wait_today(timeout=25):
    """Today is up: a screen brighter than the ident's canvas, with the tab bar drawn, and stable
    (the billboard's slow drift is under the threshold)."""
    last = [None]
    def ok():
        im = shot()
        bright = ImageStat.Stat(im).mean[0] > 18
        tabbar = mean(im, (40, 800, 353, 830)) > mean(im, (0, 760, 393, 780)) - 40   # the pill is not darker than the content above it
        stable = last[0] is not None and ImageStat.Stat(ImageChops.difference(last[0], im)).mean[0] < 0.8
        last[0] = im
        return bright and tabbar and stable
    return wait_for(ok, timeout, every=0.5, what='Today')

# ---- the run
REANALYZE = '--reanalyze' in sys.argv
perf_path = os.path.join(sh('xcrun', 'simctl', 'get_app_container', U, B, 'data').stdout.strip(), 'Documents', 'perf.jsonl')
if not REANALYZE and os.path.exists(perf_path): os.remove(perf_path)
if not REANALYZE: sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(0.6)
launch_args = ['-perfProbe', '1'] + (['-openTab', 'discover'] if scenario == 'cycles' else []) \
    + (['-perfNoWarm', '1'] if scenario == 'cold' else []) + extra
mp4 = f'{OUT}/film.mp4'
phases = []
rec = None
def start_rec():
    global rec
    rec = subprocess.Popen(['xcrun', 'simctl', 'io', U, 'recordVideo', '--codec', 'h264', '--force', mp4], env=ENV_SIM, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2.5)   # the encoder's start starves the sim; a tap sent into it lands seconds late
def focus(name, settle=1.6):
    t = tap(196, 137)
    seen = wait_for(lambda: field_state(shot()) == 'focused', 4, every=0.3, what='focus')
    kb = wait_for(lambda: keyboard_visible(shot()), 3, every=0.3, what='the keyboard')
    time.sleep(settle)
    phases.append({'phase': name, 'kind': 'focus', 'tap': t, 'seen': seen, 'kb': kb, 'end': now()}); print('  ', name, flush=True)
    if kb is None and name.endswith('-1'):
        print('   !! NO SOFTWARE KEYBOARD: the simulator is in its hardware-keyboard mode; reboot it (xcrun simctl shutdown/boot) and rerun', flush=True)
        rec.send_signal(signal.SIGINT); rec.wait(timeout=20); sh('xcrun', 'simctl', 'terminate', U, B); sys.exit(3)
def cancel(name, settle=1.4):
    if field_state(shot()) != 'focused':
        print(f'   !! {name}: the field is not focused, no cancel tap', flush=True); return
    t = tap(355, 89)
    seen = wait_for(lambda: field_state(shot()) == 'rest', 4, every=0.3, what='rest')
    time.sleep(settle)
    phases.append({'phase': name, 'kind': 'cancel', 'tap': t, 'seen': seen, 'end': now()}); print('  ', name, flush=True)

t_launch = now()
if REANALYZE:
    phases = json.load(open(f'{OUT}/phases.json'))
elif scenario == 'cycles':
    sh('xcrun', 'simctl', 'launch', U, B, *launch_args)
    wait_ready('rest'); time.sleep(1.0)
    start_rec()
    for n in range(1, 4):
        focus(f'focus-{n}'); cancel(f'cancel-{n}')
else:
    sh('xcrun', 'simctl', 'launch', U, B, *launch_args)
    wait_today()
    time.sleep(4.0 if scenario == 'warm' else 0.2)
    start_rec()
    t = tap(338, 812); phases.append({'phase': 'tab-search', 'kind': 'tab', 'tap': t, 'seen': None, 'end': None})
    phases[-1]['seen'] = wait_ready('rest', timeout=12); phases[-1]['end'] = now(); print('   tab-search', flush=True)
    time.sleep(0.4)
    for n in range(1, 3):
        focus(f'focus-{n}'); cancel(f'cancel-{n}')
if not REANALYZE:
    rec.send_signal(signal.SIGINT); rec.wait(timeout=20)
    sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(1)
    shutil.copy(perf_path, f'{OUT}/perf.jsonl'); json.dump(phases, open(f'{OUT}/phases.json', 'w'))
    if os.path.exists(SHOT): os.remove(SHOT)

# ---- the probe: marks, hitches, stalls per phase
ev = [json.loads(l) for l in open(f'{OUT}/perf.jsonl') if l.strip()]
marks = [e for e in ev if e['event'] == 'mark']
def first_mark(name, after, before=None):
    for m in marks:
        if m['name'] == name and m['t'] >= after - 60 and (before is None or m['t'] <= before): return m
    return None
names = sorted({f for e in ev if e['event'] == 'stall' for smp in e['samples'] for f in smp['frames'] if f != '?' and not f.startswith('[')})
dem = {}
if names:
    r = subprocess.run(['xcrun', 'swift-demangle', '--compact'], input='\n'.join(names), capture_output=True, text=True,
                       env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer'))
    dem = dict(zip(names, r.stdout.splitlines()))
def short(f): return re.sub(r'\(.*?\)', '()', dem.get(f, f)).replace('AniTrack.', '')[:90]
report = []
def out(s): print(s); report.append(s)
first_presented = None
def touch_after(t):
    """The app's own touch-down mark for a tap the driver sent at `t` (idb's clock leads the touch
    by its transport, ~200–400 ms on this machine)."""
    for m in marks:
        if m['name'] == 'touch-down' and t - 50 <= m['t'] <= t + 1500: return m['t']
    return None
for ph in phases:
    td = touch_after(ph['tap'])
    if td: ph['idb'] = ph['tap']; ph['tap'] = td
    a = ph['tap']; b = ph['end'] or a + 3000
    hs = [e for e in ev if e['event'] == 'hitch' and a <= e['t'] <= b]
    st = [e for e in ev if e['event'] == 'stall' and a - 100 <= e['t'] <= b + 200]
    bodies = [m for m in marks if m['name'] == 'search-body' and a <= m['t'] <= a + 1500]
    line = f"{ph['phase']:<10} hitches {len(hs):2d} sum {sum(h['ms'] for h in hs):4d} worst {max([h['ms'] for h in hs], default=0):4d} | stalls {[s['ms'] for s in st]} | body re-runs {len(bodies)}" + ('' if 'idb' in ph else ' | (no touch mark: times from idb)')
    if ph['kind'] == 'focus':
        pr = first_mark('search-presented', a, b); ws = first_mark('keyboard-will-show', a, b); ds = first_mark('keyboard-did-show', a, b)
        if pr and first_presented is None: first_presented = pr['t']
        line += f"\n   tap→presented {pr['t'] - a if pr else '—'} ms · tap→keyboard-will-show {ws['t'] - a if ws else '—'} ms" \
                f" · will→did show {ds['t'] - ws['t'] if (ws and ds) else '—'} ms" + (f" ({ws['detail']})" if ws else '') \
                + f" · seen on screen +{ph['seen'] - a if ph['seen'] else '—'} ms · keyboard seen +{ph['kb'] - a if ph.get('kb') else '—'} ms"
    elif ph['kind'] == 'cancel':
        di = first_mark('search-dismissed', a, b); wh = first_mark('keyboard-will-hide', a, b); dh = first_mark('keyboard-did-hide', a, b)
        line += f"\n   tap→dismissed {di['t'] - a if di else '—'} ms · tap→keyboard-will-hide {wh['t'] - a if wh else '—'} ms" \
                f" · will→did hide {dh['t'] - wh['t'] if (wh and dh) else '—'} ms · seen at rest +{ph['seen'] - a if ph['seen'] else '—'} ms"
    out(line)
    for s in st:
        if s['ms'] < 60: continue
        incl = collections.Counter()
        for smp in s['samples']:
            seen = set()
            for f in smp['frames']:
                if f != '?' and not f.startswith('[') and 'main' not in f and f not in seen: seen.add(f); incl[f] += 1
        leaves = collections.Counter(smp['frames'][0][:44] for smp in s['samples']).most_common(3)
        out(f"    stall {s['ms']} ms leaves {leaves}")
        for f, c in incl.most_common(5): out(f'        {short(f)} ({c})')

# ---- the film: half-size frames at 60 fps, anchored on the first focus
fd = f'{OUT}/frames'; os.makedirs(fd, exist_ok=True)
for f in os.listdir(fd): os.remove(f'{fd}/{f}')
fps = 60
sh('ffmpeg', '-loglevel', 'error', '-y', '-i', mp4, '-vf', f'fps={fps},scale=197:-1', f'{fd}/%05d.png')
frames = sorted(os.listdir(fd))
if frames:
    W, H = Image.open(f'{fd}/{frames[0]}').size; k = W / 393
    regions = {'bar': (0, 0, W, int(170 * k)), 'field': (int(20 * k), int(78 * k), W - int(20 * k), int(100 * k)),
               'content': (0, int(170 * k), W, int(560 * k)), 'keys': (0, int(560 * k), W, H)}
    grey = [Image.open(f'{fd}/{f}').convert('L') for f in frames]
    diffs = {r: [0.0] for r in regions}
    for i in range(1, len(grey)):
        d = ImageChops.difference(grey[i - 1], grey[i])
        for r, box in regions.items(): diffs[r].append(ImageStat.Stat(d.crop(box)).mean[0])
    # Anchor: the first frame in which the bar band moves is the first focus's presentation; the
    # binding flips within a frame or two of it.
    tab = next((p for p in phases if p['kind'] == 'tab'), None)
    if tab:
        # The tab switch is the film's first big change: its touch (+ the tap's own ~50 ms) is the anchor.
        first_move = next((i for i in range(1, len(grey)) if diffs['content'][i] >= 12), None)
        anchor_t, anchor_name = tab['tap'] + 50, 'tab switch'
    else:
        first_move = next((i for i in range(1, len(grey)) if diffs['bar'][i] >= 1.5), None)
        anchor_t, anchor_name = first_presented, 'first focus presented'
    if anchor_t and first_move is not None:
        t_film0 = anchor_t - first_move * 1000 / fps
        out(f'film: {len(frames)} frames at {fps} fps, anchored: frame {first_move} = {anchor_name}')
        for ph in phases:
            fa = max(0, int(round((ph['tap'] - t_film0) / 1000 * fps)) - 6)
            out(f"{ph['phase']:<10} frames from tap −6 (each column = 1/60 s; '.' = no change):")
            for r in regions:
                out(f'   {r:<8} ' + ' '.join(f'{v:.0f}' if v >= 1 else '.' for v in diffs[r][fa:fa + 66]))
            ims = [Image.open(f'{fd}/{frames[i]}') for i in range(fa, min(fa + 48, len(frames)))]
            if ims:
                cols = 12; rows = (len(ims) + cols - 1) // cols
                sheet = Image.new('RGB', (cols * (W + 3) + 3, rows * (H + 3) + 3), (30, 30, 32))
                for i, im in enumerate(ims): sheet.paste(im, (3 + (i % cols) * (W + 3), 3 + (i // cols) * (H + 3)))
                sheet.save(f"{OUT}/sheet-{ph['phase']}.png")
    else:
        out('film: no anchor (no presented mark or no bar movement)')
open(f'{OUT}/report.txt', 'w').write('\n'.join(report))
if '--keep-frames' not in sys.argv: shutil.rmtree(fd, ignore_errors=True)
print('sheets in', OUT)
