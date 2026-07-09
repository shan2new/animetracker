#!/usr/bin/env python3
"""AniTrack tab-bar glyphs, sourced from the Hugeicons free set (stroke / rounded,
24x24 viewBox) and rendered crisp via rsvg-convert into transparent TEMPLATE imagesets
(@1x/@2x/@3x). Stroke paths use `currentColor`, so they tint with the iOS 26 glass bar's
selected/unselected states. Shared weight is the Hugeicons 1.5px stroke at ~28pt.

Icons (Hugeicons free, https://hugeicons.com — import names from @hugeicons/core-free-icons):
  TabToday    -> Tv01            (what's on now)
  TabSchedule -> Calendar03      (calendar + day grid)
  TabLibrary  -> PlayList        (media card with play mark)
  TabAdd      -> PlusSignSquare  (rounded square with a plus)

To swap a glyph, copy the icon's raw SVG paths from hugeicons.com into GLYPHS below
(keep stroke="currentColor", fill="none" on the root) and re-run this script.
"""
import json, os, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SVGDIR = os.path.join(HERE, "vector")
XCASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "ios", "Resources", "Assets.xcassets"))
PT = 30
SCALES = [1, 2, 3]
# Hugeicons content bleeds to a ~2u margin in its 24u box; the old bespoke glyphs sat at a ~4u
# margin. Pad the canvas so the glyph's optical footprint matches (and isn't oversized in the bar).
PAD = 3
VB = 24 + 2 * PAD
os.makedirs(SVGDIR, exist_ok=True)

# Inner SVG markup (paths only) for each glyph. The root <svg fill="none"> is added by svg().
GLYPHS = {
    # Tv01: rounded screen on a center antenna.
    "TabToday": '''
  <path d="M2 14C2 10.2288 2 8.34315 3.17157 7.17157C4.34315 6 6.22876 6 10 6H14C17.7712 6 19.6569 6 20.8284 7.17157C22 8.34315 22 10.2288 22 14C22 17.7712 22 19.6569 20.8284 20.8284C19.6569 22 17.7712 22 14 22H10C6.22876 22 4.34315 22 3.17157 20.8284C2 19.6569 2 17.7712 2 14Z" stroke="currentColor" stroke-linecap="round" stroke-width="1.5"/>
  <path d="M9 3L12 6L16 2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"/>''',

    # Calendar03: rounded calendar with binding tabs, header bar and a 3x2 day grid.
    "TabSchedule": '''
  <path d="M16 2V6M8 2V6" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"/>
  <path d="M13 4H11C7.22876 4 5.34315 4 4.17157 5.17157C3 6.34315 3 8.22876 3 12V14C3 17.7712 3 19.6569 4.17157 20.8284C5.34315 22 7.22876 22 11 22H13C16.7712 22 18.6569 22 19.8284 20.8284C21 19.6569 21 17.7712 21 14V12C21 8.22876 21 6.34315 19.8284 5.17157C18.6569 4 16.7712 4 13 4Z" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"/>
  <path d="M3 10H21" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"/>
  <path d="M12.1258 14H12.0008M12.1258 18H12.0008M7.625 14H7.5M7.625 18H7.5M16.625 14H16.5M12.2508 14C12.2508 14.1381 12.1389 14.25 12.0008 14.25C11.8628 14.25 11.7508 14.1381 11.7508 14C11.7508 13.8619 11.8628 13.75 12.0008 13.75C12.1389 13.75 12.2508 13.8619 12.2508 14ZM12.2508 18C12.2508 18.1381 12.1389 18.25 12.0008 18.25C11.8628 18.25 11.7508 18.1381 11.7508 18C11.7508 17.8619 11.8628 17.75 12.0008 17.75C12.1389 17.75 12.2508 17.8619 12.2508 18ZM7.75 14C7.75 14.1381 7.63807 14.25 7.5 14.25C7.36193 14.25 7.25 14.1381 7.25 14C7.25 13.8619 7.36193 13.75 7.5 13.75C7.63807 13.75 7.75 13.8619 7.75 14ZM7.75 18C7.75 18.1381 7.63807 18.25 7.5 18.25C7.36193 18.25 7.25 18.1381 7.25 18C7.25 17.8619 7.36193 17.75 7.5 17.75C7.63807 17.75 7.75 17.8619 7.75 18ZM16.75 14C16.75 14.1381 16.6381 14.25 16.5 14.25C16.3619 14.25 16.25 14.1381 16.25 14C16.25 13.8619 16.3619 13.75 16.5 13.75C16.6381 13.75 16.75 13.8619 16.75 14Z" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"/>''',

    # PlayList: rounded media card with a play triangle, slats reading like film/episodes.
    "TabLibrary": '''
  <path d="M2.50012 7.5H21.5001" stroke="currentColor" stroke-linejoin="round" stroke-width="1.5"/>
  <path d="M17.0001 2.5L14.0001 7.5" stroke="currentColor" stroke-linejoin="round" stroke-width="1.5"/>
  <path d="M10.0001 2.5L7.00012 7.5" stroke="currentColor" stroke-linejoin="round" stroke-width="1.5"/>
  <path d="M2.5 12C2.5 7.52166 2.5 5.28249 3.89124 3.89124C5.28249 2.5 7.52166 2.5 12 2.5C16.4783 2.5 18.7175 2.5 20.1088 3.89124C21.5 5.28249 21.5 7.52166 21.5 12C21.5 16.4783 21.5 18.7175 20.1088 20.1088C18.7175 21.5 16.4783 21.5 12 21.5C7.52166 21.5 5.28249 21.5 3.89124 20.1088C2.5 18.7175 2.5 16.4783 2.5 12Z" stroke="currentColor" stroke-width="1.5"/>
  <path d="M14.9531 14.8948C14.8016 15.5215 14.0857 15.9644 12.6539 16.8502C11.2697 17.7064 10.5777 18.1346 10.0199 17.9625C9.78934 17.8913 9.57925 17.7562 9.40982 17.57C9 17.1198 9 16.2465 9 14.5C9 12.7535 9 11.8802 9.40982 11.4299C9.57925 11.2438 9.78934 11.1087 10.0199 11.0375C10.5777 10.8654 11.2697 11.2936 12.6539 12.1498C14.0857 13.0356 14.8016 13.4785 14.9531 14.1052C15.0156 14.3639 15.0156 14.6361 14.9531 14.8948Z" stroke="currentColor" stroke-linejoin="round" stroke-width="1.5"/>''',

    # PlusSignSquare: rounded square with a centered plus.
    "TabAdd": '''
  <path d="M2.5 12C2.5 7.52166 2.5 5.28249 3.89124 3.89124C5.28249 2.5 7.52166 2.5 12 2.5C16.4783 2.5 18.7175 2.5 20.1088 3.89124C21.5 5.28249 21.5 7.52166 21.5 12C21.5 16.4783 21.5 18.7175 20.1088 20.1088C18.7175 21.5 16.4783 21.5 12 21.5C7.52166 21.5 5.28249 21.5 3.89124 20.1088C2.5 18.7175 2.5 16.4783 2.5 12Z" stroke="currentColor" stroke-linejoin="round" stroke-width="1.5"/>
  <path d="M12 8V16M16 12H8" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"/>''',
}


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" '
            f'viewBox="{-PAD} {-PAD} {VB} {VB}" width="{VB}" height="{VB}" '
            f'fill="none">{body}\n</svg>')


def contents(name):
    return {
        "images": [{"idiom": "universal", "filename": f"{name}@{s}x.png", "scale": f"{s}x"} for s in SCALES],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }


for name, body in GLYPHS.items():
    svgpath = os.path.join(SVGDIR, f"{name}.svg")
    with open(svgpath, "w") as f:
        f.write(svg(body))
    outdir = os.path.join(XCASSETS, f"{name}.imageset")
    os.makedirs(outdir, exist_ok=True)
    for s in SCALES:
        px = PT * s
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px),
                        svgpath, "-o", os.path.join(outdir, f"{name}@{s}x.png")], check=True)
    with open(os.path.join(outdir, "Contents.json"), "w") as f:
        json.dump(contents(name), f, indent=2)
    print(f"{name}  ok")
print("done ->", XCASSETS)
