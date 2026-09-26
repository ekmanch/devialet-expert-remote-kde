#!/usr/bin/env python3
"""Crop the driver sheet's row bands (fixed logical y ranges) and upscale
them nearest-neighbour so 2x device pixels can be judged by eye."""
import sys
from PIL import Image

raw = Image.open(sys.argv[1] if len(sys.argv) > 1 else "captures/sheet.png").convert("RGBA")
# composite on white first: the grab carries near-transparent junk-RGB pixels
sheet = Image.alpha_composite(Image.new("RGBA", raw.size, (255, 255, 255, 255)), raw).convert("RGB")
dpr = sheet.width / 640
rows = {"r1-readout": (14, 78), "r2-small": (92, 128), "r3-spheres": (150, 190),
        "r4-glyphs": (208, 250), "r5-speakers": (268, 306)}
zoom = int(sys.argv[2]) if len(sys.argv) > 2 else 3
for name, (y0, y1) in rows.items():
    band = sheet.crop((0, int(y0 * dpr), sheet.width, int(y1 * dpr)))
    band.resize((band.width * zoom, band.height * zoom), Image.NEAREST).save(f"captures/zoom-{name}.png")
    print(name, band.size, "->", f"captures/zoom-{name}.png")
print("sheet", sheet.size, "dpr", dpr)
