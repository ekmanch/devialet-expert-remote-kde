// The dark palette. See ColorPalette.qml for what each token is for.

import QtQuick

ColorPalette {
    isLight: false

    // ---- Surfaces and controls ----
    // Pulled close to the panel base (#151515, Darkly's window background):
    // +3/+6/+9 levels over it, neutral grey (R=G=B) like the panel tint.
    // Like Darkly, controls sit at nearly the panel's tone and get their
    // definition from the divider border and copperDim hover, not from a
    // fill-lightness jump; larger lifts, compounded by controlAlphaK, made
    // buttons read as a separate layer at high panel opacity. Judged live,
    // not measured.
    surface: "#181818"
    surface2: "#1b1b1b"
    surface3: "#1e1e1e"
    divider: Qt.rgba(1, 1, 1, 0.08)

    // ---- Accent (the original flyout mockup's :root) ----
    copper: "#c17f4e"
    copperBright: "#e3a06a"
    copperDim: "#8a5c39"

    // ---- Text ----
    text: "#f2f0ec"
    textDim: "#9a9a9f"
    textFaint: "#5c5c60"

    // ---- Status ----
    danger: "#b5544a"
    dangerBright: "#d17165"
    success: "#5fa374"
    successBright: "#7bc796"
    warning: "#a3813a"
    warningBright: "#e0b563"

    // Flyout panel tint, opaque base colours only. FlyoutContent.qml applies
    // the user's transparency with
    // `transparencySettings.withAlpha(colors.panelTintTop/Bottom)`. Kept as
    // plain #rrggbb so nothing uses them without going through withAlpha().
    // #151515 is Darkly's window background. A +-3-level gradient and a
    // flat pair looked identical live; flat is used here.
    panelTintTop: "#151515"
    panelTintBottom: "#151515"

    // OSD toast (VolumeToast.qml) and hover tooltip (VolumeHoverTooltip.qml)
    // background: a fixed translucent graphite gradient with alpha 0.94,
    // not the flyout's live transparency setting. Dark keeps this pair
    // rather than the v2 mockups' flat #121212 at 0.96 / opaque.
    osdGradientTop: Qt.rgba(23 / 255, 23 / 255, 26 / 255, 0.94)
    osdGradientBottom: Qt.rgba(18 / 255, 18 / 255, 20 / 255, 0.94)

    // ---- Overlay cards (mockup v2 `.overlay-popup` background + border) ----
    overlayGradientTop: "#1e1e21"
    overlayGradientBottom: "#19191c"
    overlayBorder: Qt.rgba(1, 1, 1, 0.10)
    overlayShadow: Qt.rgba(0, 0, 0, 0.5)

    // ---- Flyout details ----
    accentFill: "#c17f4e"                          // = copper (VolumeBlock fill)
    headerHover: Qt.rgba(1, 1, 1, 0.02)            // AmpHeader hover
    activeFill: Qt.rgba(193 / 255, 127 / 255, 78 / 255, 0.14)   // copper at 0.14, muted button
    cardShadow: "transparent"                      // no control shadows in dark
    controlBorder: Qt.rgba(1, 1, 1, 0.08)          // = divider
    chipBorder: Qt.rgba(1, 1, 1, 0.08)             // = divider
    // Unused in dark (flat text); the flat colours.
    readoutGradientStart: "#e3a06a"
    readoutGradientEnd: "#e3a06a"
    readoutGlow: "transparent"
    eyebrowGradientStart: "#5c5c60"
    eyebrowGradientEnd: "#5c5c60"
    // Gold text is unused in dark (flat copperBright); mutedFill = textFaint.
    goldTextStart: "#e3a06a"
    goldTextMid: "#e3a06a"
    goldTextEnd: "#e3a06a"
    mutedFill: "#5c5c60"

    // ---- Settings page (the values the dark page painted, apart from the
    // brand mark's ring and disk) ----
    listBackground: "#1b1b1b"                      // = surface2
    listHover: "#1e1e1e"                           // = surface3
    controlValueText: "#e3a06a"                    // = copperBright
    brandRingStart: "#654c3a"                      // configDialog mockup v30 :246
    brandRingMid: "#654c3a"
    brandRingEnd: "#654c3a"
    brandRingInner: "#262221"
    brandDiskStart: "#e3a06a"                      // :249
    brandDiskMid: "#e3a06a"
    brandDiskEnd: "#e3a06a"
    switchOff: "#1e1e1e"                           // = surface3
    switchBorder: Qt.rgba(1, 1, 1, 0.08)           // = divider
    switchKnobOff: "#e8e6e1"                       // SettingsSwitch.qml's original knob
    switchKnobOn: "#e3a06a"                        // = copperBright
    switchKnobShadow: "transparent"
    switchOnStart: "#8a5c39"                       // = copperDim (flat)
    switchOnMid: "#8a5c39"
    switchOnEnd: "#8a5c39"
    segmentActiveFill: "#1e1e1e"                   // = surface3
    segmentActiveBorder: "transparent"
    segmentActiveText: "#e3a06a"                   // = copperBright
    controlAlphaK: 0.1                             // see ColorPalette.qml
}
