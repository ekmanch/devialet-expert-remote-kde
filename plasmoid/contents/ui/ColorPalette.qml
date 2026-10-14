// The colour-token type for the widget's palettes.
//
// Every colour the flyout, OSD toast, hover tooltip and settings page
// paint comes from one of these tokens; DarkPalette.qml and
// LightPalette.qml are instances that only assign values. Each token is
// `required`, so a palette that forgets one fails at creation with a
// named error instead of silently painting black. A new colour is a new
// token in all three files (docs/DESIGN.md §6).
//
// Consumers declare `required property ColorPalette colors`, so qmllint
// can check token names against this type. Not named Palette/palette:
// QtQuick already exports a `Palette` type and every Item has a built-in
// `palette` property.
//
// Theme.qml keeps fonts, sizes, radii and the volume icon map - nothing
// that changes between palettes.

import QtQuick

QtObject {
    id: cp

    // True for LightPalette. Branch on this only where the two themes need
    // different mechanisms (a gradient or effect against a flat fill),
    // never to choose between two colours.
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

    // ---- Flyout details ----
    // Slider fill (dark: copper; light: flat #e2b865, not light `copper`).
    required property color accentFill
    // Amp header hover fill.
    required property color headerHover
    // Muted (active) mute-button fill.
    required property color activeFill
    // Card shadow under controls (buttons, source row, chip, +/-);
    // transparent in dark, which has no control shadows.
    required property color cardShadow

    // ---- Resting borders of controls (flyout mockup v22) ----
    // Mute, power, -/+ and the source row (`--btn-border`). Dark: same
    // value as `divider`.
    required property color controlBorder
    // The source chip, drawn stronger in light (v22 :158). Dark: same value
    // as `divider`.
    required property color chipBorder

    // ---- Light-theme gradient text (GradientText.qml) ----
    // Left -> right sweep of the volume readout and of the "DEVIALET"
    // wordmark, and the readout's glow. Light only; dark paints these texts
    // flat (copperBright / textFaint) and carries the flat colour in both
    // stops.
    required property color readoutGradientStart
    required property color readoutGradientEnd
    required property color readoutGlow
    required property color eyebrowGradientStart
    required property color eyebrowGradientEnd

    // ---- Light OSD toast + tooltip ----
    // The three-stop sweep of the toast's "Muted" word (`--gold-text`; the
    // settings page headings use the same one). Light only.
    required property color goldTextStart
    required property color goldTextMid
    required property color goldTextEnd
    // Fill of the toast/tooltip bar while muted.
    required property color mutedFill

    // ---- Settings page (ConfigGeneral.qml) ----
    // Light values are the configDialog mockup's (v30).
    // Sound-theme dropdown list: card and row hover.
    required property color listBackground
    required property color listHover
    // Value text inside controls (slider percent, dB stepper value).
    required property color controlValueText
    // Brand mark (BrandMark.qml): ring sweep, the ring's inside, disk sweep.
    // 145 degree sweeps in light, one flat colour per shape in dark.
    required property color brandRingStart
    required property color brandRingMid
    required property color brandRingEnd
    required property color brandRingInner
    required property color brandDiskStart
    required property color brandDiskMid
    required property color brandDiskEnd
    // Switch (SettingsSwitch.qml): off track, border, knob per state, knob
    // shadow, and the "on" track (left -> right sweep in light).
    required property color switchOff
    required property color switchBorder
    required property color switchKnobOff
    required property color switchKnobOn
    required property color switchKnobShadow
    required property color switchOnStart
    required property color switchOnMid
    required property color switchOnEnd
    // Selected segment (SegmentedControl.qml): fill, 1 px outline (light
    // only), label.
    required property color segmentActiveFill
    required property color segmentActiveBorder
    required property color segmentActiveText

    // ---- Control alpha, per palette ----
    // Controls (volume -/+, mute/power, the source row and chip; not the
    // overlay cards, see TransparencySettings.overlayAlpha) target a
    // fraction k of the remaining gap to full opacity:
    //   targetEffective = panelAlpha + (1 - panelAlpha) * k
    // Solving the compositing inverse (effective = 1 - (1 - panelAlpha) *
    // (1 - controlAlpha)) for this target gives controlAlpha = k exactly,
    // at every panel alpha. So a flat raw alpha k is the corrected
    // solution: no clamp, no plateau near 100 %, and no division by
    // (1 - panelAlpha), which goes to 0 at the top of the range. A flat
    // +N-point offset instead clamps to 1.0 and freezes the controls solid
    // over the top of the panel range.
    //
    // k = 0.1, chosen live: higher k (0.3-0.5) left too large a gap on an
    // almost-invisible panel (targetEffective = k at panelAlpha 0), and
    // lowering k only made the already-right top end more subtle. One
    // fixed-k model for both themes: light's earlier glass alpha (0.35 +
    // 0.65 x panel alpha) painted grey slabs over dark wallpapers (+94
    // levels above the panel at alpha 0.20 over black, against +20 with
    // k = 0.1). Light's 0.1 is a starting value to tune live.
    required property real controlAlphaK

    // Background of a control (button, source row, chip, +/- steppers):
    // `surface` at the palette's fixed controlAlphaK, painted over the
    // panel, for both themes. `ts` is not read (k does not depend on the
    // transparency setting - that is the point of the fixed-k model); the
    // parameter stays so the call sites are unchanged.
    function controlColor(ts: TransparencySettings): color {
        return Qt.rgba(cp.surface.r, cp.surface.g, cp.surface.b, cp.controlAlphaK);
    }
}
