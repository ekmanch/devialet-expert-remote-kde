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

    // Background of a control (button, source row, chip, +/- steppers) at
    // the configured transparency. One mechanism for both themes: dark
    // uses the constant control alpha over `surface`; light uses the
    // mockup's glass alpha (0.35 + 0.65 x panel alpha) over white, so the
    // buttons frost together with the panel (flyout mockup v3 :67, :85).
    function controlColor(ts: TransparencySettings): color {
        return cp.isLight ? ts.withGlassAlpha(cp.surface) : ts.withControlAlpha(cp.surface);
    }
}
