#!/usr/bin/env python3
"""Score a typing test: typing_report.py <tag> — hitches relative to the keystrokes, and each
stall's leaves and app frames (demangled)."""
import json, os, re, subprocess, sys
P = os.environ.get('PERF_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'build', 'perf'))
if not os.path.exists(f'{P}/typing-{sys.argv[1]}'):
    P = '/private/tmp/claude-501/-Users-shantanusinha-Desktop-workspace-animetracker/231c4454-cb8b-4cea-bad3-83e64fe6383a/scratchpad/perf'
D = f'{P}/typing-{sys.argv[1]}'
ev = [json.loads(l) for l in open(f'{D}/perf.jsonl') if l.strip()]
keys = json.load(open(f'{D}/keys.json'))
ks = [k['t'] for k in keys['keys']]
t0, t1 = ks[0] - 200, keys['end'] + 300
st = [e for e in ev if e['event'] == 'stall' and t0 <= e['t'] <= t1]
hs = [e for e in ev if e['event'] == 'hitch' and t0 <= e['t'] <= t1]
def is_app(f): return f != '?' and not f.startswith('[')
names = sorted({f for s in st for smp in s['samples'] for f in smp['frames'] if is_app(f)})
dem = {}
if names:
    r = subprocess.run(['xcrun', 'swift-demangle', '--compact'], input='\n'.join(names), capture_output=True, text=True,
                       env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer'))
    dem = dict(zip(names, r.stdout.splitlines()))
print(f"{sys.argv[1]}: {len(ks)} keys over {ks[-1] - ks[0]} ms; hitches {len(hs)} sum {sum(h['ms'] for h in hs)} ms worst {max([h['ms'] for h in hs], default=0)} ms; stalls {[s['ms'] for s in st]}")
print('keys at:', [k - ks[0] for k in ks])
print('hitches at (ms, len):', [(h['t'] - ks[0], h['ms']) for h in hs])
for s in st:
    print(f"stall {s['ms']} ms at {s['t'] - ks[0]}")
    for smp in s['samples'][:6]:
        app = [re.sub(r'\(.*?\)', '()', dem.get(f, f)).replace('AniTrack.', '')[:60] for f in smp['frames'] if is_app(f) and 'main' not in f][:3]
        print(f"   {smp['ms']:4d}  {smp['frames'][0][:46]:<48} {' < '.join(app)}")
