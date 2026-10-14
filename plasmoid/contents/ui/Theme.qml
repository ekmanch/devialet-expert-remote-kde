// Fonts, sizes, radii and the volume icon map, from
// the original flyout mockup's :root custom
// properties. No colours: those are in ColorPalette.qml and its two
// palettes. Plain QtObject, not `pragma Singleton` (this KPackage has no
// qmldir module); it holds nothing that needs syncing, so each file that
// needs it instantiates its own `Theme {}` (docs/DESIGN.md §3).
//
// Font files live in contents/fonts/ (assets/fonts/ is outside the
// KPackage payload) and load via
// `FontLoader { source: Qt.resolvedUrl("../fonts/...") }`, the same
// convention as org.kde.plasma.advanced-weather-widget. Every weight file
// of a family reports the same `font.family` with a distinct
// `font.weight`, so `font.family: theme.fontDisplay; font.weight:
// Font.DemiBold` selects the matching static face through Qt's normal
// weight matching.
import QtQuick

QtObject {
    id: theme

    // ---- Volume-level icon selection ----
    // Breakpoints match the Audio Devices applet's AudioIcon::forVolume()
    // (plasma-pa's src/audioicon.cpp): muted or percent<=0 -> mute, <=25 ->
    // low, <=75 -> medium, else high. Its overdrive tiers above 100 % have
    // no meaning here: volumeFraction is clamped to 0..1. Used by
    // VolumeToast.qml and ActionRow.qml; reuse these thresholds rather
    // than re-deriving them.
    readonly property var volumeIconSources: ({
        high: Qt.resolvedUrl("../icons/audio-volume-icons/volume-high.svg"),
        medium: Qt.resolvedUrl("../icons/audio-volume-icons/volume-medium.svg"),
        low: Qt.resolvedUrl("../icons/audio-volume-icons/volume-low.svg"),
        mute: Qt.resolvedUrl("../icons/audio-volume-icons/volume-mute.svg")
    })
    function volumeIconKindForFraction(fraction) {
        const percent = fraction * 100;
        if (percent <= 0) return "mute";
        if (percent <= 25) return "low";
        if (percent <= 75) return "medium";
        return "high";
    }

    // ---- Fonts ----
    // One FontLoader per weight the mockup uses (Space Grotesk
    // 400/500/600/700, JetBrains Mono 400/500/600) - the files in
    // contents/fonts/.
    readonly property FontLoader _sgRegular: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_regular.ttf") }
    readonly property FontLoader _sgMedium: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_medium.ttf") }
    readonly property FontLoader _sgSemibold: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_semibold.ttf") }
    readonly property FontLoader _sgBold: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_bold.ttf") }
    readonly property FontLoader _jbRegular: FontLoader { source: Qt.resolvedUrl("../fonts/jetbrains_mono_regular.ttf") }
    readonly property FontLoader _jbMedium: FontLoader { source: Qt.resolvedUrl("../fonts/jetbrains_mono_medium.ttf") }
    readonly property FontLoader _jbSemibold: FontLoader { source: Qt.resolvedUrl("../fonts/jetbrains_mono_semibold.ttf") }

    // Family names, available once a weight of each family has loaded.
    // "" (Qt's default UI font) while loading, rather than blank text.
    readonly property string fontDisplay: theme._sgRegular.status === FontLoader.Ready ? theme._sgRegular.font.family : ""
    readonly property string fontMono: theme._jbRegular.status === FontLoader.Ready ? theme._jbRegular.font.family : ""

    // The mockup's --font-body (Inter) is not bundled; body text leaves
    // font.family unset and uses Plasma's system UI font. A deliberate
    // substitution.

    // ---- Spacing/sizing constants reused across the restyle ----
    readonly property int panelWidth: 300
    readonly property int radiusLg: 16
    readonly property int radiusMd: 11
    readonly property int radiusSm: 8

    // ---- Overlay cards (mockup v2 `.overlay-popup`) ----
    // AmpListOverlay.qml and SourceListOverlay.qml render as floating cards
    // inset from the flyout's edges. Their radius is an explicit constant,
    // not Kirigami.Units.cornerRadius, which has nothing to do with these
    // self-drawn cards.
    readonly property int radiusOverlay: 13
    // `.amp-option` / `.source-option` border-radius: 9px.
    readonly property int radiusOverlayRow: 9
}
