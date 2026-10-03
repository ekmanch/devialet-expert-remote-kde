// Phase 17.11.0 - the dark palette: today's colours, moved unchanged out
// of Theme.qml (values and their history comments). See ColorPalette.qml
// for what each token is for.

import QtQuick

ColorPalette {
    isLight: false

    // ---- Surfaces and controls ----
    // Phase 9.1.1 REVISION: pulled much closer to the panel base
    // (#151515, Darkly's real window background - owner-confirmed) after
    // the first pass (+6.5/+14.5/+22.8 over panel average, preserving the
    // OLD pre-#151515 palette's lift magnitude) was rejected live -
    // real Darkly (owner's own Dolphin reference screenshot) keeps
    // window chrome and controls at nearly the same tone, separation
    // coming from a thin border/hover state, not a fill-lightness jump.
    // At the old magnitude, controlAlpha's opacity boost (Phase 9.1.1
    // REVISION 2) compounded with the color difference at high panel
    // opacity (90-100%) to make buttons read as a distinct layer
    // entirely, not "a control on this panel."
    //
    // Hue confirmed unchanged, not the cause: every value here and in
    // panelTintTop/Bottom below is strictly R=G=B (checked directly in
    // this file, not assumed) - neutral gray already matched panelTint's
    // hue exactly before this revision, so the mismatch was purely the
    // lightness delta's magnitude, not a blue/grey cast drifting away
    // from the base. New deltas are +3/+6/+9 over the panel's own
    // average (~21, from #151515) - a "few percent lighter" step per
    // tier rather than the old ~+7/+14/+23, still monotonically
    // increasing (so the three tiers stay individually distinguishable
    // from each other) but each one much closer to the panel than
    // before. Border/hover states (already theme.divider / theme.
    // copperDim on every button and row, unchanged by this revision) do
    // the rest of the definition work, matching the Darkly reference.
    // Owner will judge and iterate live - this is a starting point, not
    // a final measured value.
    surface: "#181818"
    surface2: "#1b1b1b"
    surface3: "#1e1e1e"
    divider: Qt.rgba(1, 1, 1, 0.08)

    // ---- Accent (design/mockups/devialet_tray_flyout_mockup.html :root) ----
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

    // Flyout panel tint, opaque base colours only (Phase 9.1.0). The old
    // panelGradientTop/Bottom baked a hardcoded 0.82 alpha in here,
    // inherited from a mockup variant that assumed an 18px backdrop blur
    // Plasma never provided (see TODO.md's Phase 9.0.0 entry, "Provenance
    // of 0.82 and 0.94"). Alpha is now user-configured, live, and shared
    // across every translucent surface via TransparencySettings.qml -
    // FlyoutContent.qml applies it with
    // `transparencySettings.withAlpha(colors.panelTintTop/Bottom)`. Kept
    // as plain #rrggbb rather than Qt.rgba(...,1.0) so callers can't
    // accidentally use these without going through withAlpha() first.
    //
    // Phase 9.1.1: recentered on #151515 (Darkly's real window background
    // - owner-confirmed, used directly, not re-derived). Flat-vs-gradient
    // decided live, not silently: a flat #151515/#151515 pair and this
    // ±3-level gradient (exact same total depth as the old #17171a/
    // #121214 pair, just recentered and desaturated to #151515's neutral
    // hue - averages to #151515 exactly) were both captured on the real
    // flyout at 95% panel opacity. The two were visually indistinguishable
    // in that comparison - at this magnitude the "gradient" reads as flat
    // to the eye regardless, so flat's "looks boring" risk never actually
    // materializes either way. Kept the gradient anyway, on cost/benefit
    // rather than a visible difference: it costs nothing (imperceptible
    // when not needed) and keeps this surface consistent with every other
    // gradient-based surface in the palette (overlayGradientTop/Bottom,
    // osdGradientTop/Bottom below) rather than making the panel a flat
    // one-off exception - a flat panel next to still-gradient overlay
    // cards would be a design-language inconsistency with no offsetting
    // visual benefit, since flat bought nothing perceptible in the
    // comparison that justified it.
    // readonly property color panelTintTop: "#0E0E10"
    // readonly property color panelTintBottom: "#0E0E10"

    panelTintTop: "#151515"
    panelTintBottom: "#151515"

    // Phase 4.5.0/4.5.3: translucent graphite gradient shared by the OSD
    // toast (VolumeToast.qml) and the hover tooltip (VolumeHoverTooltip.
    // qml) - historically a distinct, slightly more opaque pair from the
    // flyout's own tint (0.94 vs the old hardcoded 0.82), since neither of
    // those two windows gets the flyout's own genuine KWin blur-behind to
    // soften a lower alpha the way the flyout's tint does. Centralized
    // here (Phase 4.5.3 item 2) so both files reference one definition
    // instead of repeating the same rgba literals. Still hardcoded as of
    // Phase 9.1.0 - the flyout's own tint is now panelTintTop/Bottom above
    // (opaque base colours, alpha applied live via TransparencySettings)
    // - unifying this pair onto the same live mechanism is Phase 9.2.0's
    // job, not this one's.
    // Phase 17.9.0/17.10.0 (owner decision, 2026-09-27): dark keeps this
    // pair, not the v2 mockups' flat #121212 at 0.96 / opaque.
    osdGradientTop: Qt.rgba(23 / 255, 23 / 255, 26 / 255, 0.94)
    osdGradientBottom: Qt.rgba(18 / 255, 18 / 255, 20 / 255, 0.94)

    // ---- Overlay cards (mockup v2 `.overlay-popup` background + border) ----
    overlayGradientTop: "#1e1e21"
    overlayGradientBottom: "#19191c"
    overlayBorder: Qt.rgba(1, 1, 1, 0.10)
    overlayShadow: Qt.rgba(0, 0, 0, 0.5)

    // ---- Phase 17.19.0: previously hardcoded in the flyout's files ----
    accentFill: "#c17f4e"                          // = copper (VolumeBlock fill)
    headerHover: Qt.rgba(1, 1, 1, 0.02)            // AmpHeader hover
    activeFill: Qt.rgba(193 / 255, 127 / 255, 78 / 255, 0.14)   // copper at 0.14, muted button
    cardShadow: "transparent"                      // no control shadows in dark
    controlBorder: Qt.rgba(1, 1, 1, 0.08)          // = divider (Phase 17.19.3)
    chipBorder: Qt.rgba(1, 1, 1, 0.08)             // = divider (Phase 17.19.3)
    // Phase 17.20.0: unused in dark (flat text); the flat colours.
    readoutGradientStart: "#e3a06a"
    readoutGradientEnd: "#e3a06a"
    readoutGlow: "transparent"
    eyebrowGradientStart: "#5c5c60"
    eyebrowGradientEnd: "#5c5c60"
    controlAlphaK: 0.1                             // Phase 9.1.1 value, unchanged (moved from TransparencySettings in 17.19.2)
}
