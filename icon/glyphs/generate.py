#!/usr/bin/env python3
"""Render AniTrack's hand-authored, Hugeicons-inspired UI glyphs into template assets.

The SVG paths in this file are original drawings on a 24-unit grid. Run from any directory:
    python3 icon/glyphs/generate.py
"""
from __future__ import annotations

import sys as _sys
if "--force" not in _sys.argv:
    _sys.exit("Superseded (26 Sep): the app's glyphs are Tabler icons now — run icon/tabler/icons.py.\n"
              "This script would redraw ios/Shared/AppSymbols.xcassets with the retired hand-drawn set;\n"
              "pass --force only to regenerate that retired set on purpose.")

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SVG_DIR = Path(__file__).resolve().parent / "vector"
CATALOG = ROOT / "ios/Shared/AppSymbols.xcassets"
SCALES = (1, 2, 3)
INK = "#ffffff"
HOLE = "#000000"


def path(d: str, *, fill: str = "none", stroke: str = INK, width: float = 2,
         cap: str = "round", join: str = "round") -> str:
    attrs = [f'd="{d}"', f'fill="{fill}"']
    if stroke != "none":
        attrs += [f'stroke="{stroke}"', f'stroke-width="{width}"',
                  f'stroke-linecap="{cap}"', f'stroke-linejoin="{join}"']
    return f'<path {" ".join(attrs)} />'


def circle(cx: float, cy: float, r: float, *, fill: str = "none", stroke: str = INK,
           width: float = 2) -> str:
    attrs = f'cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
    if stroke != "none":
        attrs += f' stroke="{stroke}" stroke-width="{width}"'
    return f'<circle {attrs} />'


def rect(x: float, y: float, w: float, h: float, r: float = 2, *, fill: str = "none",
         stroke: str = INK, width: float = 2) -> str:
    attrs = f'x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'
    if stroke != "none":
        attrs += f' stroke="{stroke}" stroke-width="{width}"'
    return f'<rect {attrs} />'


def line(x1: float, y1: float, x2: float, y2: float, *, color: str = INK,
         width: float = 2) -> str:
    return (f'<path d="M{x1} {y1}L{x2} {y2}" fill="none" stroke="{color}" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" />')


def group(content: str, transform: str) -> str:
    return f'<g transform="{transform}">{content}</g>'


def cutout(shape: str, hole: str, ident: str = "cut") -> str:
    return (f'<defs><mask id="{ident}" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">'
            f'<rect width="24" height="24" fill="white" />{hole}</mask></defs>'
            f'<g mask="url(#{ident})">{shape}</g>')


def check(color: str = INK, width: float = 2.2) -> str:
    return path("M5 12.5l4.3 4.2L19.5 6.8", stroke=color, width=width)


def cross(color: str = INK, width: float = 2) -> str:
    return path("M6.5 6.5l11 11m0-11l-11 11", stroke=color, width=width)


def arrow(direction: str, color: str = INK, width: float = 2) -> str:
    points = {
        "left": "M19 12H5m7-7l-7 7 7 7",
        "right": "M5 12h14m-7-7l7 7-7 7",
        "up": "M12 19V5m-7 7l7-7 7 7",
        "down": "M12 5v14m7-7l-7 7-7-7",
        "up-left": "M17 17L7 7m0 9V7h9",
        "up-right": "M7 17L17 7m-9 0h9v9",
        "down-left": "M17 7L7 17m0-9v9h9",
        "down-right": "M7 7l10 10m0-9v9H8",
    }
    return path(points[direction], stroke=color, width=width)


def chevron(direction: str, color: str = INK, width: float = 2) -> str:
    points = {
        "left": "M15 5l-7 7 7 7",
        "right": "M9 5l7 7-7 7",
        "up": "M5 15l7-7 7 7",
        "down": "M5 9l7 7 7-7",
    }
    return path(points[direction], stroke=color, width=width)


def arc_arrow(clockwise: bool = True) -> str:
    if clockwise:
        return (path("M19.5 8A8 8 0 1 0 20 12", stroke=INK, width=2)
                + path("M15.7 4.8l4.6 3.7-5.8 1.3", stroke=INK, width=2))
    return (path("M4.5 8A8 8 0 1 1 4 12", stroke=INK, width=2)
            + path("M8.3 4.8L3.7 8.5l5.8 1.3", stroke=INK, width=2))


def circle_mark(mark: str, filled: bool = False) -> str:
    base = circle(12, 12, 9, fill=INK if filled else "none", stroke="none" if filled else INK)
    if mark == "check":
        inner = check(HOLE if filled else INK, 2.3)
    elif mark == "x":
        inner = cross(HOLE if filled else INK, 2.0)
    elif mark == "minus":
        inner = line(7.5, 12, 16.5, 12, color=HOLE if filled else INK, width=2)
    elif mark == "plus":
        inner = line(12, 7.5, 12, 16.5, color=HOLE if filled else INK, width=2) + line(7.5, 12, 16.5, 12, color=HOLE if filled else INK, width=2)
    elif mark == "info":
        color = HOLE if filled else INK
        inner = circle(12, 7.4, 1, fill=color, stroke="none") + line(12, 11, 12, 16.5, color=color, width=2)
    elif mark == "exclamation":
        color = HOLE if filled else INK
        inner = line(12, 6.2, 12, 14.2, color=color, width=2.1) + circle(12, 17, .75, fill=color, stroke="none")
    else:
        inner = ""
    if filled and inner:
        return cutout(base, inner, "circle-mark")
    return base + inner


def person(fill: bool = False) -> str:
    if fill:
        return (circle(12, 7.5, 3.3, fill=INK, stroke="none")
                + path("M4.2 20v-1.1a7.8 7.8 0 0 1 15.6 0V20Z", fill=INK, stroke="none"))
    return (circle(12, 7.5, 3.2) + path("M4.2 20a7.8 7.8 0 0 1 15.6 0", stroke=INK, width=2))


def bell(fill: bool = False) -> str:
    d = "M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"
    if not fill:
        return path(d, stroke=INK, width=2)
    shape = path("M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z", fill=INK, stroke="none")
    return shape + path("M10 21h4", stroke=INK, width=2)


def bookmark(slash: bool = False, fill: bool = False) -> str:
    d = "M6 4.5A1.5 1.5 0 0 1 7.5 3h9A1.5 1.5 0 0 1 18 4.5V21l-6-4-6 4Z"
    shape = path(d, fill=INK if fill else "none", stroke="none" if fill else INK, width=2)
    if slash:
        shape += path("M4 4l16 16", stroke=INK, width=2.2)
    return shape


def bubble(double: bool = False) -> str:
    first = path("M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8a2.5 2.5 0 0 1-2.5 2.5H11l-5.5 4v-4.2A2.5 2.5 0 0 1 4 13.5Z", stroke=INK, width=1.8)
    if not double:
        return first
    second = path("M7 2.7h10.5A2.5 2.5 0 0 1 20 5.2", stroke=INK, width=1.8)
    return first + second


def clock_face() -> str:
    return circle(12, 12, 9) + path("M12 7v5l3.5 2", stroke=INK, width=2)


def file_page(lines: int = 2, folded: bool = True) -> str:
    outline = path("M6 3.5h8l4 4V20a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4.5a1 1 0 0 1 1-1Z", stroke=INK)
    if folded:
        outline += path("M14 3.8V8h4", stroke=INK)
    for y in range(11, 11 + lines * 3, 3):
        outline += line(8, y, 15.5, y, width=1.6)
    return outline


def eye(slash: bool = False, filled: bool = False) -> str:
    if filled:
        shape = path("M2.5 12s3.4-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.4 6.5-9.5 6.5S2.5 12 2.5 12Z", fill=INK, stroke="none")
        holes = circle(12, 12, 2.5, fill=HOLE, stroke="none")
        if slash:
            holes += path("M4 20 20 4", stroke=HOLE, width=2.1)
        return cutout(shape, holes, "eye-fill")
    result = path("M2.5 12s3.4-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.4 6.5-9.5 6.5S2.5 12 2.5 12Z", stroke=INK, width=1.8)
    result += circle(12, 12, 2.5)
    if slash:
        result += path("M4 20 20 4", stroke=INK, width=2.1)
    return result


def heart(fill: bool = False) -> str:
    d = "M12 20.2 4.1 12.7A5 5 0 0 1 11.2 5.6L12 6.4l.8-.8a5 5 0 0 1 7.1 7.1Z"
    return path(d, fill=INK if fill else "none", stroke="none" if fill else INK, width=1.8)


def hand_raised() -> str:
    return path("M7.2 12V5.4a1.3 1.3 0 0 1 2.6 0v5.1V4.2a1.3 1.3 0 0 1 2.6 0v6.3V5a1.3 1.3 0 0 1 2.6 0v6.1V6.7a1.3 1.3 0 0 1 2.6 0v7.6c0 4.5-2.4 7-6.4 7h-1.4c-2.1 0-3.2-.8-4.3-2.5L3.6 14a1.5 1.5 0 0 1 2.4-1.8l1.2 1.5Z", stroke=INK, width=1.7)


def filter_lines(circle_badge: bool = False) -> str:
    lines = (path("M3 5h18M6 12h12m-9 7h6", stroke=INK, width=1.8)
             + circle(6, 5, 1.6, fill=INK, stroke="none")
             + circle(16, 12, 1.6, fill=INK, stroke="none")
             + circle(10, 19, 1.6, fill=INK, stroke="none"))
    if not circle_badge:
        return lines
    return lines + circle(17.8, 17.8, 4.2, fill="none", stroke=INK, width=1.6)


def wifi(kind: str) -> str:
    waves = (path("M3.5 8.7a13.3 13.3 0 0 1 17 0M6.8 12a8.4 8.4 0 0 1 10.4 0M10 15.2a3.5 3.5 0 0 1 4 0", stroke=INK, width=1.8)
             + circle(12, 19, 1.2, fill=INK, stroke="none"))
    if kind == "slash":
        return waves + path("M4 4l16 16", stroke=INK, width=2)
    if kind == "exclamation":
        badge = circle(19, 5, 4, fill=INK, stroke="none")
        mark = line(19, 3, 19, 5, color=HOLE, width=1.4) + circle(19, 6.5, .45, fill=HOLE, stroke="none")
        return waves + cutout(badge, mark, "wifi-alert")
    return waves


def speaker(kind: str, filled: bool = False) -> str:
    d = "M3.5 9v6h4l5 4V5l-5 4Z"
    body = path(d, fill=INK if filled else "none", stroke="none" if filled else INK, width=1.8)
    if kind == "slash":
        body += cross(INK, 1.8)
    elif kind == "wave":
        body += path("M16 9a4 4 0 0 1 0 6m2-9a7 7 0 0 1 0 12", stroke=INK, width=1.8)
    return body


def person_badge(kind: str) -> str:
    base = circle(10, 11, 8.3) + circle(10, 8, 2.7) + path("M5.5 17a5 5 0 0 1 9 0", stroke=INK, width=1.6)
    badge = circle(18.5, 18, 4.2, fill=INK, stroke="none")
    if kind == "x":
        inner = cross(HOLE, 1.5)
    else:
        inner = line(18.5, 15.8, 18.5, 18, color=HOLE, width=1.4) + circle(18.5, 19.4, .5, fill=HOLE, stroke="none")
    return base + cutout(group(badge, "translate(-.5 -.5)"), group(inner, "translate(-.5 -.5)"), "person-badge")


def glyph(name: str) -> str:
    if name in ("arrow.left", "arrow.up", "arrow.up.right", "arrow.up.forward", "arrow.up.backward"):
        return arrow({"arrow.left": "left", "arrow.up": "up", "arrow.up.right": "up-right", "arrow.up.forward": "up-right", "arrow.up.backward": "up-left"}[name])
    if name in ("arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right"):
        if name == "arrow.down.right.and.arrow.up.left":
            return path("M10 4H4v6M4 4l7 7M14 20h6v-6m0 6-7-7", stroke=INK, width=2)
        return path("M4 14v6h6m-6 0 7-7M20 10V4h-6m6 0-7 7", stroke=INK, width=2)
    if name == "arrow.clockwise": return arc_arrow(True)
    if name == "arrow.counterclockwise": return arc_arrow(False)
    if name == "arrow.triangle.2.circlepath":
        return path("M7 7h10l-2.8-2.8M17 17H7l2.8 2.8M18 7a7 7 0 0 1 1 9M6 17a7 7 0 0 1-1-9", stroke=INK, width=1.8)
    if name in ("chevron.left", "chevron.right", "chevron.up", "chevron.down", "chevron.forward", "chevron.right"):
        direction = "right" if name in ("chevron.forward", "chevron.right") else name.split(".")[-1]
        return chevron(direction, width=2.2)
    if name == "chevron.up.chevron.down":
        return chevron("up", width=2.1) + group(chevron("down", width=2.1), "translate(0 7)")
    if name in ("gobackward.10", "goforward.10"):
        body = arc_arrow(name == "goforward.10")
        return body + path("M6.5 16.2h11", stroke=INK, width=1.5) + '<text x="12" y="20" text-anchor="middle" font-family="Arial,sans-serif" font-size="5.4" font-weight="700" fill="#fff">10</text>'
    if name == "ellipsis":
        return ''.join(circle(x, 12, 1.5, fill=INK, stroke="none") for x in (5.5, 12, 18.5))
    if name == "checkmark": return check()
    if name == "xmark": return cross()
    if name == "plus": return line(12, 4.5, 12, 19.5) + line(4.5, 12, 19.5, 12)
    if name == "minus": return line(4.5, 12, 19.5, 12)
    if name == "circle": return circle(12, 12, 8.5)
    if name == "circle.fill": return circle(12, 12, 8.5, fill=INK, stroke="none")
    if name in ("checkmark.circle", "checkmark.circle.fill"):
        return circle_mark("check", name.endswith(".fill"))
    if name == "xmark.circle.fill": return circle_mark("x", True)
    if name == "checkmark.seal.fill":
        badge = path("M12 2.8l2.2 1.3 2.6-.1 1.1 2.4 2.2 1.4-.6 2.5.6 2.5-2.2 1.4-1.1 2.4-2.6-.1L12 21.2l-2.2-1.3-2.6.1-1.1-2.4-2.2-1.4.6-2.5-.6-2.5 2.2-1.4 1.1-2.4 2.6.1Z", fill=INK, stroke="none")
        return cutout(badge, check(HOLE, 2.2), "seal-check")
    if name in ("exclamationmark.circle", "info.circle", "minus.circle"):
        return circle_mark({"exclamationmark.circle": "exclamation", "info.circle": "info", "minus.circle": "minus"}[name])
    if name in ("exclamationmark.triangle.fill", "wifi.exclamationmark"):
        if name == "wifi.exclamationmark": return wifi("exclamation")
        shape = path("M12 3 22 20H2Z", fill=INK, stroke="none")
        hole = line(12, 8, 12, 14, color=HOLE, width=2.2) + circle(12, 17, .7, fill=HOLE, stroke="none")
        return cutout(shape, hole, "warning")
    if name in ("bell", "bell.fill", "bell.badge"):
        body = bell(name == "bell.fill")
        if name == "bell.badge": body += circle(18.5, 5.5, 3.5, fill=INK, stroke="none")
        return body
    if name in ("bookmark", "bookmark.fill", "bookmark.slash"):
        return bookmark(name == "bookmark.slash", name == "bookmark.fill")
    if name == "bubble.left.fill":
        return path("M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8a2.5 2.5 0 0 1-2.5 2.5H11l-5.5 4v-4.2A2.5 2.5 0 0 1 4 13.5Z", fill=INK, stroke="none")
    if name in ("bubble.left", "bubble.left.and.bubble.right", "questionmark.bubble"):
        body = bubble(name == "bubble.left.and.bubble.right")
        if name == "questionmark.bubble":
            body += '<text x="12" y="15.8" text-anchor="middle" font-family="Arial,sans-serif" font-size="9" font-weight="700" fill="#fff">?</text>'
        return body
    if name in ("calendar", "rectangle.stack", "text.book.closed"):
        if name == "calendar":
            return (rect(3.5, 5, 17, 16, 2) + line(3.5, 9, 20.5, 9)
                    + line(8, 3, 8, 7) + line(16, 3, 16, 7)
                    + ''.join(circle(x, y, .75, fill=INK, stroke="none") for x, y in ((8, 13), (12, 13), (16, 13), (8, 17), (12, 17))))
        if name == "text.book.closed":
            return (path("M3.5 5.5h7.2a3.3 3.3 0 0 1 3.3 3.3v11.7a3.3 3.3 0 0 0-3.3-3.3H3.5Zm17 0h-3.2A3.3 3.3 0 0 0 14 8.8v11.7a3.3 3.3 0 0 1 3.3-3.3h3.2Z", stroke=INK, width=1.7)
                    + line(6, 9, 10, 9, width=1.4) + line(6, 12, 10, 12, width=1.4))
        a = rect(4, 5, 13.5, 16, 1.8)
        b = group(rect(6.5, 3, 13.5, 16, 1.8), "translate(2.5 -1)")
        return a + b
    if name in ("chevron.up.chevron.down",): return chevron("up") + chevron("down")
    if name in ("clock", "clock.arrow.circlepath"):
        body = clock_face()
        if name == "clock.arrow.circlepath": body += path("M7 3 4 6l3 3", stroke=INK, width=1.8)
        return body
    if name == "doc.on.doc":
        return rect(8, 4, 12, 15, 1.5) + path("M5 8H4a1 1 0 0 0-1 1v11a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1v-1", stroke=INK, width=1.8)
    if name == "doc.text": return file_page(3)
    if name in ("eye", "eye.slash", "eye.slash.fill"):
        return eye(name.endswith("slash") or name == "eye.slash.fill", name.endswith(".fill"))
    if name in ("heart", "heart.fill"): return heart(name.endswith("fill"))
    if name in ("flag", "flag.fill"):
        if name == "flag.fill":
            return path("M5 21V4", stroke=INK, width=1.9) + path("M5 5c5-4 9 3 14-1v11c-5 4-9-3-14 1Z", fill=INK, stroke="none")
        return path("M5 21V4m0 1c5-4 9 3 14-1v11c-5 4-9-3-14 1", stroke=INK, width=1.9)
    if name == "globe":
        return (circle(12, 12, 9) + path("M3.3 9h17.4M3.3 15h17.4M12 3c2.4 2.4 3.5 5.4 3.5 9s-1.1 6.6-3.5 9c-2.4-2.4-3.5-5.4-3.5-9S9.6 5.4 12 3Z", stroke=INK, width=1.6))
    if name in ("hand.raised", "hand.tap", "hand.thumbsdown"):
        if name == "hand.raised": return hand_raised()
        if name == "hand.thumbsdown": return path("M8 10V4h10l2 6v5h-7l1 5a1.8 1.8 0 0 1-3.3 1L7 15H4V10Z", stroke=INK, width=1.8)
        return path("M9 20V9l4-5a1.8 1.8 0 0 1 2.8 2.2L14 10h4.2a2 2 0 0 1 1.9 2.6l-1.7 5.9a2 2 0 0 1-1.9 1.5Zm-5-9h3v9H4Z", stroke=INK, width=1.7) + path("M18 4l1-2m2 4h2", stroke=INK, width=1.4)
    if name == "magnifyingglass": return circle(10.5, 10.5, 7) + path("m16 16 5 5", stroke=INK, width=2.2)
    if name == "line.3.horizontal.decrease": return filter_lines()
    if name == "line.3.horizontal.decrease.circle.fill": return filter_lines(True)
    if name == "slider.horizontal.3":
        tracks = line(3, 6, 21, 6) + line(3, 12, 21, 12) + line(3, 18, 21, 18)
        holes = ''.join(circle(x, y, 2.1, fill=HOLE, stroke="none") for x, y in ((8, 6), (16, 12), (10, 18)))
        knobs = ''.join(circle(x, y, 2.1) for x, y in ((8, 6), (16, 12), (10, 18)))
        return cutout(tracks, holes, "slider-knobs") + knobs
    if name == "link": return path("M9.5 14.5l5-5m-7.3 8.3H5a3.5 3.5 0 0 1 0-7h4m5-3h5a3.5 3.5 0 0 1 0 7h-4", stroke=INK, width=1.9)
    if name == "lock.fill":
        body = path("M6 10V7a6 6 0 0 1 12 0v3h1.2a1.8 1.8 0 0 1 1.8 1.8v8.4a1.8 1.8 0 0 1-1.8 1.8H4.8A1.8 1.8 0 0 1 3 20.2v-8.4A1.8 1.8 0 0 1 4.8 10Z", fill=INK, stroke="none")
        hole = circle(12, 15, 1, fill=HOLE, stroke="none") + line(12, 16, 12, 18, color=HOLE, width=1.5)
        return cutout(body, hole, "lock-keyhole")
    if name == "newspaper":
        return (rect(3, 4, 18, 16, 1.5) + rect(5.5, 7, 5, 5, .7)
                + line(13, 8, 18, 8, width=1.5) + line(13, 11, 18, 11, width=1.5)
                + line(5.5, 15, 18, 15, width=1.5) + line(5.5, 18, 16, 18, width=1.5))
    if name in ("paperplane", "safari"):
        if name == "paperplane": return path("M3 11.5 21 3l-5.5 18-3.2-7.3Zm9.3 2.2L21 3", stroke=INK, width=1.8)
        return circle(12, 12, 9) + path("m15.8 8.2-2.7 5-5 2.6 2.6-5Z", fill=INK, stroke="none")
    if name in ("person.fill", "person.2.fill"): 
        if name == "person.fill": return person(True)
        return (group(person(True), "translate(-3 0) scale(.8 1)") + group(person(True), "translate(5 0) scale(.8 1)"))
    if name == "person.crop.circle.badge.exclamationmark": return person_badge("!")
    if name == "person.crop.circle.badge.xmark": return person_badge("x")
    if name == "photo":
        return rect(3, 4, 18, 16, 2) + circle(8, 9, 1.5, fill=INK, stroke="none") + path("M4 18l5-5 3 3 4-5 4 5v2H4Z", fill=INK, stroke="none")
    if name == "pin.fill": return path("M16 3 21 8l-3 1.5-3.5 5L13 16l-1 1-1-1-1.5 1.5-4 4-.7-.7 4-4L10.3 15l-1-1 1-1 1.5-1.5-5-3.5L5 6l5-3 2 2Z", fill=INK, stroke="none")
    if name == "play.fill": return path("M7 4.5a1.5 1.5 0 0 1 2.3-1.3l11 7.3a1.8 1.8 0 0 1 0 3l-11 7.3A1.5 1.5 0 0 1 7 19.5Z", fill=INK, stroke="none")
    if name == "pause.fill":
        return rect(5.5, 4, 4.5, 16, 1, fill=INK, stroke="none") + rect(14, 4, 4.5, 16, 1, fill=INK, stroke="none")
    if name in ("play.circle", "pause.circle", "xmark.circle"):
        outline = circle(12, 12, 9)
        if name == "play.circle":
            return outline + path("M10 7.2a1 1 0 0 0-1.5.9v7.8a1 1 0 0 0 1.5.9l6-3.9a1.1 1.1 0 0 0 0-1.8Z", fill=INK, stroke="none")
        if name == "pause.circle":
            return outline + rect(8, 7, 3, 10, .6, fill=INK, stroke="none") + rect(13, 7, 3, 10, .6, fill=INK, stroke="none")
        return circle_mark("x")
    if name in ("play.rectangle", "play.rectangle.on.rectangle"):
        body = rect(3, 5, 18, 14, 2)
        body += path("m10 9 5 3-5 3Z", fill=INK, stroke="none")
        if name == "play.rectangle.on.rectangle": body += path("M6 3h14a1 1 0 0 1 1 1v12", stroke=INK, width=1.7)
        return body
    if name == "plus.circle": return circle_mark("plus")
    if name == "at": return '<text x="12" y="19" text-anchor="middle" font-family="Arial,sans-serif" font-size="20" font-weight="600" fill="none" stroke="#fff" stroke-width="1">@</text>'
    if name == "curlybraces": return path("M9 3H7a2 2 0 0 0-2 2v4a3 3 0 0 1-2 3 3 3 0 0 1 2 3v4a2 2 0 0 0 2 2h2m6-18h2a2 2 0 0 1 2 2v4a3 3 0 0 0 2 3 3 3 0 0 0-2 3v4a2 2 0 0 1-2 2h-2", stroke=INK, width=2)
    if name == "dot.radiowaves.left.and.right":
        return (circle(12, 12, 1.7, fill=INK, stroke="none")
                + path("M8.5 8.5a5 5 0 0 0 0 7m7-7a5 5 0 0 1 0 7M5.5 5.5a9 9 0 0 0 0 13m13-13a9 9 0 0 1 0 13", stroke=INK, width=1.8))
    if name == "envelope": return path("M3 6h18v13H3Zm0 1 9 7 9-7", stroke=INK, width=1.8)
    if name == "ladybug":
        return (circle(12, 13, 7) + path("M9 6V4a3 3 0 0 1 6 0v2M5.5 8 3 6m15.5 2L21 6M5 13H3m16 0h2M8 10l1 1m5-1 1 1m-7 4 1 1m5-1 1 1", stroke=INK, width=1.5)
                + line(12, 7, 12, 20, width=1.4))
    if name == "rectangle.portrait.and.arrow.right":
        return rect(3, 3, 13, 18, 1.5) + path("M11 12h10m-4-4 4 4-4 4", stroke=INK, width=1.8)
    if name == "square.and.arrow.up":
        return rect(4, 9, 16, 12, 1.6) + path("M12 15V3m-5 5 5-5 5 5", stroke=INK, width=2)
    if name == "square.grid.2x2" or name == "tablecells":
        return (rect(3.5, 3.5, 7, 7, 1.2) + rect(13.5, 3.5, 7, 7, 1.2)
                + rect(3.5, 13.5, 7, 7, 1.2) + rect(13.5, 13.5, 7, 7, 1.2))
    if name == "text.append":
        return line(3, 5, 21, 5) + line(3, 10, 19, 10) + line(3, 15, 15, 15) + line(18, 14, 18, 21) + line(14.5, 17.5, 21.5, 17.5)
    if name == "trash":
        return path("M4 6h16m-10-3h4m-8 3 1 14h10l1-14M10 10v6m4-6v6", stroke=INK, width=1.8)
    if name == "tv":
        return rect(2.5, 7, 19, 13, 2) + path("M8 3l4 4 4-4", stroke=INK, width=1.8)
    if name == "wifi.slash": return wifi("slash")
    if name in ("speaker.slash", "speaker.slash.fill", "speaker.wave.2", "speaker.wave.2.fill"):
        kind = "slash" if "slash" in name else "wave"
        return speaker(kind, name.endswith(".fill"))
    if name == "square.stack":
        return (path("M5 4.5A1.5 1.5 0 0 1 6.5 3h12A1.5 1.5 0 0 1 20 4.5v11a1.5 1.5 0 0 1-1.5 1.5h-12A1.5 1.5 0 0 1 5 15.5Z", stroke=INK, width=1.7)
                + path("M3 7v12.5A1.5 1.5 0 0 0 4.5 21H17", stroke=INK, width=1.7))
    if name == "text.book.closed": return file_page(2)
    if name == "hand.thumbsdown": return hand_raised()
    raise KeyError(f"No SVG drawing for symbol: {name}")


SYMBOLS = (
    "\\(index + 1).circle.fill", "arrow.clockwise", "arrow.counterclockwise",
    "arrow.down.right.and.arrow.up.left", "arrow.left", "arrow.triangle.2.circlepath",
    "arrow.up", "arrow.up.backward", "arrow.up.forward", "arrow.up.left.and.arrow.down.right", "arrow.up.right",
    "at", "bell", "bell.badge", "bell.fill", "bookmark", "bookmark.fill", "bookmark.slash",
    "bubble.left", "bubble.left.and.bubble.right", "bubble.left.fill", "calendar", "checkmark", "checkmark.circle",
    "checkmark.circle.fill", "checkmark.seal.fill", "chevron.down", "chevron.forward", "chevron.left",
    "chevron.right", "chevron.up", "chevron.up.chevron.down", "circle", "circle.fill", "clock",
    "clock.arrow.circlepath", "curlybraces", "doc.on.doc", "doc.text", "dot.radiowaves.left.and.right",
    "ellipsis", "envelope", "exclamationmark.circle", "exclamationmark.triangle.fill", "eye", "eye.slash", "eye.slash.fill",
    "flag", "flag.fill", "globe", "gobackward.10", "goforward.10", "hand.raised", "hand.tap", "hand.thumbsdown",
    "heart", "heart.fill", "info.circle", "ladybug", "line.3.horizontal.decrease",
    "line.3.horizontal.decrease.circle.fill", "link", "lock.fill", "magnifyingglass", "minus",
    "minus.circle", "newspaper", "paperplane", "pause.circle", "pause.fill", "person.2.fill", "person.crop.circle.badge.exclamationmark",
    "person.crop.circle.badge.xmark", "person.fill", "photo", "pin.fill", "play.circle", "play.fill", "play.rectangle",
    "play.rectangle.on.rectangle", "plus", "plus.circle", "questionmark.bubble", "rectangle.portrait.and.arrow.right",
    "rectangle.stack", "safari", "slider.horizontal.3", "speaker.slash", "speaker.slash.fill",
    "speaker.wave.2", "speaker.wave.2.fill", "square.and.arrow.up", "square.grid.2x2", "square.stack",
    "tablecells", "text.append", "text.book.closed", "trash", "tv", "wifi.exclamationmark", "wifi.slash", "xmark",
    "xmark.circle", "xmark.circle.fill",
)


def asset_key(name: str) -> str:
    if name == "\\(index + 1).circle.fill":
        return "number-circle"
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def svg_document(body: str) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '
            'fill="none" stroke-linecap="round" stroke-linejoin="round">\n'
            f'{body}\n</svg>\n')


def main() -> None:
    SVG_DIR.mkdir(parents=True, exist_ok=True)
    CATALOG.mkdir(parents=True, exist_ok=True)
    if len(set(SYMBOLS)) != len(SYMBOLS):
        raise RuntimeError("duplicate symbol name")
    generated = set()
    for name in SYMBOLS:
        key = asset_key(name)
        if key in generated:
            continue
        generated.add(key)
        body = circle(12, 12, 9) if key == "number-circle" else glyph(name)
        svg = svg_document(body)
        svg_path = SVG_DIR / f"{key}.svg"
        svg_path.write_text(svg)
        folder = CATALOG / f"Glyph-{key}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        image_records = []
        for scale in SCALES:
            filename = f"Glyph-{key}@{scale}x.png"
            subprocess.run(["rsvg-convert", "-w", str(24 * scale), "-h", str(24 * scale),
                            str(svg_path), "-o", str(folder / filename)], check=True)
            image_records.append({"idiom": "universal", "filename": filename, "scale": f"{scale}x"})
        (folder / "Contents.json").write_text(json.dumps({
            "images": image_records,
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "template"},
        }, indent=2) + "\n")
    catalog = {name: f"Glyph-{asset_key(name)}" for name in SYMBOLS}
    glyph_root = Path(__file__).resolve().parent
    (glyph_root / "symbols.json").write_text(json.dumps(catalog, indent=2) + "\n")
    swift_entries = "\n".join(
        f"        {json.dumps(name)}: {json.dumps(asset)},"
        for name, asset in catalog.items()
    )
    (ROOT / "ios/Shared/AppGlyphCatalog.swift").write_text(
        "// Generated by icon/glyphs/generate.py. Do not edit by hand.\n"
        "enum AppGlyphCatalog {\n"
        "    static let assets: [String: String] = [\n"
        f"{swift_entries}\n"
        "    ]\n"
        "}\n"
    )
    print(f"rendered {len(generated)} original SVG glyphs into {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
