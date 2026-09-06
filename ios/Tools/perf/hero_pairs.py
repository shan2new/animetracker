#!/usr/bin/env python3
"""Before/after sheet of the heroes: <before-dir> <after-dir> <out.png>."""
import sys, os
from PIL import Image, ImageDraw
b, a, out = sys.argv[1:4]
names = [('today', 'today'), ('detail-wed', 'detail-wed'), ('detail-got', 'detail-got'), ('detail-aot', 'detail-aot'), ('detail-slime', 'detail-slime')]
tiles = []
for nb, na in names:
    pb, pa = f'{b}/{nb}.png', f'{a}/{na}.png'
    if not (os.path.exists(pb) and os.path.exists(pa)): continue
    ib, ia = Image.open(pb), Image.open(pa)
    for im in (ib, ia): im.thumbnail((300, 650))
    tiles.append((nb, ib, ia))
w, h = 300, 650
sheet = Image.new('RGB', (len(tiles) * (2 * w + 24) + 12, h + 40), (24, 24, 26))
d = ImageDraw.Draw(sheet)
for i, (n, ib, ia) in enumerate(tiles):
    x = 12 + i * (2 * w + 24)
    sheet.paste(ib, (x, 32)); sheet.paste(ia, (x + w + 6, 32))
    d.text((x, 10), f'{n}: before | after', fill=(220, 220, 220))
sheet.save(out); print('sheet', sheet.size, len(tiles), 'pairs')
