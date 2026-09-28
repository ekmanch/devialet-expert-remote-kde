#!/usr/bin/env python3
"""Spike light-glass: WCAG contrast of the light flyout's tokens under
transparency, computed from token values and alpha compositing.

Why computed, not captured: over a flat backdrop, blur changes nothing, and
saturation barely changes a near-grey. The worst case (minimum light alpha
over near-black #0a0a0c) is therefore exact arithmetic: sRGB "over"
compositing, the same blending browsers and KWin use (confirmed in Phase
17.19.0: a light+dark solve gave alpha 0.500 exactly). capture.sh checks a
sample of these numbers against real headless-Firefox renders (+-0.1).

Token values are the v3 flyout mockup's
(design/mockups/flyout/Devialet Expert Remote Flyout Design Mockup v3.html,
light :61-80 and gold :94-105, readout :110-115, glyphs :134-136, dark :20-53).

Usage:
    python3 tools/spike-light-glass/contrast.py            # writes contrast-tables.md next to this file
    python3 tools/spike-light-glass/contrast.py --selftest # only the known-value check
Rules (owner, spike plan):
    - gates: text 4.5:1, large text (26 px readout) 3:1, state-carrying
      non-text marks 3:1; borders/dividers reported, not gated
    - gradients are gated on their lightest *visible* colour, not an average
    - polarity: a token lighter than its background is never "fixed" by
      darkening it past the panel; that Lmin is unusable for the token
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- colour maths

def hx(h):
    h = h.lstrip("#")
    return tuple(float(int(h[i:i + 2], 16)) for i in (0, 2, 4))


def to_hex(c):
    return "#" + "".join(f"{max(0, min(255, round(v))):02x}" for v in c)


def over(fg, a, bg):
    """fg at alpha a over opaque bg, sRGB (gamma-space) blending."""
    return tuple(f * a + b * (1 - a) for f, b in zip(fg, bg))


def _lin(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def _unlin(v):
    v = v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return v * 255.0


def lum(c):
    r, g, b = (_lin(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def to_oklch(c):
    r, g, b = (_lin(v) for v in c)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s))
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(A, B), math.atan2(B, A)


def from_oklch(L, C, H):
    """OKLCH -> sRGB 0..255; chroma is reduced until the colour is in gamut."""
    for _ in range(60):
        A, B = C * math.cos(H), C * math.sin(H)
        l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
        m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
        s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3
        r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        if all(-1e-4 <= v <= 1 + 1e-4 for v in (r, g, b)):
            return tuple(_unlin(min(1.0, max(0.0, v))) for v in (r, g, b))
        C *= 0.95
    return tuple(_unlin(min(1.0, max(0.0, v))) for v in (r, g, b))


def grad_at(stops, t):
    """Colour of a multi-stop gradient at offset t (stops: [(offset, hex)])."""
    t = max(0.0, min(1.0, t))
    for (o0, c0), (o1, c1) in zip(stops, stops[1:]):
        if o0 <= t <= o1:
            f = 0 if o1 == o0 else (t - o0) / (o1 - o0)
            a, b = hx(c0), hx(c1)
            return tuple(x + (y - x) * f for x, y in zip(a, b))
    return hx(stops[-1][1])

# ------------------------------------------------------ glyph gold (v3 :473, :630-636)

GLYPH_GOLD = [(0.0, "#fcecc0"), (0.38, "#f0a623"), (1.0, "#a8710b")]
GLYPH_CENTRE, GLYPH_R = (6.4, 5.6), 15.5          # userSpaceOnUse, 20-unit box


def _seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _poly_edges(pts):
    return list(zip(pts, pts[1:] + pts[:1]))


def _in_poly(px, py, pts):
    inside = False
    for (ax, ay), (bx, by) in _poly_edges(pts):
        if (ay > py) != (by > py) and px < (bx - ax) * (py - ay) / (by - ay) + ax:
            inside = not inside
    return inside


def _rrect_dist(px, py, x, y, w, h, r):
    cx, cy = x + w / 2, y + h / 2
    qx, qy = abs(px - cx) - (w / 2 - r), abs(py - cy) - (h / 2 - r)
    outside = math.hypot(max(qx, 0), max(qy, 0))
    return abs(outside + min(max(qx, qy), 0) - r)


DIAMOND = [(10, 2.6), (17.4, 10), (10, 17.4), (2.6, 10)]
DIAMOND_IN = [(10, 6.6), (13.4, 10), (10, 13.4), (6.6, 10)]


def _painted(kind, x, y):
    ring = abs(math.hypot(x - 10, y - 10) - 7.2) <= 0.8
    if kind == "optical":
        return ring or math.hypot(x - 10, y - 10) <= 3
    if kind == "upnp":
        return _rrect_dist(x, y, 3, 3, 14, 14, 1.8) <= 0.8 or _seg_dist(x, y, 10, 3, 10, 17) <= 0.8
    if kind == "roon":
        lines = [(6.4, 5.08, 14.92), (8.8, 4.02, 15.98), (11.2, 4.02, 15.98), (13.6, 5.08, 14.92)]
        return ring or any(_seg_dist(x, y, lx, a, lx, b) <= 0.55 for lx, a, b in lines)
    if kind in ("airplay", "air"):
        edge = min(_seg_dist(x, y, *a, *b) for a, b in _poly_edges(DIAMOND)) <= 0.8
        return edge or (kind == "airplay" and _in_poly(x, y, DIAMOND_IN))
    if kind == "spotify":
        return ring or (math.hypot(x - 10, y - 10) <= 7.2 and x <= 10)
    raise ValueError(kind)


def glyph_lightest(kind, step=0.05):
    """Smallest gradient offset any painted point of the glyph reaches."""
    best = 9.0
    n = int(20 / step)
    for i in range(n + 1):
        for j in range(n + 1):
            x, y = i * step, j * step
            if _painted(kind, x, y):
                best = min(best, math.hypot(x - GLYPH_CENTRE[0], y - GLYPH_CENTRE[1]) / GLYPH_R)
    return best


GLYPHS = ["optical", "upnp", "roon", "airplay", "spotify", "air"]

# ------------------------------------------------------------------- tokens

LIGHT = {
    "text": "#1c1a17", "textDim": "#6e6a64", "textFaint": "#a29d95",
    "copperBright": "#9c6d20", "warningBright": "#b8862e",
    "divider": ("#1c1812", 0.09), "btnBorder": ("#1c1812", 0.10),
    "track": "#ece9e4", "accentFill": "#e2b865",
    "activeFill": ("#c39443", 0.10),
}
READOUT = [(0.0, "#dca136"), (1.0, "#f3cf7c")]       # :112
EYEBROW = [(0.0, "#97691f"), (1.0, "#cf9c45")]       # :103
SPHERE = [(0.0, "#fcecc0"), (0.38, "#f0a623"), (1.0, "#a8710b")]   # :99/:101

DARK = {"panel": "#121212", "text": "#f2f0ec", "textDim": "#9a9a9f", "textFaint": "#5c5c60",
        "copperBright": "#e3a06a"}

BLACK = hx("#0a0a0c")       # v3 dark desktop floor (:167-170): the worst case
NEAR_WHITE = hx("#f2f2f2")  # a bright wallpaper, for the dark reference
WHITE = (255.0, 255.0, 255.0)

GATE = {"text": 4.5, "large": 3.0, "ui": 3.0, "report": None}

# ----------------------------------------------------------------- surfaces

def panel(alpha, backdrop=BLACK):
    return over(WHITE, alpha, backdrop)


def control(alpha, style, k, backdrop=BLACK):
    p = panel(alpha, backdrop)
    a = 0.35 + 0.65 * alpha if style == "current" else k
    return over(WHITE, a, p)


def surface(name, alpha, style, k):
    if name == "panel":
        return panel(alpha)
    if name == "control":
        return control(alpha, style, k)
    if name == "active":
        return over(hx(LIGHT["activeFill"][0]), LIGHT["activeFill"][1], panel(alpha))
    if name == "overlay":
        return WHITE           # --popup-bg #ffffff, opaque (:75)
    if name == "track":
        return hx(LIGHT["track"])
    raise ValueError(name)

# ------------------------------------------------------------------- items
# (id, label, token key, surface, gate). Token keys resolve through colour_of().

ITEMS = [
    ("eyebrow", "Header eyebrow DEVIALET (gradient, lightest stop)", "eyebrowLightest", "panel", "text"),
    ("ampName", "Amp name", "text", "panel", "text"),
    ("ipLine", "IP / status line", "textFaint", "panel", "text"),
    ("caret", "Header caret", "textFaint", "panel", "ui"),
    ("gear", "Settings gear", "textFaint", "panel", "ui"),
    ("ampDot", "Header status dot (sphere, lightest = highlight)", "sphereLightest", "panel", "ui"),
    ("readout", "Readout -25.0 (gradient, lightest stop)", "readoutLightest", "panel", "large"),
    ("dB", "Readout unit dB", "textDim", "panel", "text"),
    ("footer", "Footer Connected", "textFaint", "panel", "text"),
    ("footerDot", "Footer dot (sphere, lightest)", "sphereLightest", "panel", "ui"),
    ("thumb", "Slider thumb (sphere, lightest) vs panel", "sphereLightest", "panel", "ui"),
    ("sphereRim", "Any sphere, rim `#a8710b` (alt rule, report)", "sphereRim", "panel", "report"),
    ("fillVsTrack", "Slider fill vs track", "accentFill", "track", "ui"),
    ("trackVsPanel", "Slider track vs panel", "track", "panel", "report"),
    ("divider", "Divider vs panel", "divider", "panel", "report"),
    ("chipText", "Chip text Optical 1", "textFaint", "control", "text"),
    ("stepText", "+/- stepper glyphs", "text", "control", "text"),
    ("btnLabel", "Mute / Power Off labels", "text", "control", "text"),
    ("mutedLabel", "Unmute label on active fill", "copperBright", "active", "text"),
    ("bootLabel", "Powering on... label", "warningBright", "control", "text"),
    ("srcEyebrow", "Source eyebrow SOURCE", "textFaint", "control", "text"),
    ("srcName", "Source name", "text", "control", "text"),
    ("srcCaret", "Source caret", "textFaint", "control", "ui"),
    ("srcGlyph", "Source row glyph (gold, lightest visible)", "glyphLightest", "control", "ui"),
    ("btnBorder", "Control border vs panel", "btnBorder", "controlEdge", "report"),
    ("ovAmpName", "Amp list: other amp name", "textDim", "overlay", "text"),
    ("ovAmpSel", "Amp list: connected amp name", "copperBright", "overlay", "text"),
    ("ovAmpSub", "Amp list: IP line", "textFaint", "overlay", "text"),
    ("ovTick", "List tick", "copperBright", "overlay", "ui"),
    ("ovDot", "Amp list: unconnected dot", "textFaint", "overlay", "ui"),
    ("ovSrc", "Source list: option", "textDim", "overlay", "text"),
    ("ovSrcSel", "Source list: selected", "copperBright", "overlay", "text"),
    ("ovGlyph", "Source list: glyph (gold, lightest visible)", "glyphLightest", "overlay", "ui"),
]

GLYPH_T = {g: glyph_lightest(g) for g in GLYPHS}
GLYPH_WORST = min(GLYPH_T, key=GLYPH_T.get)


def colour_of(key, bg, tokens=None):
    """Resolve a token key to an opaque colour as it appears over bg."""
    t = dict(LIGHT)
    if tokens:
        t.update(tokens)
    if key == "eyebrowLightest":
        return hx(t.get("eyebrowLightest", EYEBROW[-1][1]))
    if key == "readoutLightest":
        return hx(t.get("readoutLightest", READOUT[-1][1]))
    if key == "sphereRim":
        return hx(SPHERE[-1][1])
    if key == "sphereLightest":
        return hx(t.get("sphereLightest", SPHERE[0][1]))
    if key == "glyphLightest":
        if "glyphLightest" in t:
            return hx(t["glyphLightest"])
        return grad_at(GLYPH_GOLD, GLYPH_T[GLYPH_WORST])
    v = t[key]
    if isinstance(v, tuple):
        return over(hx(v[0]), v[1], bg)
    return hx(v)


def evaluate(item, alpha, style, k, tokens=None):
    iid, _label, key, surf, gate = item
    if surf == "controlEdge":
        bg = panel(alpha)
        fg = over(hx(LIGHT["btnBorder"][0]), LIGHT["btnBorder"][1], control(alpha, style, k))
    else:
        bg = surface(surf, alpha, style, k)
        fg = colour_of(key, bg, tokens)
    r = ratio(fg, bg)
    polarity_ok = lum(fg) < lum(bg)       # light theme: marks are darker than their background
    return r, polarity_ok, fg, bg


def mark(r, gate, polarity_ok):
    g = GATE[gate]
    if not polarity_ok:
        return f"{r:.2f} **inv**"
    if g is None:
        return f"{r:.2f}"
    return f"{r:.2f} {'ok' if r >= g else '**FAIL**'}"

# ---------------------------------------------------------- polarity floor

def alpha_cross(fg):
    """Lowest panel alpha (over BLACK) at which the panel is lighter than fg."""
    lo, hi = 0.0, 1.0
    if lum(panel(1.0)) <= lum(fg):
        return None     # lighter than opaque white: never below the panel
    for _ in range(40):
        mid = (lo + hi) / 2
        if lum(panel(mid)) > lum(fg):
            hi = mid
        else:
            lo = mid
    return hi

# ---------------------------------------------------------- token proposals

def darken_until(fg, bg, gate_ratio):
    """Darken fg in OKLCH lightness only (same hue/chroma, gamut-clipped)."""
    L, C, H = to_oklch(fg)
    c = fg
    while ratio(c, bg) < gate_ratio and L > 0:
        L -= 0.002
        c = from_oklch(L, C, H)
    return c


TOKEN_OF = {  # which proposable token each item's colour comes from
    "eyebrowLightest": "eyebrowLightest", "readoutLightest": "readoutLightest",
    "sphereLightest": "sphereLightest", "glyphLightest": "glyphLightest",
    "text": "text", "textDim": "textDim", "textFaint": "textFaint",
    "copperBright": "copperBright", "warningBright": "warningBright", "accentFill": "accentFill",
}


def proposals(lmin, style, k):
    """Per token: the darkest background it appears on at lmin decides."""
    out = {}
    for item in ITEMS:
        iid, _l, key, surf, gate = item
        if key not in TOKEN_OF or GATE[gate] is None:
            continue
        r, pol, fg, bg = evaluate(item, lmin, style, k)
        tok = TOKEN_OF[key]
        rec = out.setdefault(tok, {"orig": fg, "need": [], "unusable": []})
        if not pol:
            rec["unusable"].append(iid)
            continue
        if r < GATE[gate]:
            rec["need"].append((iid, bg, GATE[gate]))
    result = {}
    for tok, rec in out.items():
        if rec["unusable"]:
            result[tok] = ("unusable", rec["unusable"])
        elif rec["need"]:
            c = rec["orig"]
            for _iid, bg, g in rec["need"]:
                c = darken_until(c, bg, g)
            # re-check every use of the token with the proposed colour
            worst = min(ratio(c, surface(s, lmin, style, k)) / GATE[g]
                        for (_i, _l, key, s, g) in ITEMS
                        if TOKEN_OF.get(key) == tok and GATE[g] and s != "controlEdge")
            if worst < 1.0:
                result[tok] = ("impossible", worst)
            else:
                result[tok] = ("proposed", to_hex(c), worst)
        else:
            result[tok] = ("passes", None)
    return result

# ------------------------------------------------------------------ self-test

def selftest():
    # Phase 17.19.0 measurement: panel alpha 0.5 over an effective backdrop
    # of 115 read 185; the glass face (0.35 + 0.65 * 0.5 = 0.675) read 232.
    p = over(WHITE, 0.5, (115.0,) * 3)
    f = over(WHITE, 0.35 + 0.65 * 0.5, p)
    ok = round(p[0]) == 185 and round(f[0]) == 232
    # sanity: WCAG black on white is 21:1
    ok = ok and abs(ratio((0, 0, 0), WHITE) - 21.0) < 1e-9
    # OKLCH round trip
    rt = from_oklch(*to_oklch(hx("#9c6d20")))
    ok = ok and max(abs(a - b) for a, b in zip(rt, hx("#9c6d20"))) < 0.5
    print(f"selftest: panel {p[0]:.2f} (185), face {f[0]:.2f} (232), round-trip {to_hex(rt)} -> {'PASS' if ok else 'FAIL'}")
    return ok

# ------------------------------------------------------------------- report

LMINS = [0.40, 0.50, 0.60, 0.65, 0.70, 0.80, 0.90, 1.00]


def build(k):
    L = []
    w = L.append
    w("# Light-glass spike: contrast tables")
    w("")
    w("Generated by `python3 tools/spike-light-glass/contrast.py` - do not edit by hand.")
    w("Backdrop for every worst case: flat `#0a0a0c` (v3's dark desktop floor), no blur")
    w("needed (blur of a flat colour is the same colour). WCAG 2.x ratios; gates: text 4.5,")
    w("large text 3.0, state-carrying non-text marks 3.0; borders/dividers reported only.")
    w("`inv` = the mark is lighter than its background (polarity flipped) - unusable at that alpha.")
    w(f"Restructured controls use k = {k} (white at a fixed alpha over the panel, the dark theme's controlAlphaK model).")
    w("")
    w("Gradient marks are gated on their lightest visible colour:")
    w(f"- readout `{READOUT[-1][1]}` (right end of `#dca136 -> #f3cf7c`), eyebrow `{EYEBROW[-1][1]}`;")
    w(f"- spheres (status dots, thumb) `{SPHERE[0][1]}`, the highlight at the gradient centre;")
    lt = ", ".join(f"{g} {GLYPH_T[g]:.3f}" for g in GLYPHS)
    w(f"- source glyphs: lightest painted gradient offset per glyph ({lt}); worst = {GLYPH_WORST},"
      f" colour `{to_hex(grad_at(GLYPH_GOLD, GLYPH_T[GLYPH_WORST]))}`.")
    w("")

    fails = [it[1] for it in ITEMS if GATE[it[4]] and (lambda r: not r[1] or r[0] < GATE[it[4]])(evaluate(it, 1.0, "current", k))]
    w("**Fails even fully opaque (a token/design issue, not a transparency one):** " + "; ".join(fails) + ".")
    w("")
    cols = ["opaque", "today 20 %"] + [f"Lmin {x:.2f}" for x in LMINS]

    def row(item, style):
        cells = []
        r, pol, _f, _b = evaluate(item, 1.0, style, k)
        cells.append(mark(r, item[4], pol))
        # "today": 17.19.0 glass controls at the owner's 20 % over black
        r, pol, _f, _b = evaluate(item, 0.20, "current", k)
        cells.append(mark(r, item[4], pol))
        for a in LMINS:
            r, pol, _f, _b = evaluate(item, a, style, k)
            cells.append(mark(r, item[4], pol))
        return cells

    for title, surfs in (("Panel, overlay and slider marks (control style does not matter)",
                          ("panel", "overlay", "track")),):
        w(f"## {title}")
        w("")
        w("| item | gate | " + " | ".join(cols) + " |")
        w("|---|---|" + "---|" * len(cols))
        for it in ITEMS:
            if it[3] in surfs:
                w(f"| {it[1]} | {it[4]} | " + " | ".join(row(it, "current")) + " |")
        w("")
    for style in ("current", "restructured"):
        label = "glass 0.35 + 0.65 alpha" if style == "current" else f"fixed k = {k}"
        w(f"## Marks on controls - {style} ({label})")
        w("")
        w("`today 20 %` is always the 17.19.0 glass controls, for reference.")
        w("")
        w("| item | gate | " + " | ".join(cols) + " |")
        w("|---|---|" + "---|" * len(cols))
        for it in ITEMS:
            if it[3] in ("control", "active", "controlEdge"):
                w(f"| {it[1]} | {it[4]} | " + " | ".join(row(it, style)) + " |")
        w("")

    w("## Polarity floor: lowest light alpha at which the panel stays lighter than each mark")
    w("")
    w("Over `#0a0a0c`. Below this alpha the mark is lighter than the panel and the")
    w("dark-on-light design inverts; no token change fixes that without flipping the design.")
    w("")
    w("| mark | colour | alpha floor |")
    w("|---|---|---|")
    marks = [("text", LIGHT["text"]), ("textDim", LIGHT["textDim"]), ("textFaint", LIGHT["textFaint"]),
             ("copperBright", LIGHT["copperBright"]), ("warningBright", LIGHT["warningBright"]),
             ("accentFill", LIGHT["accentFill"]), ("track", LIGHT["track"]),
             ("readout lightest", READOUT[-1][1]), ("readout darkest", READOUT[0][1]),
             ("eyebrow lightest", EYEBROW[-1][1]),
             ("sphere highlight", SPHERE[0][1]), ("sphere mid stop", SPHERE[1][1]),
             ("glyph lightest visible", to_hex(grad_at(GLYPH_GOLD, GLYPH_T[GLYPH_WORST])))]
    floors = []
    for name, c in marks:
        a = alpha_cross(hx(c))
        floors.append((a or 0.0, name))
        w(f"| {name} | `{c}` | {'never below (lighter than white)' if a is None else f'{a:.3f}'} |")
    top = max(floors)
    w("")
    w(f"Lowest alpha where the panel is lighter than **every** mark: **{top[0]:.3f}** (set by {top[1]}).")
    no_hi = [f for f in floors if f[1] not in ("sphere highlight", "glyph lightest visible")]
    top2 = max(no_hi)
    w(f"Excluding the gold gradient centre `#fcecc0` (sphere highlight, glyph centre): **{top2[0]:.3f}** (set by {top2[1]}).")
    txt = [f for f in floors if f[1] in ("text", "textDim", "textFaint", "copperBright", "warningBright")]
    top3 = max(txt)
    w(f"Text tokens only (text, textDim, textFaint, copperBright, warningBright): **{top3[0]:.3f}** (set by {top3[1]}).")
    w("")

    for style in ("current", "restructured"):
        w(f"## Worst-case token proposals - controls {style}")
        w("")
        w("Darkened in OKLCH lightness only (hue and chroma kept, gamut-clipped) until every")
        w("use of the token passes its gate at that Lmin; `unusable` = polarity already flipped")
        w("(listed items), no proposal. Worst margin = lowest ratio/gate over the token's uses.")
        w("")
        toks = ["text", "textDim", "textFaint", "copperBright", "warningBright", "accentFill",
                "readoutLightest", "eyebrowLightest", "sphereLightest", "glyphLightest"]
        w("| token | " + " | ".join(f"Lmin {x:.2f}" for x in LMINS) + " |")
        w("|---|" + "---|" * len(LMINS))
        per = {a: proposals(a, style, k) for a in LMINS}
        for t in toks:
            cells = []
            for a in LMINS:
                p = per[a].get(t)
                if p is None:
                    cells.append("-")
                elif p[0] == "passes":
                    cells.append("passes")
                elif p[0] == "impossible":
                    cells.append(f"impossible (black reaches x{p[1]:.2f})")
                elif p[0] == "unusable":
                    cells.append("unusable (" + ", ".join(p[1]) + ")")
                else:
                    cells.append(f"`{p[1]}` (x{p[2]:.2f})")
            w(f"| {t} | " + " | ".join(cells) + " |")
        w("")

    w("## Checked against captures")
    w("")
    w("`tools/spike-light-glass/capture.sh` renders the mockup headless at 2x on the flat")
    w("`#0a0a0c` wallpaper and compares captured pixels with this file's arithmetic")
    w("(amp name, IP line, dB, footer, chip text, SOURCE, button label, readout first stop,")
    w("optical glyph core) - tolerance +-0.1. Files in `captures/`:")
    w("")
    capdir = os.path.join(HERE, "captures")
    for f in sorted(os.listdir(capdir)) if os.path.isdir(capdir) else []:
        if f.endswith(".png"):
            w(f"- `captures/{f}`")
    chk = os.path.join(capdir, "check.txt")
    if os.path.exists(chk):
        last = open(chk).read().strip().splitlines()[-1]
        w("")
        w(f"Last check (`captures/check.txt`): {last}")
    w("")
    w("## Dark theme reference (not gated; v3 dark tokens)")
    w("")
    w("The mirror case: a dark translucent panel over a bright wallpaper.")
    w("")
    w("| mark | opaque | 50 % over black | 50 % over `#f2f2f2` | 30 % over `#f2f2f2` |")
    w("|---|---|---|---|---|")
    for name in ("text", "textDim", "textFaint", "copperBright"):
        fg = hx(DARK[name])
        cells = []
        for a, bd in ((1.0, BLACK), (0.5, BLACK), (0.5, NEAR_WHITE), (0.3, NEAR_WHITE)):
            bg = over(hx(DARK["panel"]), a, bd)
            r = ratio(fg, bg)
            cells.append(f"{r:.2f}" + ("" if lum(fg) > lum(bg) else " inv"))
        w(f"| {name} `{DARK[name]}` | " + " | ".join(cells) + " |")
    w("")
    return "\n".join(L) + "\n"


def shift_L(hex_c, dL):
    L, C, H = to_oklch(hx(hex_c))
    return to_hex(from_oklch(max(0.0, L - dL), C, H))


def worst_tokens(k):
    """Per Lmin: the darker proposal of the two control styles, as CSS values
    for the mockup. Tokens that pass keep v3's value; unusable/impossible
    tokens also keep v3's value (the mockup then shows them failing, honestly).
    Gradients: both stops move by the lightest stop's OKLCH lightness change,
    so the dark-at-rest -> lighter-at-lit-end sweep keeps its direction."""
    base = {"text-dim": LIGHT["textDim"], "text-faint": LIGHT["textFaint"],
            "copper-bright": LIGHT["copperBright"], "warning-bright": LIGHT["warningBright"]}
    grads = {"eyebrow": EYEBROW, "readout": READOUT}
    out = {}
    for a in LMINS:
        props = [proposals(a, st, k) for st in ("current", "restructured")]
        row = {}
        for css, tok in (("text-dim", "textDim"), ("text-faint", "textFaint"),
                         ("copper-bright", "copperBright"), ("warning-bright", "warningBright")):
            cands = [p[tok][1] for p in props if p.get(tok, ("",))[0] == "proposed"]
            row[css] = min(cands, key=lambda c: lum(hx(c))) if cands else base[css]
        for name, stops in grads.items():
            tok = name + "Lightest"
            cands = [p[tok][1] for p in props if p.get(tok, ("",))[0] == "proposed"]
            if cands:
                new1 = min(cands, key=lambda c: lum(hx(c)))
                dL = to_oklch(hx(stops[-1][1]))[0] - to_oklch(hx(new1))[0]
                row[name + "-0"], row[name + "-1"] = shift_L(stops[0][1], dL), new1
            else:
                row[name + "-0"], row[name + "-1"] = stops[0][1], stops[-1][1]
        out[f"{a:.2f}"] = row
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--k", type=float, default=0.10, help="restructured control alpha")
    ap.add_argument("--out", default=os.path.join(HERE, "contrast-tables.md"))
    ap.add_argument("--point", nargs=3, metavar=("ALPHA", "STYLE", "ITEM"),
                    help="print one item's ratio (used by capture.sh)")
    args = ap.parse_args()
    if not selftest():
        sys.exit(1)
    if args.selftest:
        return
    if args.point:
        a, style, iid = float(args.point[0]), args.point[1], args.point[2]
        it = next(i for i in ITEMS if i[0] == iid)
        r, pol, fg, bg = evaluate(it, a, style, args.k)
        print(f"{iid} {r:.3f} fg {to_hex(fg)} bg {to_hex(bg)}")
        return
    with open(args.out, "w") as f:
        f.write(build(args.k))
    print("wrote", args.out)
    import json
    js = os.path.join(HERE, "worst-tokens.js")
    with open(js, "w") as f:
        f.write("// Generated by contrast.py - worst-case light tokens per Lmin (see contrast-tables.md).\n")
        f.write("const WORST = " + json.dumps(worst_tokens(args.k), indent=1) + ";\n")
    print("wrote", js)


if __name__ == "__main__":
    main()
