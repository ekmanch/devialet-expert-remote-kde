#!/usr/bin/env bash
# Spike light-glass: headless-Firefox captures of flyout-light-glass.html.
#
#   tools/spike-light-glass/capture.sh [SCRATCH_DIR]
#
# 1. Black-wallpaper measurement set (kept in captures/, the evidence behind
#    contrast-tables.md): light at the worst case (map B, p=0 -> alpha = Lmin
#    0.65) for glass/fixed-k controls x v3/worst-case tokens, plus opaque
#    light; rendered at 2x (CSS zoom - headless Firefox ignores
#    devPixelsPerPx). A probe capture locates each measured element.
# 2. The +-0.1 check: WCAG ratio from the captured pixels vs contrast.py's
#    arithmetic for the same token/surface (imported, not re-implemented).
# 3. Dark identity check: spike dark (map B identity, p=50) vs the v3 mockup
#    dark at transparency 50, both on v3's plain wallpaper with blur off
#    (the spike blurs with saturate(110%), v3 with 150%).
# 4. Eye-check shots on the colourful and light wallpapers -> SCRATCH_DIR
#    only. Headless Firefox does not render backdrop-filter (checked on
#    Firefox 156), so these show the flyout unblurred; judge blur live.
set -u
export PYTHONDONTWRITEBYTECODE=1   # capture.sh imports contrast.py; keep the spike dir clean
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
SCRATCH=${1:-${TMPDIR:-/tmp}/spike-light-glass}
CAP="$HERE/captures"
mkdir -p "$CAP" "$SCRATCH"
PROFILE=$(mktemp -d "$SCRATCH/profile.XXXX")
trap 'rm -rf "$PROFILE"' EXIT
PAGE="file://$HERE/flyout-light-glass.html"
# page console -> stdout, so a script error in the mockup fails the capture
echo 'user_pref("devtools.console.stdout.content", true);' > "$PROFILE/user.js"

shot() { # out.png "query" [w h]
    local log
    log=$(timeout 90 firefox --headless --no-remote --profile "$PROFILE" --screenshot "$1" \
        --window-size="${3:-1520},${4:-1440}" "$PAGE?$2" 2>&1)
    [ -s "$1" ] || { echo "capture failed: $1" >&2; exit 1; }
    if grep -q "JavaScript error: file://.*flyout-light-glass.html" <<<"$log"; then
        echo "page script error for ?$2:" >&2; grep "flyout-light-glass.html" <<<"$log" >&2; exit 1
    fi
}

W="mode=light&wall=black&map=B&p=0&lmin=0.65&capture=1&zoom=2"
echo "== black-wallpaper measurement set -> $CAP"
shot "$CAP/probe.png"                    "$W&controls=current&text=current&probe=1"
shot "$CAP/lmin065-glass-v3.png"         "$W&controls=current&text=current"
shot "$CAP/lmin065-glass-worst.png"      "$W&controls=current&text=worst"
shot "$CAP/lmin065-fixedk-v3.png"        "$W&controls=restructured&k=0.1&text=current"
shot "$CAP/lmin065-fixedk-worst.png"     "$W&controls=restructured&k=0.1&text=worst"
shot "$CAP/opaque-glass-v3.png"          "mode=light&wall=black&map=B&p=100&lmin=0.65&capture=1&zoom=2&controls=current&text=current"

echo "== +-0.1 check"
python3 - "$HERE" "$CAP" <<'PY'
import json, re, sys
sys.path.insert(0, sys.argv[1])
import contrast as C
from PIL import Image
here, cap = sys.argv[1], sys.argv[2]
WORST = json.loads(re.search(r"=\s*(\{.*\})\s*;", open(f"{here}/worst-tokens.js").read(), re.S).group(1))

probe = Image.open(f"{cap}/probe.png").convert("RGB"); pp = probe.load()
boxes = {}
for y in range(probe.size[1]):
    for x in range(probe.size[0]):
        r, g, b = pp[x, y]
        if r == 255 and g == 0 and b and b % 10 == 0:
            x0, y0, x1, y1 = boxes.get(b, (x, y, x, y))
            boxes[b] = (min(x0, x), min(y0, y), max(x1, x), max(y1, y))
BOX = dict(zip(["ampName", "ipLine", "readout", "dB", "footer", "chipText", "srcEyebrow", "btnLabel", "srcGlyph"],
               [boxes[10 * (i + 1)] for i in range(9)]))

def pixels(im, box):
    x0, y0, x1, y1 = box; p = im.load()
    return [p[x, y] for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]

def mode(ps):
    from collections import Counter
    return Counter(ps).most_common(1)[0][0]

def darkest(ps, grey_only=False):
    if grey_only:
        ps = [q for q in ps if max(q) - min(q) < 30]
    return min(ps, key=sum)

CASES = [  # file, alpha, style, text set
    ("lmin065-glass-v3.png", 0.65, "current", "current"),
    ("lmin065-glass-worst.png", 0.65, "current", "worst"),
    ("lmin065-fixedk-v3.png", 0.65, "restructured", "current"),
    ("lmin065-fixedk-worst.png", 0.65, "restructured", "worst"),
    ("opaque-glass-v3.png", 1.0, "current", "current"),
]
# item -> (token css name or None, surface)
ITEMS = {"ampName": ("text", "panel"), "ipLine": ("text-faint", "panel"), "dB": ("text-dim", "panel"),
         "footer": ("text-faint", "panel"), "chipText": ("text-faint", "control"),
         "srcEyebrow": ("text-faint", "control"), "btnLabel": ("text", "control")}
BASE = {"text": C.LIGHT["text"], "text-dim": C.LIGHT["textDim"], "text-faint": C.LIGHT["textFaint"]}
worst = 0.0
lines = []
for fname, a, style, tset in CASES:
    im = Image.open(f"{cap}/{fname}").convert("RGB")
    for item, (tok, surf) in ITEMS.items():
        ps = pixels(im, BOX[item])
        bg_m, fg_m = mode(ps), darkest(ps, grey_only=(item == "footer"))
        meas = C.ratio(fg_m, bg_m)
        fg_hex = BASE[tok] if tset == "current" or tok == "text" else WORST["0.65"][tok]
        bg_c = C.surface(surf, a, style, 0.1)
        calc = C.ratio(C.hx(fg_hex), bg_c)
        d = meas - calc; worst = max(worst, abs(d))
        lines.append(f"{fname:28s} {item:10s} measured {meas:5.2f} (fg {C.to_hex(fg_m)} bg {C.to_hex(bg_m)})"
                     f"  computed {calc:5.2f} (fg {fg_hex} bg {C.to_hex(bg_c)})  diff {d:+.3f}")
    # readout: darkest core = first gradient stop, over the panel
    ps = pixels(im, BOX["readout"]); fg_m = darkest(ps)
    stop0 = C.READOUT[0][1] if tset == "current" else WORST["0.65"]["readout-0"]
    bg_c = C.panel(a); meas = C.ratio(fg_m, bg_c); calc = C.ratio(C.hx(stop0), bg_c)
    d = meas - calc; worst = max(worst, abs(d))
    lines.append(f"{fname:28s} {'readout0':10s} measured {meas:5.2f} (fg {C.to_hex(fg_m)} vs panel)          "
                 f"  computed {calc:5.2f} (fg {stop0} bg {C.to_hex(bg_c)})  diff {d:+.3f}")
    # optical glyph: ring core at the point nearest the gradient centre
    # Locate the ring from its own gold pixels (the SVG's reported box is
    # offset by its drop-shadow filter): the ring's outer edge spans glyph
    # units 2.0..18.0, so its bounding box gives origin and scale.
    bx0, by0, bx1, by1 = BOX["srcGlyph"]; q = im.load()
    gold = [(x, y) for y in range(by0 - 12, by1 + 12) for x in range(bx0 - 12, bx1 + 12)
            if max(q[x, y]) - min(q[x, y]) > 60]
    gx0, gy0 = min(g[0] for g in gold), min(g[1] for g in gold)
    gx1, gy1 = max(g[0] for g in gold), max(g[1] for g in gold)
    u = (gx1 - gx0 + 1) / 16.0; ox, oy = gx0 - 2 * u, gy0 - 2 * u
    gx, gy = 10 - 7.2 * 3.6 / 5.685, 10 - 7.2 * 4.4 / 5.685   # ring centreline nearest the gradient centre
    cx, cy = ox + gx * u, oy + gy * u
    # stroke core = the most saturated pixel within 1.5 px of that point
    near = [(x, y) for x in range(int(cx) - 2, int(cx) + 3) for y in range(int(cy) - 2, int(cy) + 3)
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= 1.5 ** 2]
    fg_m = max((q[x, y] for x, y in near), key=lambda c: max(c) - min(c))
    off = ((gx - 6.4) ** 2 + (gy - 5.6) ** 2) ** 0.5 / 15.5
    bg_c = C.surface("control", a, style, 0.1)
    meas, calc = C.ratio(fg_m, bg_c), C.ratio(C.grad_at(C.GLYPH_GOLD, off), bg_c)
    d = meas - calc; worst = max(worst, abs(d))
    lines.append(f"{fname:28s} {'glyph':10s} measured {meas:5.2f} (fg {C.to_hex(fg_m)} at offset {off:.3f})   "
                 f"  computed {calc:5.2f} (fg {C.to_hex(C.grad_at(C.GLYPH_GOLD, off))})  diff {d:+.3f}")
out = "\n".join(lines) + f"\nmax |diff| = {worst:.3f} -> {'PASS' if worst <= 0.1 else 'FAIL'} (tolerance 0.1)\n"
print(out)
open(f"{cap}/check.txt", "w").write(out)
sys.exit(0 if worst <= 0.1 else 2)
PY
check=$?

echo "== dark identity vs v3 (plain wallpaper, blur off)"
V3="$REPO/design/mockups/flyout/Devialet Expert Remote Flyout Design Mockup v3.html"
V3S="$SCRATCH/v3-dark50.html"
sed 's#</body>#<style>.preview-switcher,.mockup-tag{display:none}*{animation:none!important;transition:none!important}</style><script>setMode("dark");setAlpha(50);setBlur("off");</script></body>#' "$V3" > "$V3S"
cp "$HERE/worst-tokens.js" "$SCRATCH/" 2>/dev/null
timeout 90 firefox --headless --no-remote --profile "$PROFILE" --screenshot "$SCRATCH/v3-dark50.png" --window-size=760,720 "file://$V3S" >/dev/null 2>&1
shot "$SCRATCH/spike-dark-B50.png" "mode=dark&map=B&p=50&bdark=identity&blur=off&wall=plain&capture=1" 760 720
shot "$SCRATCH/spike-dark-A50.png" "mode=dark&map=A&pd=50&blur=off&wall=plain&capture=1" 760 720
python3 - "$SCRATCH" <<'PY'
import sys
from PIL import Image, ImageChops
s = sys.argv[1]
ref = Image.open(f"{s}/v3-dark50.png").convert("RGB")
rc = 0
for n in ("spike-dark-B50", "spike-dark-A50"):
    d = ImageChops.difference(ref, Image.open(f"{s}/{n}.png").convert("RGB"))
    bbox = d.getbbox()
    print(f"{n}: {'pixel-identical to v3 dark 50' if bbox is None else f'DIFFERS in {bbox}'}")
    rc |= bbox is not None
sys.exit(rc)
PY
ident=$?

echo "== every URL parameter changes the render (one-parameter pairs)"
PB="mode=light&wall=colour&map=B&p=40&lmin=0.65&controls=current&k=0.1&text=current&blur=off&capture=1"
params_fail=0
# "extra-base|varied": the varied parameter is compared against the base
# plus extra-base, so dark-only parameters are tested on a dark base.
for pair in "|mode=dark" "|wall=light" "|map=A&pl=90" "|p=80" "|lmin=0.80" "|controls=restructured" \
            "controls=restructured|k=0.3" "|text=worst" "|mute=1" "|list=source" "|list=amp" \
            "mode=dark&map=A|pd=10" "mode=dark|bdark=floor" "|capture=0"; do
    extra=${pair%%|*}; var=${pair#*|}
    shot "$SCRATCH/par-base.png" "$PB&$extra" 760 720
    shot "$SCRATCH/par-var.png" "$PB&$extra&$var" 760 720
    pair="$var${extra:+ (on base +$extra)}"
    if cmp -s "$SCRATCH/par-base.png" "$SCRATCH/par-var.png"; then echo "  NO CHANGE: $pair"; params_fail=1
    else echo "  changes:   $pair"; fi
done
echo "  (blur, br: not visible headless - no backdrop-filter; zoom, probe: used above)"

echo "== eye-check shots -> $SCRATCH (unblurred: headless has no backdrop-filter)"
for wall in colour light; do
  for ctl in current restructured; do
    for txt in current worst; do
      shot "$SCRATCH/eye-$wall-lmin065-$ctl-$txt.png" "mode=light&wall=$wall&map=B&p=0&lmin=0.65&controls=$ctl&text=$txt&capture=1" 760 720
    done
  done
  shot "$SCRATCH/eye-$wall-dark50.png" "mode=dark&wall=$wall&map=B&p=50&capture=1" 760 720
  shot "$SCRATCH/eye-$wall-today20.png" "mode=light&wall=$wall&map=A&pl=20&lmin=0.40&controls=current&capture=1" 760 720
done
echo "check exit $check, identity exit $ident, params exit $params_fail"
exit $(( check | ident | params_fail ))
