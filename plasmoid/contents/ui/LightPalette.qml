// Phase 17.19.0 - the light palette. Values from the flyout mockup, v22
// since Phase 17.19.3 (design/mockups/flyout/Devialet Flyout Mockup
// v22.html, `body[data-mode="light"]` :61-84 and `body[data-theme="gold"]`
// :95-107) unless noted. Pure white surfaces,
// near-black text, gold accents; see ColorPalette.qml for each token.
//
// The flyout (ThemeSettings.flyoutPalette) and, since 17.22.0/17.23.0, the
// OSD toast and hover tooltip (osdPalette) paint this palette; the light
// settings page (17.25.0-17.27.0) builds on the same tokens. The OSD and
// tooltip mockups (v4/v5) still list the pre-v21 dim/faint text (#6e6a64 /
// #a29d95); they get the flyout's darker pair below, one palette for all
// three surfaces.

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
    // Phase 17.19.3: darkened in mockup v21 (v22 :69-73) so they stay
    // legible over a translucent, blurred backdrop; were #6e6a64 / #a29d95.
    textDim: "#3f3a33"
    textFaint: "#524c45"

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
    controlBorder: Qt.rgba(28 / 255, 24 / 255, 18 / 255, 0.10)   // --btn-border (v22 :76)
    chipBorder: Qt.rgba(28 / 255, 24 / 255, 18 / 255, 0.16)      // .vol-source-chip border (v22 :158)

    // ---- Phase 17.20.0: gradient text ----
    readoutGradientStart: "#dca136"                              // .vol-value (v22 :111)
    readoutGradientEnd: "#f3cf7c"
    readoutGlow: Qt.rgba(199 / 255, 154 / 255, 46 / 255, 0.35)   // text-shadow 0 0 14px (v22 :115)
    eyebrowGradientStart: "#97691f"                              // --eyebrow (v22 :104)
    eyebrowGradientEnd: "#cf9c45"

    // ---- Phase 17.22.0: OSD toast + tooltip (OSD mockup v4 :104-105) ----
    goldTextStart: "#a8710b"                                     // --gold-text, stops 0 / 55 % / 100 %
    goldTextMid: "#d99a1f"
    goldTextEnd: "#efc36a"
    mutedFill: "#d8d3cb"                                         // --muted-fill
    controlAlphaK: 0.1                                           // 17.19.2 starting value (fixed-k, as dark); tune live
}
