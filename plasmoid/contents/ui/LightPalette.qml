// Phase 17.19.0 - the light palette. Values from the flyout mockup, v22
// since Phase 17.19.3 (design/mockups/flyout/Devialet Flyout Mockup
// v22.html, `body[data-mode="light"]` :61-84 and `body[data-theme="gold"]`
// :95-107) unless noted. Pure white surfaces,
// near-black text, gold accents; see ColorPalette.qml for each token.
//
// The flyout (ThemeSettings.flyoutPalette), the OSD toast and hover tooltip
// (osdPalette, 17.22.0/17.23.0) and the settings page on a light desktop
// (ConfigGeneral.qml, 17.24.0-17.27.0) paint this palette. The OSD, tooltip
// and configDialog mockups still list the pre-v21 dim/faint text (#6e6a64 /
// #a29d95); they get the flyout's darker pair below, one palette for all
// four surfaces.

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

    // ---- Phase 17.24.0-17.27.0: settings page (configDialog mockup v30) ----
    listBackground: "#ffffff"                                    // --list-bg (:80)
    listHover: Qt.rgba(24 / 255, 20 / 255, 15 / 255, 0.04)       // --list-hover
    controlValueText: "#1c1a17"                                  // --val-color / .kcm-slider-value (:96, :108)
    brandRingStart: "#ecd3a0"                                    // .bm-ring, 145deg, stops 0 / 60 % / 100 % (:250-254)
    brandRingMid: "#dcb068"
    brandRingEnd: "#cfa052"
    brandRingInner: "#ffffff"
    brandDiskStart: "#efc977"                                    // .bm-disk, 145deg, stops 0 / 55 % / 100 % (:255)
    brandDiskMid: "#e0aa4b"
    brandDiskEnd: "#cf9738"
    switchOff: "#e6e2dc"                                         // --switch-off (:92)
    switchBorder: Qt.rgba(24 / 255, 20 / 255, 15 / 255, 0.08)    // --switch-border (:77)
    switchKnobOff: "#ffffff"                                     // --knob-off / --knob-on (:76, :97)
    switchKnobOn: "#ffffff"
    switchKnobShadow: Qt.rgba(24 / 255, 20 / 255, 15 / 255, 0.30)   // --knob-shadow 0 1px 3px (:76)
    switchOnStart: "#b07a27"                                     // --switch-on, 90deg, stops 0 / 60 % / 100 % (:93)
    switchOnMid: "#dcaa4f"
    switchOnEnd: "#efc36a"
    segmentActiveFill: "#ffffff"                                 // --seg-active-bg (:95)
    segmentActiveBorder: "#1c1a17"                               // --seg-active-shadow inset 0 0 0 1px
    segmentActiveText: "#1c1a17"                                 // --seg-active-color
    controlAlphaK: 0.1                                           // 17.19.2 starting value (fixed-k, as dark); tune live
}
