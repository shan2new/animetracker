#!/usr/bin/env python3
"""AniTrack tab-bar glyphs, sourced from the Hugeicons free set (stroke / rounded,
24x24 viewBox) and rendered crisp via rsvg-convert into transparent TEMPLATE imagesets
(@1x/@2x/@3x). The app's own bar (`AppTabBar`, X's anatomy — 25 Sep) tints them with one ink.

X's bar, measured off the owner's iPhone (25 Sep): every tab in ONE ink, the selected tab told
apart only by its glyph — FILLED where the unselected one is an outline (a heavier stroke where a
glyph has nothing to fill, like search) — at a ~2-pt stroke on a ~21-pt glyph. So every glyph
here has two forms: `TabX` (outline, stroke W) and `TabXFill` (the selected form). The fills are
masks over the outline's own shapes, so the two forms share one silhouette and the switch never
moves an edge.

Icons (Hugeicons free, https://hugeicons.com — import names from @hugeicons/core-free-icons):
  TabToday     -> Tv01        (what's on now)
  TabSchedule  -> Calendar03  (calendar + day grid)
  TabLibrary   -> PlayList    (media card with play mark)
  TabDiscover  -> Search01    (X's Explore is a magnifier; it replaced the SF sparkle glyph so the
                               bar is one family)

To swap a glyph, copy the icon's raw SVG paths from hugeicons.com into the shapes below
and re-run this script.
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
# X's outline weight, measured on its bar: ~2 pt at a ~21-pt glyph (Hugeicons ships 1.5).
W = 2
# Search has nothing to fill; X draws its selected magnifier heavier instead.
W_BOLD = 3
os.makedirs(SVGDIR, exist_ok=True)

# --- Shapes (Hugeicons paths, 24u box) ---
TV_SCREEN = ("M2 14C2 10.2288 2 8.34315 3.17157 7.17157C4.34315 6 6.22876 6 10 6H14C17.7712 6 19.6569 6 "
             "20.8284 7.17157C22 8.34315 22 10.2288 22 14C22 17.7712 22 19.6569 20.8284 20.8284C19.6569 22 "
             "17.7712 22 14 22H10C6.22876 22 4.34315 22 3.17157 20.8284C2 19.6569 2 17.7712 2 14Z")
TV_ANTENNA = "M9 3L12 6L16 2"

CAL_RINGS = "M16 2V6M8 2V6"
CAL_BODY = ("M13 4H11C7.22876 4 5.34315 4 4.17157 5.17157C3 6.34315 3 8.22876 3 12V14C3 17.7712 3 "
            "19.6569 4.17157 20.8284C5.34315 22 7.22876 22 11 22H13C16.7712 22 18.6569 22 19.8284 "
            "20.8284C21 19.6569 21 17.7712 21 14V12C21 8.22876 21 6.34315 19.8284 5.17157C18.6569 4 "
            "16.7712 4 13 4Z")
CAL_HEADER = "M3 10H21"
# The day grid: Calendar03's five dots (three on the first row, two on the second).
CAL_DOTS = [(7.5, 14), (12, 14), (16.5, 14), (7.5, 18), (12, 18)]
DOT_R = 1.2

LIB_BODY = ("M2.5 12C2.5 7.52166 2.5 5.28249 3.89124 3.89124C5.28249 2.5 7.52166 2.5 12 2.5C16.4783 "
            "2.5 18.7175 2.5 20.1088 3.89124C21.5 5.28249 21.5 7.52166 21.5 12C21.5 16.4783 21.5 "
            "18.7175 20.1088 20.1088C18.7175 21.5 16.4783 21.5 12 21.5C7.52166 21.5 5.28249 21.5 "
            "3.89124 20.1088C2.5 18.7175 2.5 16.4783 2.5 12Z")
LIB_SLAT = "M2.50012 7.5H21.5001"
LIB_DIAGONALS = "M17.0001 2.5L14.0001 7.5M10.0001 2.5L7.00012 7.5"
LIB_PLAY = ("M14.9531 14.8948C14.8016 15.5215 14.0857 15.9644 12.6539 16.8502C11.2697 17.7064 10.5777 "
            "18.1346 10.0199 17.9625C9.78934 17.8913 9.57925 17.7562 9.40982 17.57C9 17.1198 9 16.2465 "
            "9 14.5C9 12.7535 9 11.8802 9.40982 11.4299C9.57925 11.2438 9.78934 11.1087 10.0199 "
            "11.0375C10.5777 10.8654 11.2697 11.2936 12.6539 12.1498C14.0857 13.0356 14.8016 13.4785 "
            "14.9531 14.1052C15.0156 14.3639 15.0156 14.6361 14.9531 14.8948Z")

SEARCH_HANDLE = "M17.5 17.5L22 22"
SEARCH_RING = ("M20 11C20 6.02944 15.9706 2 11 2C6.02944 2 2 6.02944 2 11C2 15.9706 6.02944 20 11 "
               "20C15.9706 20 20 15.9706 20 11Z")


def stroke(d, w=W, cap="round"):
    return (f'<path d="{d}" stroke="currentColor" stroke-width="{w}" stroke-linecap="{cap}" '
            'stroke-linejoin="round"/>')


def solid(d, w=W):
    """A shape filled AND stroked, so its outer edge is exactly the outline form's."""
    return f'<path d="{d}" fill="currentColor" stroke="currentColor" stroke-width="{w}" stroke-linejoin="round"/>'


def dots(fill="currentColor"):
    return "".join(f'<circle cx="{x}" cy="{y}" r="{DOT_R}" fill="{fill}"/>' for x, y in CAL_DOTS)


def knockout(mask_id, shapes, cut):
    """`shapes` with `cut` removed — transparent, so the template tints only what remains."""
    return (f'<defs><mask id="{mask_id}" maskUnits="userSpaceOnUse" x="{-PAD}" y="{-PAD}" '
            f'width="{VB}" height="{VB}"><rect x="{-PAD}" y="{-PAD}" width="{VB}" height="{VB}" '
            f'fill="white"/>{cut}</mask></defs><g mask="url(#{mask_id})">{shapes}</g>')


GLYPHS = {
    # Tv01: rounded screen on a centre antenna. Selected: the screen solid.
    "TabToday": stroke(TV_SCREEN) + stroke(TV_ANTENNA),
    "TabTodayFill": solid(TV_SCREEN) + stroke(TV_ANTENNA),

    # Calendar03: binding rings, the body, a header rule and a day grid. Selected: the body solid
    # with the rule and the days cut out of it.
    "TabSchedule": stroke(CAL_RINGS) + stroke(CAL_BODY) + stroke(CAL_HEADER) + dots(),
    "TabScheduleFill": knockout("cal", solid(CAL_BODY),
                                f'<path d="{CAL_HEADER}" stroke="black" stroke-width="{W}"/>' + dots("black"))
                       + stroke(CAL_RINGS),

    # PlayList: a clapper — the top strip with two slats over a card with a play mark. Selected:
    # the card solid with the strip's rule, the slats and the play mark cut out of it.
    "TabLibrary": stroke(LIB_SLAT, cap="butt") + stroke(LIB_DIAGONALS, cap="butt") + stroke(LIB_BODY)
                  + stroke(LIB_PLAY),
    "TabLibraryFill": knockout("lib", solid(LIB_BODY),
                               f'<path d="{LIB_SLAT}" stroke="black" stroke-width="{W}"/>'
                               f'<path d="{LIB_DIAGONALS}" stroke="black" stroke-width="{W}"/>'
                               f'<path d="{LIB_PLAY}" fill="black" stroke="black" stroke-width="0.5" '
                               'stroke-linejoin="round"/>'),

    # Search01: ring and handle. Selected: the same magnifier, heavier (nothing in it to fill).
    "TabDiscover": stroke(SEARCH_HANDLE) + stroke(SEARCH_RING),
    "TabDiscoverFill": stroke(SEARCH_HANDLE, w=W_BOLD) + stroke(SEARCH_RING, w=W_BOLD),
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
