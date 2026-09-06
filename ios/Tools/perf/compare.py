#!/usr/bin/env python3
"""Side-by-side of two or more flow summaries. Usage: compare.py base perf1 [perf2 ...]"""
import os, json, sys
P = os.environ.get('PERF_DIR', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'build', 'perf'))
tags = sys.argv[1:]
runs = {t: json.load(open(f'{P}/{t}/summary.json')) for t in tags}
steps = [r['step'] for r in runs[tags[0]]['rows']]
def cell(t, step, key):
    for r in runs[t]['rows']:
        if r['step'] == step: return r[key]
    return None
print(f"{'step':<16}" + ''.join(f"{t:>22}" for t in tags) + "     (hitches / dropped / worst ms / >100)")
for s in steps:
    print(f"{s:<16}" + ''.join(f"{str(cell(t, s, 'hitches')) + '/' + str(cell(t, s, 'dropped')) + '/' + str(cell(t, s, 'worst_ms')) + '/' + str(cell(t, s, 'over100')):>22}" for t in tags))
print(f"{'TOTAL':<16}" + ''.join(f"{str(runs[t]['total']['hitches']) + '/' + str(runs[t]['total']['dropped']) + '/' + str(runs[t]['total']['worst_ms']) + '/' + str(runs[t]['total']['over100']):>22}" for t in tags))
print(f"\n{'step':<16}" + ''.join(f"{t:>16}" for t in tags) + "     (app % / backboardd %)")
for s in steps:
    print(f"{s:<16}" + ''.join(f"{str(cell(t, s, 'app_cpu')) + ' / ' + str(cell(t, s, 'bb_cpu')):>16}" for t in tags))
