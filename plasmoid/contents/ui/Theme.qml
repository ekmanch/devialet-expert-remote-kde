// Phase 4.0: centralizes the copper/graphite palette + custom font access
// (since Phase 17.11.0 the palette lives in ColorPalette.qml/DarkPalette.qml;
// this file keeps fonts, sizes, radii and the volume icon map)
// ported 1:1 from design/mockups/devialet_tray_flyout_mockup.html's :root
// CSS custom properties, so FullRepresentation.qml doesn't repeat hex
// literals throughout. Plain QtObject (not `pragma Singleton`) - this
// KPackage has no qmldir/module registration set up for a true singleton,
// and a single `Theme { id: theme }` instance shared within
// FullRepresentation.qml is all that's needed (only one representation is
// ever shown at a time for this plasmoid's popup).
//
// Font loading: font files live at contents/fonts/ (NOT assets/fonts/,
// which is a source/reference-only location outside the KPackage payload -
// kpackagetool6 installs only what's under plasmoid/, confirmed via
// CLAUDE.md's Repository Layout and by finding real precedent, not
// guessed: org.kde.plasma.advanced-weather-widget ships
// contents/fonts/weathericons-regular-webfont.ttf and loads it from
// contents/ui/ via `FontLoader { source: Qt.resolvedUrl("../fonts/...") }`
// - same convention followed here). Confirmed live (qml6, this machine):
// each weight-variant file reports the SAME `font.family` string (e.g.
// all four Space Grotesk files report family "Space Grotesk") with
// correctly distinct `font.weight` (400/500/600/700) - so loading every
// weight file registers it in Qt's font database under one shared family
// name, and plain `font.family: theme.fontDisplay; font.weight:
// Font.DemiBold` (etc.) correctly selects the matching static face -
// standard Qt font-database weight matching, not something this file
// needs to hand-roll.
import QtQuick

QtObject {
    id: theme

    // ---- Colours: moved out in Phase 17.11.0 ----
    // Every colour token now lives in ColorPalette.qml (the typed token
    // set) and DarkPalette.qml / LightPalette.qml (the values); consumers
    // read them from a `colors` property. This file keeps what does not
    // change between palettes: the volume icon map, fonts, sizes, radii.
    // (`bg` #0e0e10 was read nowhere and was not carried over.)

    // ---- Volume-level icon selection (Phase 4.5.3 Part D) ----
    // Breakpoints matched against the real Audio Devices applet's own
    // AudioIcon::forVolume() (plasma-pa's src/audioicon.cpp/.h): muted or
    // percent<=0 -> mute, <=25 -> low, <=75 -> medium, <=100 -> high (its
    // further 101-125/>125 "warning"/"danger" tiers have no equivalent
    // icon here and no meaning for us - volumeFraction is hard-clamped to
    // 0..1 with no overdrive-past-ceiling concept, unlike PulseAudio's
    // boostable volume). Used by VolumeToast.qml's icon box only - a
    // similar icon was briefly added to VolumeHoverTooltip.qml too but
    // reverted (Phase 4.5.3 follow-up item 1 - the approved mockup only
    // ever used a status dot there, not a full icon). Kept centralized
    // here regardless, since it's still shared infrastructure in the
    // sense that any future consumer should reuse these thresholds
    // rather than re-deriving them.
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
    // One FontLoader per weight actually used in the mockup - matches the
    // exact weight set Google Fonts is asked for there (Space Grotesk
    // 400/500/600/700, JetBrains Mono 400/500/600), which is exactly the
    // set of files present in contents/fonts/, confirmed by listing them.
    readonly property FontLoader _sgRegular: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_regular.ttf") }
    readonly property FontLoader _sgMedium: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_medium.ttf") }
    readonly property FontLoader _sgSemibold: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_semibold.ttf") }
    readonly property FontLoader _sgBold: FontLoader { source: Qt.resolvedUrl("../fonts/space_grotesk_bold.ttf") }
    readonly property FontLoader _jbRegular: FontLoader { source: Qt.resolvedUrl("../fonts/jetbrains_mono_regular.ttf") }
    readonly property FontLoader _jbMedium: FontLoader { source: Qt.resolvedUrl("../fonts/jetbrains_mono_medium.ttf") }
    readonly property FontLoader _jbSemibold: FontLoader { source: Qt.resolvedUrl("../fonts/jetbrains_mono_semibold.ttf") }

    // Family name strings, available once at least one weight of each has
    // loaded (all weights of the same family report the same name - see
    // header comment). Falls back to "" (Qt's default UI font) while
    // loading rather than showing blank/broken text - matches the
    // guarded-access idiom found in the real weather-widget precedent
    // (`loader.status === FontLoader.Ready ? loader.font.family : ""`).
    readonly property string fontDisplay: theme._sgRegular.status === FontLoader.Ready ? theme._sgRegular.font.family : ""
    readonly property string fontMono: theme._jbRegular.status === FontLoader.Ready ? theme._jbRegular.font.family : ""

    // The mockup's --font-body (Inter, via Google Fonts) has no bundled
    // font file in this repo (only Space Grotesk/JetBrains Mono are
    // shipped at assets/fonts/) - deliberately not fetched here (the task
    // was to use the files already in the repo, not source new ones).
    // Body text that the mockup styles with --font-body falls back to
    // Plasma's own system UI font instead (leaving font.family unset).
    // Flagging this as a deliberate, documented substitution, not a
    // silent gap.

    // ---- Spacing/sizing constants reused across the restyle ----
    readonly property int panelWidth: 300
    readonly property int radiusLg: 16
    readonly property int radiusMd: 11
    readonly property int radiusSm: 8

    // ---- Phase 7.14.0: overlay cards (mockup v2 `.overlay-popup`) ----
    // Both AmpListOverlay.qml and SourceListOverlay.qml render as floating
    // cards inset from the flyout's edges. Their corner radius is an
    // explicit constant, NOT Kirigami.Units.cornerRadius - that one exists
    // to match Darkly's window-frame SVG under the flyout's own outer
    // corner (FlyoutContent's tint Rectangle) and has nothing to do with
    // these self-drawn inner cards (owner decision, Phase 7.14.0).
    readonly property int radiusOverlay: 13
    // `.amp-option` / `.source-option` border-radius: 9px.
    readonly property int radiusOverlayRow: 9
}
