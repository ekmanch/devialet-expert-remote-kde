# Spike — gradient rendering for the light theme (`spike/gradient-rendering`)

Unnumbered, throwaway-or-merge (TODO.md "Spike — Gradient rendering for the
light theme"). Standalone; nothing under `plasmoid/` is touched. Answers the
four rendering questions the light theme (Phase 17.19.0-17.23.0) depends on,
with 2× captures for the owner to judge.

## Run

```
cd tools/spike-gradient-rendering
QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 /usr/lib/qt6/bin/qml driver.qml
python3 zoom.py captures/sheet.png 3      # composited 3x row crops -> captures/zoom-*.png
```

A frameless 640×360 window appears for ~1.2 s and grabs itself at the
screen's device pixel ratio (2 here) into `captures/sheet.png` (1280×720).
**Do not use `QT_QPA_PLATFORM=offscreen`**: it selects the software
scenegraph (`GraphicsInfo.api` = 1) and every `MultiEffect` renders as
nothing - that was sheet 1's blank rows. Wayland gives OpenGL (api 3).

## Files

- `GradientMask.qml` — paints a 3-stop linear or radial gradient through the
  alpha of any item (`maskSource`: a Text, a Shape, or an `Image` directly),
  with an optional drop shadow / glow. Two MultiEffects: mask, then shadow.
- `GradientText.qml` — gradient text + optional glow, built on GradientMask.
- `GoldSphere.qml` — the gold sphere (Shape `RadialGradient`, CurveRenderer)
  + MultiEffect drop shadow + optional halo ring.
- `GlyphShape.qml` — the mockup's optical and airplay glyphs as Shapes (flat
  colour for dark, alpha source for light).
- `speaker-muted.svg`, `speaker-waves.svg` — the mockup's speaker paths in
  black, used as `Image` mask sources.
- `driver.qml`, `zoom.py`, `captures/` — the sheet and its crops.

## Findings (2026-09-26, Qt 6.11.2, OpenGL via RHI, DPR 2)

1. **Mask + glow needs two stages.** One `MultiEffect` with `maskEnabled`
   *and* `shadowEnabled` misaligns the mask: the shadow's auto padding
   enlarges the effect and the mask texture is stretched over the padded
   area, so the gradient rectangle shows through around a shrunken glyph
   (sheet 1, `captures/sheet-offscreen.png` is the software one; the first
   Wayland sheet was overwritten, the effect is reproducible by setting
   `twoStage: false`). Mask first, then a second `MultiEffect` shadowing the
   masked result, is correct (sheet 2 R1/R4/R5). `GradientMask.twoStage`
   defaults to true; the single path is kept only as the record.
2. **Gradient text is clean at every size used**: 26 px readout, 15/13 px
   OSD/tooltip values, 11 px DemiBold headings with 1.4 letter-spacing, 11 px
   bold "Light", 12 px bold "Muted" (R1/R2). Glyph edges match the plain
   Label next to them. Glow strengths offered for the readout: `glowBlur`
   0.35/32, 0.6/32, 0.9/32, 0.6/64 (`shadowBlur`/`blurMax`); the mockup's
   `text-shadow: 0 0 14px rgba(199,154,46,.35)` sits between the last two.
   Owner picks.
3. **Sphere**: Shape `RadialGradient` (centre 32 %/28 %, radius = farthest
   corner, stops #fcecc0 0 / #f0a623 0.38 / #a8710b 1) with `CurveRenderer`
   + MultiEffect shadow reads as a sphere at 14 (with the 3 px halo), 12,
   10, 7 and 6 px (R3, `captures/detail-r3-spheres.png`).
4. **Gradient-"stroked" glyphs**: masking the radial fill with the stroked
   Shape gives a gradient stroke (Shapes has no stroke gradient); ring and
   diamond at 20 and 17 px, with drop shadow (R4,
   `captures/detail-r4-glyphs.png`). The shadow at `0.3/16`, opacity 0.35,
   offset 2 is slightly heavier than the mockup's `drop-shadow(0 2px 2.5px
   rgba(160,110,10,.35))`; tune in 17.21.0, not a feasibility issue.
5. **Speaker SVG as `maskSource`**: a plain `Image { sourceSize: 17×17;
   visible: false }` works directly (no `layer.enabled` needed) and is
   rasterised at DPR (edge profile 255→107→0, one blended device pixel);
   the layer-enabled variant is identical (R5,
   `captures/detail-r5-speakers.png`).
6. **Qt5Compat.GraphicalEffects: not needed.** Everything above uses
   `QtQuick.Effects` and `QtQuick.Shapes`, both already dependencies of the
   plasmoid. No PKGBUILD change.
7. Pitfall for anyone measuring: `grabToImage` returns RGBA with junk RGB in
   near-transparent pixels; composite on white before zooming or the shadows
   look like red/yellow rims (sheet 1's "rim" was this).

## What lands in the arc (only after the owner judges the captures)

`GradientMask.qml`, `GradientText.qml`, `GoldSphere.qml` move to
`plasmoid/contents/ui/` in 17.19.0 (sphere thumb), 17.20.0 (readout +
wordmark) and 17.21.0 (glyphs/dots/ticks); `GlyphShape.qml` is the seed of
17.7.0's `SourceGlyph.qml` (flat colour first). The speaker SVGs are 17.2.0's
bundled icons (black → `Kirigami.Icon { isMask: true }` for dark, `Image`
mask for light). Merge and number per TODO.md's spike entry; discard the
branch if the owner rejects the look.
