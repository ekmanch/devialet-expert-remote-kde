// Phase 17.11.0 - the colour-token TYPE for the widget's palettes.
//
// Every colour the flyout, OSD toast, hover tooltip and ConfigDialog page
// paint comes from one of these tokens; DarkPalette.qml (and, from Phase
// 17.19.0, LightPalette.qml) are instances that only assign values. Each
// token is `required`, so a palette that forgets one fails at creation
// with a named error instead of silently painting black.
//
// Consumers take the palette as a typed property named `colors` (e.g.
// `required property ColorPalette colors` in the flyout's children,
// `readonly property ColorPalette colors: DarkPalette {}` where nothing
// forwards one yet), so qmllint can check token names against this type.
// Not named Palette/palette: QtQuick already exports a `Palette` type and
// every Item has a built-in `palette` property.
//
// Theme.qml keeps fonts, sizes, radii and the volume icon map - nothing
// that changes between palettes.

import QtQuick

QtObject {
    id: cp

    // True for LightPalette (17.19.0). Branch on this, not on colour
    // values, where the two themes need different mechanisms.
    required property bool isLight

    // ---- Surfaces and controls ----
    required property color surface
    required property color surface2
    required property color surface3
    required property color divider

    // ---- Accent ----
    required property color copper
    required property color copperBright
    required property color copperDim

    // ---- Text ----
    required property color text
    required property color textDim
    required property color textFaint

    // ---- Status ----
    required property color danger
    required property color dangerBright
    required property color success
    required property color successBright
    required property color warning
    required property color warningBright

    // ---- Flyout panel tint (opaque; alpha applied via TransparencySettings) ----
    required property color panelTintTop
    required property color panelTintBottom

    // ---- OSD toast + hover tooltip background (alpha baked in) ----
    required property color osdGradientTop
    required property color osdGradientBottom

    // ---- Overlay cards (amp list, source list) ----
    required property color overlayGradientTop
    required property color overlayGradientBottom
    required property color overlayBorder
    required property color overlayShadow

    // ---- Phase 17.19.0: colours that were hardcoded in the flyout ----
    // Slider fill (dark: copper; light: flat #e2b865, not light `copper`).
    required property color accentFill
    // Amp header hover fill.
    required property color headerHover
    // Muted (active) mute-button fill.
    required property color activeFill
    // Card shadow under controls (buttons, source row, chip, +/-);
    // transparent in dark, which has no control shadows.
    required property color cardShadow

    // ---- Phase 17.19.2: control alpha, per palette ----
    // Phase 9.1.1 REVISION 4 (moved here from TransparencySettings.qml in
    // Phase 17.19.2; "controlAlpha" below is this palette's controlAlphaK):
    // interactive chrome (volume +/- buttons, mute/power buttons, the source
    // row, and the current-source chip - NOT the overlay dropdown cards, see
    // TransparencySettings.overlayAlpha) targets a
    // FRACTION of the remaining gap to full opacity, not a flat +N-point
    // EFFECTIVE offset - the previous ("REVISION") formula had a real
    // bug, not just a tuning issue: `Math.min(1.0, alpha +
    // controlOffsetTarget)` clamps to exactly 1.0 once alpha >= 1 -
    // controlOffsetTarget (0.90 at controlOffsetTarget=0.10), which
    // forces the inverse-solved controlAlpha to ALSO be exactly 1.0 for
    // the entire panel range 90-100% - buttons rendered as fully solid,
    // unchanging pixels while the panel itself kept visibly changing
    // right up to 100%. Confirmed both mathematically (a standalone
    // computation of the old formula across panel 75-100% showed
    // controlAlpha flat at 1.0000 from panel=0.90 onward, every single
    // step) and live (screenshots at panel 75/85/90/94/100%: 75% and
    // 100% looked correct, everything between looked visibly "off",
    // worst in the high-80s/low-90s - exactly the plateau's span).
    //
    // Fix: targetEffective = panelAlpha + (1 - panelAlpha) * k for a
    // fraction k (controlAlphaK) - closes a FRACTION of the
    // remaining gap to 1.0, not a fixed number of points, so
    // targetEffective is strictly < 1.0 whenever panelAlpha is (for any
    // k < 1) and can never plateau or need clamping. Same compositing-
    // correction inverse as before (effectiveOpacity = 1 - (1 -
    // panelAlpha) * (1 - chromeAlpha), solved for chromeAlpha given the
    // target) - but for THIS specific target shape the algebra collapses
    // to an exact constant:
    //   1 - targetEffective = 1 - panelAlpha - (1-panelAlpha)*k
    //                        = (1-panelAlpha)*(1-k)
    //   controlAlpha = 1 - (1-targetEffective)/(1-panelAlpha)
    //                = 1 - (1-k) = k
    // i.e. painting chrome at a flat raw alpha k and letting Porter-Duff
    // compositing do the rest IS the inverse-corrected solution for a
    // proportional-gap target - verified numerically (a standalone
    // computation confirmed controlAlpha comes out to exactly k at every
    // panel value tested, 0 through 0.99) before relying on it. Written
    // as the closed form directly (not the general divide-based inverse)
    // for two reasons: it's what the algebra actually reduces to, and
    // the general form divides by (1-panelAlpha), which -> 0 as
    // panelAlpha -> 1 and is a real (if usually harmless) source of
    // floating-point noise near the top of the range - exactly where
    // the previous formula's bug lived, so avoiding that division
    // entirely here is deliberate, not just a simplification.
    //
    // k chosen live (Phase 9.1.1 REVISION 4 sweep, TODO.md): candidates
    // 0.3/0.4/0.5 compared at panel 50% plus a fine ~3%-step sweep across
    // 75-100% (the exact range the old bug broke) confirmed smooth,
    // continuously-changing effective opacity with no plateau at every
    // tested k - the choice among them is a real aesthetic trade-off
    // (low k: subtle everywhere, including at low panel opacity where
    // more standout was wanted; high k: closer to the old flat-offset
    // feel, more standout at low panel, less separation-per-point-of-
    // panel-change near the very top), not a bug to be tuned away.
    // Revision 5 picked 0.3; Revision 6 (owner, live): the top end
    // (panel ~70%+) already looked right at k=0.3, the problem was
    // specifically the low end - k*(1-panelAlpha) is a ~30pt gap at
    // panel=0%, too large for an almost-invisible panel. Since the gap
    // shrinks proportionally with k at every panel value (not two
    // problems needing different curve shapes), lowering k alone fixes
    // the low end and only makes the already-fine top end more subtle
    // still. 0.1 sets the panel=0% gap to exactly 10pt
    // (targetEffective = panelAlpha + (1-panelAlpha)*k reduces to
    // targetEffective = k when panelAlpha = 0), tapering smoothly from
    // there - the owner's explicit target.
    // Phase 17.19.2: one model for both themes (the 17.19.1 light-glass
    // spike measured light's glass alpha, 0.35 + 0.65 x panel alpha, as the
    // cause of grey "slabs" over dark wallpapers: +94 levels above the panel
    // at alpha 0.20 over black, against +20 with fixed k = 0.1). Dark 0.1 is
    // the unchanged value; light 0.1 is a starting value to tune live.
    required property real controlAlphaK

    // Background of a control (button, source row, chip, +/- steppers):
    // `surface` at the palette's fixed controlAlphaK, painted over the
    // panel, for both themes. `ts` is no longer read (k does not depend on
    // the transparency setting - that is the point of the fixed-k model);
    // the parameter stays so the call sites are unchanged.
    function controlColor(ts: TransparencySettings): color {
        return Qt.rgba(cp.surface.r, cp.surface.g, cp.surface.b, cp.controlAlphaK);
    }
}
