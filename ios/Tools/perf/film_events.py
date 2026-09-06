#!/usr/bin/env python3
"""Find the transitions in a focus film by the frames themselves. Usage: film_events.py <film-dir> [--min-gap 6] [--keep-frames]
A transition = a run of frames in which some region changed (bar / focused field row / content /
keyboard), runs closer than --min-gap frames merged. Prints each run's per-frame series and writes
a half-size sheet of it (run-4 … run+44) so the eye can check what the numbers say."""
import os, sys, json
from PIL import Image, ImageChops, ImageStat
d = sys.argv[1]; fd = f'{d}/frames'
min_gap = int(sys.argv[sys.argv.index('--min-gap') + 1]) if '--min-gap' in sys.argv else 6
frames = sorted(os.listdir(fd)); W, H = Image.open(f'{fd}/{frames[0]}').size
k = W / 393
regions = {'bar': (0, 0, W, int(170 * k)), 'field': (int(20 * k), int(36 * k), W - int(20 * k), int(70 * k)),
           'content': (0, int(170 * k), W, int(560 * k)), 'keys': (0, int(560 * k), W, H)}
grey = [Image.open(f'{fd}/{f}').convert('L') for f in frames]
diffs = {k: [0.0] for k in regions}
for i in range(1, len(grey)):
    dd = ImageChops.difference(grey[i - 1], grey[i])
    for k, box in regions.items(): diffs[k].append(ImageStat.Stat(dd.crop(box)).mean[0])
active = [any(diffs[k][i] >= 0.8 for k in regions) for i in range(len(grey))]
runs = []; i = 0
while i < len(active):
    if active[i]:
        j = i
        while j + 1 < len(active) and (active[j + 1] or any(active[j + 1:j + 1 + min_gap])): j += 1
        runs.append((i, j)); i = j + 1
    else: i += 1
phases = json.load(open(f'{d}/phases.json')) if os.path.exists(f'{d}/phases.json') else []
print(f'{d}: {len(frames)} frames, {len(runs)} runs')
for n, (a, b) in enumerate(runs):
    print(f'run {n}: frames {a}-{b} ({(b - a + 1) / 60:.2f} s at 60 fps = {(a) / 60:.2f}s into the film)')
    for k in regions:
        s = ' '.join(f'{v:.0f}' if v >= 1 else '.' for v in diffs[k][a:b + 1][:90])
        print(f'   {k:<8} {s}')
    ims = [Image.open(f'{fd}/{frames[i]}') for i in range(max(0, a - 4), min(a + 44, len(frames)))]
    tw, th = W, H; cols = 12; rows = (len(ims) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * (tw + 3) + 3, rows * (th + 3) + 3), (30, 30, 32))
    for i, im in enumerate(ims): sheet.paste(im, (3 + (i % cols) * (tw + 3), 3 + (i // cols) * (th + 3)))
    sheet.save(f'{d}/run-{n}.png')
if '--keep-frames' not in sys.argv:
    import shutil; shutil.rmtree(fd, ignore_errors=True)
