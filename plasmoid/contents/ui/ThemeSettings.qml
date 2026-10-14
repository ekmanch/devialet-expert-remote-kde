// Which colour palette each surface paints: the widget's Dark / Light /
// Follow-system setting resolved to ColorPalette objects.
//
// Root-anchored in main.qml and forwarded like TransparencySettings.qml
// (main.qml -> CompactRepresentation -> FlyoutPopup -> FlyoutContent, and
// CompactRepresentation -> VolumeToast / VolumeHoverTooltip), because the
// flyout, OSD and tooltip must never disagree about the theme
// (docs/DESIGN.md §3). The settings page cannot reach main.qml's root and
// resolves its own palette from the desktop's scheme (§6).
//
// flyoutPalette and osdPalette are separate, though both follow the one
// `theme` setting, so a per-surface setting later is one more kcfg key
// and one binding here, with no consumer changes.

import QtQuick

QtObject {
    id: ts

    // Plasmoid.configuration.theme: "dark" | "light" | "system" (default).
    // Any other value is treated like "dark".
    required property string mode

    // What the desktop's colour scheme says when mode is "system". Starts
    // true (dark) and changes only when a value arrives; main.qml binds it
    // to SystemScheme.dark (the XDG portal reader).
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

    // The OSD toast + hover tooltip's own resolution. They follow the
    // widget's theme; an option to follow the desktop's appearance instead
    // would be one kcfg key plus this binding, e.g.
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

    // The flyout follows the resolved theme; the OSD toast and tooltip do
    // too, through their own seam above.
    readonly property ColorPalette flyoutPalette: ts.resolvedDark ? ts.dark : ts.light
    readonly property ColorPalette osdPalette: ts.osdResolvedDark ? ts.dark : ts.light
}
