// Single shared owner of volume-range configuration (floor/hard-limit/step/
// startup dB), read once from Plasmoid.configuration and forwarded to every
// surface that displays or adjusts volume - the flyout's VolumeBlock, the
// panel icon's own scroll-to-adjust, the OSD toast, and the hover tooltip
// (the latter two indirectly, via CompactRepresentation.qml's volumeFraction).
//
// Same shape as PendingAmpState.qml: a plain QtObject (not `pragma
// Singleton` - no qmldir exists anywhere under contents/ui/, so a true QML
// module singleton isn't set up in this KPackage), instantiated exactly
// once in main.qml and forwarded down via `required property` through
// CompactRepresentation.qml -> FlyoutPopup.qml -> FlyoutContent.qml ->
// VolumeBlock.qml, and directly into CompactRepresentation.qml's own
// stepVolume()/volumeFraction. See CLAUDE.md's "Shared cross-view state"
// note for the general convention this follows.
//
// Deliberately does NOT `import org.kde.plasma.plasmoid` itself - every
// existing file in this codebase that reads Plasmoid.configuration is an
// Item-derived root (main.qml, CompactRepresentation.qml, FlyoutContent.qml,
// FlyoutPopup.qml); the two existing plain QtObjects (Theme.qml,
// PendingAmpState.qml) never do. Rather than be the first to find out
// whether that context property propagates into a bare QtObject file, the
// four properties below are plain `required property real` and get bound
// declaratively from main.qml instead, which is unambiguously proven to
// have Plasmoid.configuration access already.
//
// This replaces two independent hardcoded copies of the same three numbers
// (CompactRepresentation.qml's and FlyoutContent.qml's own local
// volumeCeilingDb/volumeFloorDb/volumeStepDb properties, both -15.0/-60.0
// pre-ConfigDialog literals) with one source of truth, and centralizes the
// actual clamp/step/fraction math too - not just the raw numbers - so the
// three UI surfaces (flyout, OSD, tooltip) can't independently compute
// conflicting results the way the two duplicated copies could have.
import QtQuick

QtObject {
    id: root

    required property real floorDb
    required property real hardLimitDb
    required property real stepDb
    required property real startupVolumeDb
    // Phase 10.1.2: main.xml `chimeEnabled` - the master on/off for the
    // Phase 10.1.0 volume-feedback chime. Carried here rather than in a new
    // settings object because the chime is volume feedback (it fires from
    // the same stepVolume() paths that consume stepDb/clamp() above) and
    // both maybeChime() owners already hold this object; the spike's own
    // deferred-settings note in TODO.md named this file as the forwarding
    // path. Read live by both maybeChime()s - when false they return
    // before building a command, so devialet-chime is never spawned.
    required property bool chimeEnabled

    // Wheel step spacing (2026-09-29): both wheel surfaces (panel icon,
    // flyout slider) turn notches into volume steps at most this often,
    // spaced evenly by WheelStepPacer.qml (see its header for why pacing
    // replaced dropping). Every step spawns a devialet-ctl and a
    // devialet-chime process and makes a D-Bus call from plasmashell's UI
    // thread; unlimited, a free-spinning wheel delivered up to ~300
    // notches/s, which backed the thread up for 2-10 s (widget frozen, then
    // the backlog replayed at once - floor to ceiling in 30 ms, dozens of
    // chimes together). Measured before and after the OSD-echo fix: same
    // freeze, so it was this flood. Started at 40 ms (the MPV scroll
    // script's min_interval_ms); the owner found that slow, then kept 25 ms,
    // then moved to 20 ms (50 steps/s). A constant, not a setting.
    readonly property int wheelStepMinIntervalMs: 20
    // Phase 10.1.3: the chime's sound source (main.xml chimeSourceMode /
    // chimePinnedTheme / chimeSoundFile) plus the pinned theme's resolved
    // file, all bound in main.qml. Paths are RAW here; quoting for the
    // executable engine's /bin/sh -c happens once, in chimeFileArgument()
    // below, via SoundThemes.shellQuote - the same helper ConfigGeneral's
    // Preview uses.
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
    //            hand-edited config): no --file at all, byte for byte the
    //            Phase 10.1.0 command; devialet-chime resolves kdeglobals'
    //            theme itself.
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
    // command strings is fixed at chimeSlots (x the rarely changing --file
    // suffix) for the life of the shell (2026-09-29). Every command the
    // executable engine finishes makes Plasma5Support clear that source
    // name in the `data` map of EVERY executable DataSource in plasmashell;
    // QQmlPropertyMap::clear() creates the key where it is missing and a
    // map can never drop a key, so each never-seen name adds a property to
    // every such map and rebuilds its whole metaobject (stack samples:
    // DataContainer::becameUnused -> DataEngine::removeSource ->
    // QQmlPropertyMap::clear -> QMetaObjectBuilder::toMetaObject in 69 of
    // 77 busy samples). The old ever-increasing --tick made every chime
    // name new: plasmashell's UI thread ended up ~95% busy after a few
    // minutes of scrolling. Passing the dB values (even as a bounded delta,
    // commit 57073de) still left up to 1,296 names, 437 of them reached in
    // one 6-minute session, so the binary now reads target (VolumeDb) and
    // confirmed (VolumeRaw) from the daemon itself in one GetAll
    // (crates/devialet-chime/src/daemon.rs).
    //
    // --tick only has to differ between chimes running at the same time:
    // measured at most 9 at once (170 ms median, 208 ms max each, one per
    // wheelStepMinIntervalMs); the longest chime seen all day (259 ms) / 20 ms
    // needs >= 14, hence 16.
    readonly property int chimeSlots: 16
    function chimeArguments(tick) {
        return " --tick " + (tick % root.chimeSlots);
    }

    // Reads floorDb/hardLimitDb live on every call (never a cached local),
    // so any binding that calls this stays a normal reactive QML binding -
    // changing a ConfigDialog value re-evaluates every consumer immediately.
    function clamp(db) {
        return Math.min(root.hardLimitDb, Math.max(root.floorDb, db));
    }

    // currentDb may be undefined (no amp connected yet) - falls back to
    // floorDb, matching the pre-existing behavior in both call sites this
    // replaces.
    function stepped(currentDb, direction) {
        const base = currentDb !== undefined ? currentDb : root.floorDb;
        return root.clamp(base + direction * root.stepDb);
    }

    // Normalized 0..1 position for progress-bar-style displays (OSD/
    // tooltip fill). undefined db (no amp yet) reads as 0, matching the
    // pre-existing behavior in both call sites this replaces.
    function fractionFor(db) {
        if (db === undefined) return 0;
        return Math.min(1, Math.max(0, (db - root.floorDb) / (root.hardLimitDb - root.floorDb)));
    }
}
