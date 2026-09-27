// Phase 17.12.0 - which colour palette each surface paints: the widget's
// Dark / Light / Follow-system setting resolved to ColorPalette objects.
//
// Root-anchored in main.qml and forwarded like TransparencySettings.qml
// (main.qml -> CompactRepresentation -> FlyoutPopup -> FlyoutContent; the
// OSD toast and hover tooltip get it in 17.13.0), because the flyout, OSD
// and tooltip must never disagree about the theme (CLAUDE.md "Shared
// cross-view state"). The ConfigDialog page cannot reach main.qml's root and
// resolves its own page palette (17.14.0/17.15.0).
//
// Two palettes are exposed from day one - flyoutPalette and osdPalette -
// both following the one `theme` setting today, so a later per-surface
// setting (the owner may theme the OSD/tooltip separately) is one more kcfg
// key and one binding here, with no consumer changes.
//
// Until LightPalette.qml exists (17.19.0) every mode resolves to the dark
// palette: `light` and `system` are accepted and resolved (resolvedDark),
// but both palette properties still hand out `dark`.

import QtQuick

QtObject {
    id: ts

    // Plasmoid.configuration.theme: "dark" | "light" | "system" (default).
    // Any other value is treated like "dark".
    required property string mode

    // What the desktop's colour scheme says when mode is "system". Starts
    // true (today's look) and changes only when a value arrives - the
    // portal reader (SystemScheme.qml, 17.15.0) drives it.
    property bool systemDark: true

    // Harness-only: when non-empty ("dark"/"light"), wins over `mode`, so
    // captures can pin a theme without writing KConfig. Set through
    // FlyoutContent.themeOverride (a Harness1.UiState key); the harness
    // clears it on teardown so it never outlives a run.
    property string harnessOverride: ""

    readonly property string effectiveMode: ts.harnessOverride !== "" ? ts.harnessOverride : ts.mode
    readonly property bool resolvedDark: ts.effectiveMode === "system" ? ts.systemDark : ts.effectiveMode !== "light"

    readonly property ColorPalette dark: DarkPalette {}

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

    // 17.19.0: `ts.resolvedDark ? ts.dark : ts.light` for both.
    readonly property ColorPalette flyoutPalette: ts.dark
    readonly property ColorPalette osdPalette: ts.dark
}
