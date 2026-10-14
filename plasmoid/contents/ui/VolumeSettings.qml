// The one owner of volume-range and chime settings, forwarded to every
// surface that shows or adjusts volume: the flyout's VolumeBlock, the
// panel icon's scroll, and (via CompactRepresentation's volumeFraction)
// the OSD toast and hover tooltip. It also holds the clamp/step/fraction
// math, so no surface computes its own.
//
// Root-anchored like PendingAmpState.qml (docs/DESIGN.md §3):
// instantiated once in main.qml and passed down as `required property`
// through CompactRepresentation -> FlyoutPopup -> FlyoutContent ->
// VolumeBlock. It does not import org.kde.plasma.plasmoid; main.qml
// binds the Plasmoid.configuration values into the required properties.
import QtQuick

QtObject {
    id: root

    required property real floorDb
    required property real hardLimitDb
    required property real stepDb
    required property real startupVolumeDb
    // main.xml `chimeEnabled`, the chime's master switch. Lives here
    // because the chime fires from the same stepVolume() paths that use
    // this object. When false both maybeChime()s return before building a
    // command, so devialet-chime is never spawned.
    required property bool chimeEnabled

    // Wheel step spacing: both wheel surfaces (panel icon, flyout slider)
    // turn notches into volume steps at most this often, spaced evenly by
    // WheelStepPacer.qml. Every step spawns devialet-ctl and devialet-chime
    // and makes a D-Bus call from plasmashell's UI thread; unlimited, a
    // free-spinning wheel delivers up to ~300 notches/s and froze the
    // widget for 2-10 s. 20 ms = 50 steps/s (40 ms felt slow). A constant,
    // not a setting.
    readonly property int wheelStepMinIntervalMs: 20
    // The chime's sound source (main.xml chimeSourceMode /
    // chimePinnedTheme / chimeSoundFile) plus the pinned theme's resolved
    // file, all bound in main.qml. Paths are raw here; quoting for the
    // executable engine's /bin/sh -c happens once, in chimeFileArgument(),
    // via SoundThemes.shellQuote (as ConfigGeneral's Preview does).
    required property string chimeSourceMode
    required property string chimePinnedTheme
    required property string chimeSoundFile
    // main.qml's own SoundThemes instance resolves this
    // (soundThemes.pathFor(chimePinnedTheme)): "" when the id isn't an
    // installed theme that has an audio-volume-change.oga.
    required property string chimePinnedThemePath
    required property SoundThemes soundThemes

    // The --file suffix for devialet-chime's command string:
    //   ""     - "follow" mode (or an unrecognized mode string from a
    //            hand-edited config): no --file; devialet-chime resolves
    //            kdeglobals' theme itself.
    //   " --file '<path>'" - a resolvable pinned theme, or a picked file.
    //   null   - the mode needs a file but has none (pinned id not
    //            installed / has no sound, or nothing picked yet). Callers
    //            skip the chime and warn - never a silent fall-back to
    //            another mode.
    function chimeFileArgument() {
        if (root.chimeSourceMode !== "theme" && root.chimeSourceMode !== "file") return "";
        const path = root.chimeSourceMode === "theme" ? root.chimePinnedThemePath : root.chimeSoundFile;
        if (path === "") return null;
        return " --file " + root.soundThemes.shellQuote(path);
    }

    // devialet-chime's arguments: only `--tick k`, so the set of distinct
    // command strings stays fixed at chimeSlots (x the rarely changing
    // --file suffix) for the life of the shell. Every new command string
    // permanently grows every executable DataSource's property map in
    // plasmashell and rebuilds its metaobject (docs/DESIGN.md §5), so
    // per-call data (target and confirmed volume) is not passed: the
    // binary reads it from the daemon itself
    // (crates/devialet-chime/src/daemon.rs).
    //
    // --tick only has to differ between chimes running at the same time:
    // measured at most 9 at once (170 ms median, 208 ms max each, one per
    // wheelStepMinIntervalMs); the longest chime seen (259 ms) / 20 ms
    // needs >= 14, hence 16.
    readonly property int chimeSlots: 16
    function chimeArguments(tick) {
        return " --tick " + (tick % root.chimeSlots);
    }

    // Reads floorDb/hardLimitDb live on every call (never a cached local),
    // so a binding that calls this re-evaluates when a setting changes.
    function clamp(db) {
        return Math.min(root.hardLimitDb, Math.max(root.floorDb, db));
    }

    // currentDb may be undefined (no amp connected yet): falls back to
    // floorDb.
    function stepped(currentDb, direction) {
        const base = currentDb !== undefined ? currentDb : root.floorDb;
        return root.clamp(base + direction * root.stepDb);
    }

    // Normalized 0..1 position for progress-bar-style displays (OSD/
    // tooltip fill). undefined db (no amp yet) reads as 0.
    function fractionFor(db) {
        if (db === undefined) return 0;
        return Math.min(1, Math.max(0, (db - root.floorDb) / (root.hardLimitDb - root.floorDb)));
    }
}
