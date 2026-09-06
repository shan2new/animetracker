#!/usr/bin/env python3
"""Prove the keyboard warm-up is unseen. Usage: warmup_check.py <tag> [--tab discover] [--film]
With --film the launch is RECORDED (60 fps) and every frame is scanned for the keyboard —
screenshots land only once or twice inside a one-second window on this sim.
Launches the app with the probe, screenshots every 0.2 s from 1 s to 7 s after launch, then
reads the probe's `keyboard-warm` marks (begin/end) and reports whether any screenshot taken
inside that window — or at all — shows the software keyboard (`keyboard_visible`: the space
bar's uniform mid-grey band), and whether the keyboard notifications fired (the warm-up's
keyboard exists for UIKit even though no one sees it)."""
import os, sys, time, json, subprocess
from PIL import Image, ImageStat

P = os.environ.get('PERF_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'build', 'perf'))
U = os.environ.get('PERF_UDID', 'C2AED006-C1A7-49DF-B7B4-764B35373C11'); B = 'com.anitrack.app'
ENV_SIM = {k: v for k, v in os.environ.items() if k != 'DEVELOPER_DIR'}
tag = sys.argv[1]
tab = sys.argv[sys.argv.index('--tab') + 1] if '--tab' in sys.argv else None
OUT = f'{P}/warmup-{tag}'; os.makedirs(OUT, exist_ok=True)
def sh(*a): return subprocess.run(a, env=ENV_SIM, capture_output=True, text=True)
def now(): return int(time.time() * 1000)
def keyboard_visible(path):
    im = Image.open(path).convert('L').resize((393, 852))
    st = ImageStat.Stat(im.crop((110, 744, 280, 760)))
    return st.stddev[0] < 10 and 55 < st.mean[0] < 140
perf_path = os.path.join(sh('xcrun', 'simctl', 'get_app_container', U, B, 'data').stdout.strip(), 'Documents', 'perf.jsonl')
if os.path.exists(perf_path): os.remove(perf_path)
sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(0.6)
args = ['-perfProbe', '1'] + (['-openTab', tab] if tab else [])
FILM = '--film' in sys.argv
rec = None
if FILM:
    rec = subprocess.Popen(['xcrun', 'simctl', 'io', U, 'recordVideo', '--codec', 'h264', '--force', f'{OUT}/launch.mp4'], env=ENV_SIM, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2.5)
t0 = now(); sh('xcrun', 'simctl', 'launch', U, B, *args)
shots = []
# Screenshots from 1 s after launch until the warm-up's end mark has been written (the app
# emerges 3–9 s after launch on this sim), or 16 s.
def warm_end_written():
    try: return any('"end"' in l and 'keyboard-warm' in l for l in open(perf_path))
    except FileNotFoundError: return False
while now() - t0 < 16000:
    if now() - t0 < 1000: time.sleep(0.1); continue
    f = f'{OUT}/s{len(shots):03d}.png'; t = now(); sh('xcrun', 'simctl', 'io', U, 'screenshot', f)
    shots.append((t, f))
    if warm_end_written() and now() - t > 0: break
    time.sleep(0.15)
time.sleep(1.5)
if rec:
    import signal as _sig; rec.send_signal(_sig.SIGINT); rec.wait(timeout=20)
sh('xcrun', 'simctl', 'terminate', U, B); time.sleep(0.8)
# the probe flushes once a second; the terminate may lose the last second — read what is there
ev = [json.loads(l) for l in open(perf_path) if l.strip()]
marks = [e for e in ev if e['event'] == 'mark' and (e['name'].startswith('keyboard') or e['name'] == 'touch-down')]
begin = next((m['t'] for m in marks if m['name'] == 'keyboard-warm' and m['detail'].startswith('begin')), None)
end = next((m['t'] for m in marks if m['name'] == 'keyboard-warm' and m['detail'] == 'end'), None)
print('marks:', [(m['name'], m.get('detail', ''), m['t'] - t0) for m in marks])
print(f"warm-up window: begin +{begin - t0 if begin else '—'} ms, end +{end - t0 if end else '—'} ms after launch")
seen_any = False
for t, f in shots:
    vis = keyboard_visible(f)
    inside = begin and end and begin <= t <= end
    seen_any |= vis
    flag = 'KEYBOARD VISIBLE' if vis else ''
    if inside or vis: print(f"  shot +{t - t0} ms {'(inside the window)' if inside else ''} {flag}")
stalls = [e for e in ev if e['event'] == 'stall' and begin and begin - 1500 <= e['t'] <= (end or begin) + 500]
print('stalls around the warm-up:', [s['ms'] for s in stalls])
print('RESULT:', 'keyboard was SEEN' if seen_any else 'no screenshot shows a keyboard', f'({len(shots)} screenshots)')
if rec:
    # Every frame of the launch film: any frame with a keyboard is a failure.
    fd = f'{OUT}/frames'; os.makedirs(fd, exist_ok=True)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', f'{OUT}/launch.mp4', '-vf', 'fps=60,scale=393:-1', f'{fd}/%05d.png'], env=ENV_SIM)
    frames = sorted(os.listdir(fd)); hits = [i for i, f in enumerate(frames) if keyboard_visible(f'{fd}/{f}')]
    print(f'film: {len(frames)} frames; frames showing a keyboard: {hits[:20]}{"…" if len(hits) > 20 else ""}')
    print('FILM RESULT:', 'keyboard was SEEN in the film' if hits else 'no frame of the launch film shows a keyboard')
    import shutil; shutil.rmtree(fd)
for _, f in shots:
    if not keyboard_visible(f): os.remove(f)
