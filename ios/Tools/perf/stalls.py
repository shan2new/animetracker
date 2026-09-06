#!/usr/bin/env python3
"""Aggregate the stall sampler's stacks per flow step.

Usage: stalls.py <tag> [--min 80] [--step NAME] [--top 12]
For every step with stalls at or over --min ms: total stalled time, the stalls, the app symbols
most often ON the stack (inclusive) and the leaf-most frames (self), demangled.
"""
import os, json, sys, subprocess, collections, re

P = os.environ.get('PERF_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'build', 'perf'))
tag = sys.argv[1]
mn = int(sys.argv[sys.argv.index('--min') + 1]) if '--min' in sys.argv else 80
only = sys.argv[sys.argv.index('--step') + 1] if '--step' in sys.argv else None
top = int(sys.argv[sys.argv.index('--top') + 1]) if '--top' in sys.argv else 12
D = f'{P}/{tag}'
ev = [json.loads(l) for l in open(f'{D}/perf.jsonl') if l.strip()]
steps = json.load(open(f'{D}/steps.jsonl'))
stalls = [e for e in ev if e['event'] == 'stall' and e['ms'] >= mn]

APP = '[AniTrack.debug.dylib] '
def is_app(f):
    return f != '?' and (not f.startswith('[') or f.startswith(APP) or f.startswith('[AniTrack] '))
def app_sym(f):
    return f[len(APP):] if f.startswith(APP) else (f[len('[AniTrack] '):] if f.startswith('[AniTrack] ') else f)
names = set()
for st in stalls:
    for s in st['samples']:
        for f in s['frames']:
            if is_app(f): names.add(app_sym(f))
dem = {}
if names:
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer')
    r = subprocess.run(['xcrun', 'swift-demangle', '--compact'], input='\n'.join(sorted(names)), capture_output=True, text=True, env=env)
    for raw, d in zip(sorted(names), r.stdout.splitlines()):
        d = re.sub(r'\(.*?\)', '()', d)           # drop parameter lists
        d = re.sub(r'AniTrack\.', '', d)
        d = d.replace('closure #', 'c#').replace(' in ', '←')
        dem[raw] = d[:140]

def short(f):
    if is_app(f): f = app_sym(f)
    if f.startswith('['):
        m = re.match(r'\[(.*?)\] ?(.*)', f)
        img, sym = m.group(1), m.group(2)
        return f'[{img}] {sym[:60]}' if sym else f'[{img}]'
    return dem.get(f, f)

def report(label, group):
    incl = collections.Counter(); leaf = collections.Counter(); n = 0
    for st in group:
        for s in st['samples']:
            n += 1
            frs = s['frames']
            seen = set()
            for f in frs:
                if not is_app(f): continue
                f = app_sym(f)
                if f in seen: continue
                seen.add(f); incl[f] += 1
            # leaf: the first frame, plus the first APP frame under it
            leaf[short(frs[0])] += 1
            app = next((f for f in frs if is_app(f)), None)
            if app: leaf['↳ ' + short(app)] += 1
    total = sum(st['ms'] for st in group)
    print(f"\n=== {label}: {len(group)} stalls, {total} ms stalled, {n} samples; stalls: {' '.join(str(st['ms']) for st in group)}")
    print('  -- on the stack (app frames) --')
    for f, c in incl.most_common(top): print(f"  {100*c/n:5.1f}%  {short(f)}")
    print('  -- leaf / first app frame --')
    for f, c in leaf.most_common(top): print(f"  {100*c/n:5.1f}%  {f}")

for s in steps:
    if only and s['step'] != only: continue
    group = [st for st in stalls if s['start'] <= st['t'] <= s['end'] + 200]
    if group: report(s['step'], group)
if not only and stalls: report('ALL', stalls)
