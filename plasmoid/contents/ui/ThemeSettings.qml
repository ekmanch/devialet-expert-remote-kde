// Phase 17.12.0 - which colour palette each surface paints: the widget's
// Dark / Light / Follow-system setting resolved to ColorPalette objects.
//
// Root-anchored in main.qml and forwarded like TransparencySettings.qml
// (main.qml -> CompactRepresentation -> FlyoutPopup -> FlyoutContent, and
// CompactRepresentation -> VolumeToast / VolumeHoverTooltip), because the flyout, OSD
// and tooltip must never disagree about the theme (CLAUDE.md "Shared
// cross-view state"). The ConfigDialog page cannot reach main.qml's root and
// resolves its own page palette (17.14.0/17.15.0).
//
// Two palettes are exposed from day one - flyoutPalette and osdPalette -
// both following the one `theme` setting today, so a later per-surface
// setting (the owner may theme the OSD/tooltip separately) is one more kcfg
// key and one binding here, with no consumer changes.
//
// Since 17.19.0 the flyout paints LightPalette when the theme resolves light;
// osdPalette stays dark until 17.22.0/17.23.0.

import QtQuick

QtObject {
    id: ts

    // Plasmoid.configuration.theme: "dark" | "light" | "system" (default).
    // Any other value is treated like "dark".
    required property string mode

    // What the desktop's colour scheme says when mode is "system". Starts
    // true (today's look) and changes only when a value arrives; main.qml
    // binds it to SystemScheme.dark (the XDG portal reader, 17.15.0).
    property bool systemDark: true

    // Harness-only: when non-empty ("dark"/"light"), wins over `mode`, so
    // captures can pin a theme without writing KConfig. Set through
    // FlyoutContent.themeOverride (a Harness1.UiState key); the harness
    // clears it on teardown so it never outlives a run.
    property string harnessOverride: ""

    readonly property string effectiveMode: ts.harnessOverride !== "" ? ts.harnessOverride : ts.mode
    readonly property bool resolvedDark: ts.darkFor(ts.effectiveMode)

    // "dark" | "light" | "system" -> paints dark? (anything else: dark)
    function darkFor(m: string): bool {
        return m === "system" ? ts.systemDark : m !== "light";
    }

    // The OSD toast + hover tooltip's own resolution (Phase 17.13.0 seam).
    // Today they simply follow the widget's Theme. A later option to let
    // them follow the desktop's appearance instead (owner idea, 2026-09-27)
    // is one kcfg key plus this binding, e.g.
    //     osdResolvedDark: osdFollowsSystem ? systemDark : resolvedDark
    // - no change in VolumeToast/VolumeHoverTooltip, which read osdPalette.
    // The harness override applies through resolvedDark, so it still pins
    // all three surfaces.
    readonly property bool osdResolvedDark: ts.resolvedDark

    readonly property ColorPalette dark: DarkPalette {}
    readonly property ColorPalette light: LightPalette {}

    // One journal line per change (and at startup), so the resolution can
    // be checked from `journalctl --user` without a debugger.
    // (The bindings settle during creation and would fire both change
    // handlers once before onCompleted; `_started` keeps it to one line.)
    property bool _started: false
    onEffectiveModeChanged: if (ts._started) ts.logState()
    onResolvedDarkChanged: if (ts._started) ts.logState()
    Component.onCompleted: {
        ts._started = true;
        ts.logState();
    }
    function logState() {
        console.log("[ThemeSettings] mode", ts.mode, "effective", ts.effectiveMode,
                    "systemDark", ts.systemDark, "resolvedDark", ts.resolvedDark);
    }

    // Phase 17.19.0: the flyout follows the resolved theme. The OSD toast
    // and tooltip stay dark until their light phases (17.22.0/17.23.0) make
    // this `ts.osdResolvedDark ? ts.dark : ts.light`.
    readonly property ColorPalette flyoutPalette: ts.resolvedDark ? ts.dark : ts.light
    readonly property ColorPalette osdPalette: ts.dark
}
