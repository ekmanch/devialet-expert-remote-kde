// Phase 17.19.0 - the light palette. Values from the v3 flyout mockup
// (design/mockups/flyout/... v3.html, `body[data-mode="light"]` and
// `body[data-theme="gold"]` blocks) unless noted. Pure white surfaces,
// near-black text, gold accents; see ColorPalette.qml for each token.
//
// Light OSD/tooltip (17.22.0/17.23.0) and the light settings page
// (17.25.0-17.27.0) build on these same tokens; until those phases only the
// flyout paints this palette (ThemeSettings.flyoutPalette).

import QtQuick

ColorPalette {
    isLight: true

    // ---- Surfaces and controls ----
    surface: "#ffffff"                             // --surface
    surface2: Qt.rgba(28 / 255, 24 / 255, 18 / 255, 0.045)   // --row-hover (surface2 is the flyout's hover fill)
    surface3: "#ece9e4"                            // --surface-3 (slider/bar track)
    divider: Qt.rgba(28 / 255, 24 / 255, 18 / 255, 0.09)     // --divider

    // ---- Accent (gold) ----
    copper: "#c39443"                              // --copper
    copperBright: "#9c6d20"                        // --copper-bright
    copperDim: "#e2c88f"                           // --copper-dim / --active-border

    // ---- Text ----
    text: "#1c1a17"
    textDim: "#6e6a64"
    textFaint: "#a29d95"

    // ---- Status ----
    danger: "#b23b30"
    dangerBright: "#a3342a"                        // configDialog mockup v2 light --danger-bright
    success: "#3d8a57"
    successBright: "#2f7a48"
    warning: "#e2bf6a"
    warningBright: "#b8862e"

    // ---- Flyout panel tint (opaque; alpha applied via TransparencySettings) ----
    panelTintTop: "#ffffff"
    panelTintBottom: "#ffffff"

    // ---- OSD toast + hover tooltip (D3: opaque white in light) ----
    osdGradientTop: "#ffffff"
    osdGradientBottom: "#ffffff"

    // ---- Overlay cards ----
    overlayGradientTop: "#ffffff"                  // --popup-bg
    overlayGradientBottom: "#ffffff"
    overlayBorder: Qt.rgba(28 / 255, 24 / 255, 18 / 255, 0.09)   // --popup-border
    overlayShadow: Qt.rgba(20 / 255, 16 / 255, 10 / 255, 0.26)   // --popup-shadow

    // ---- Formerly hardcoded ----
    accentFill: "#e2b865"                          // --accent-fill (flat gold)
    headerHover: Qt.rgba(28 / 255, 24 / 255, 18 / 255, 0.025)    // --header-hover
    activeFill: Qt.rgba(195 / 255, 148 / 255, 67 / 255, 0.10)    // --active-bg
    cardShadow: Qt.rgba(20 / 255, 16 / 255, 10 / 255, 0.10)      // --card-shadow
    controlAlphaK: 0.1                                           // 17.19.2 starting value (fixed-k, as dark); tune live
}
