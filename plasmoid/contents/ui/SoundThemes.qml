// The one place that knows how installed sound themes are found, named
// and resolved to the file devialet-chime plays, so the widget resolves a
// pinned theme with the same code the settings dialog lists it with.
// main.qml instantiates one for VolumeSettings.chimePinnedThemePath and
// ConfigGeneral.qml its own. Per-file instantiation like Theme.qml, not
// root-anchored: the data comes from disk, so the instances cannot
// diverge.
//
// Plain QtObject (no qmldir/singleton in this KPackage) holding its
// P5Support.DataSource as an object-typed property, the way Theme.qml
// holds its FontLoaders. Deliberately does not import
// org.kde.plasma.plasmoid.
import QtQuick
import org.kde.plasma.plasma5support as P5Support

QtObject {
    id: root

    // [{id, name, path}] - every installed sound theme that actually has
    // the one file the chime plays (see scanCommand below). id = the
    // sound-theme directory name (what kdeglobals stores, what
    // devialet-chime reads, what main.xml chimePinnedTheme persists);
    // name = the display name System Settings shows.
    property var themes: []
    // Raw kdeglobals [Sounds] Theme value; "" until read, or when unset.
    property string desktopTheme: ""

    // Theme enumeration. KDE's Sound Theme KCM does this in C++
    // (kcm_soundtheme.cpp, loadThemes()) and no QML type lists themes for
    // a plasmoid, so this is a one-shot /bin/sh walk of the same
    // directories in the same precedence order ($XDG_DATA_HOME, then each
    // $XDG_DATA_DIRS entry), emitting "id<TAB>name<TAB>path" per theme,
    // deduped by id (first wins). Two filters: index.theme must exist (the
    // KCM's validity rule, which drops e.g. sounds/alsa), and
    // stereo/audio-volume-change.oga must exist - the exact file
    // devialet-chime's theme.rs plays, with no Inherits= walk, so a theme
    // that only inherits the sound is excluded. `name` is index.theme's
    // localized Name= via kreadconfig6, defaulting to the directory id
    // (the KCM's nameFor() fallback).
    readonly property string scanCommand:
        "IFS=:; for base in \"${XDG_DATA_HOME:-$HOME/.local/share}\" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do "
        + "for dir in \"$base\"/sounds/*/; do dir=${dir%/}; id=${dir##*/}; "
        + "[ -f \"$dir/index.theme\" ] || continue; "
        + "[ -f \"$dir/stereo/audio-volume-change.oga\" ] || continue; "
        + "name=$(kreadconfig6 --file \"$dir/index.theme\" --group \"Sound Theme\" --key Name --default \"$id\"); "
        + "printf '%s\\t%s\\t%s\\n' \"$id\" \"$name\" \"$dir/stereo/audio-volume-change.oga\"; "
        + "done; done | awk -F'\\t' '!seen[$1]++'"

    // The desktop's configured sound theme (kdeglobals [Sounds] Theme, the
    // key devialet-chime's theme.rs reads), shown as the dialog's "System
    // theme" value. Read via kreadconfig6, as no KConfig QML reader
    // exists. Empty output = key unset.
    readonly property string desktopThemeCommand:
        "kreadconfig6 --file kdeglobals --group Sounds --key Theme"

    function scan() {
        root.probe.connectSource(root.scanCommand);
    }

    function refreshDesktopTheme() {
        root.probe.connectSource(root.desktopThemeCommand);
    }

    function applyScan(stdout) {
        const themes = [];
        const lines = String(stdout || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const fields = lines[i].split("\t");
            if (fields.length < 3 || fields[0] === "") continue;
            const id = fields[0];
            let name = fields[1] || id;
            // Special case copied from KDE's Sound Theme KCM, not the
            // sound-theme spec: the fallback "freedesktop" theme calls
            // itself Name=Default, which reads like the system default,
            // so the KCM shows it as "FreeDesktop". Reproduced so the
            // dropdown matches System Settings.
            if (id === "freedesktop") name = "FreeDesktop";
            themes.push({ id: id, name: name, path: fields[2] });
        }
        // kcm_soundtheme.cpp:163-173 - sort by display name, keep the
        // freedesktop fallback last.
        themes.sort(function (a, b) {
            if (a.id === "freedesktop") return 1;
            if (b.id === "freedesktop") return -1;
            return a.name.localeCompare(b.name);
        });
        root.themes = themes;
        // No "unknown pinned id -> first entry" correction: the pinned id
        // is a persisted cfg_ value, and rewriting it on a scan would
        // dirty Apply on open whenever the stored theme isn't installed.
        // An unknown id shows as its raw id (nameFor) and resolves to ""
        // (pathFor), so Preview disables and maybeChime() skips with a
        // warning.
    }

    function entry(id) {
        for (let i = 0; i < root.themes.length; i++) {
            if (root.themes[i].id === id) return root.themes[i];
        }
        return null;
    }

    // Like the KCM's nameFor(): display name, or the raw id for anything
    // not in the list.
    function nameFor(id) {
        const e = root.entry(id);
        return e ? e.name : id;
    }

    // The theme's audio-volume-change.oga, or "" when the id isn't an
    // installed theme that has one.
    function pathFor(id) {
        const e = root.entry(id);
        return e ? e.path : "";
    }

    // Port of devialet-chime's theme.rs resolve(): the configured theme,
    // then ocean, then freedesktop - first one whose audio-volume-
    // change.oga exists (themes only holds those). null when none.
    function resolveFollow() {
        const order = [root.desktopTheme !== "" ? root.desktopTheme : "ocean", "ocean", "freedesktop"];
        for (let i = 0; i < order.length; i++) {
            const e = root.entry(order[i]);
            if (e) return e;
        }
        return null;
    }

    function followDisplayName() {
        const e = root.resolveFollow();
        if (e) return e.name;
        return root.desktopTheme !== "" ? root.desktopTheme : "ocean";
    }

    // Single-quote a path for the executable engine's `/bin/sh -c`. The
    // one quoting helper for both the dialog's Preview and maybeChime()'s
    // --file argument.
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // One-shot probes (theme scan + kdeglobals read), dispatched on the
    // source string, then disconnected. Two fixed command strings.
    readonly property P5Support.DataSource probe: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            const code = data["exit code"];
            if (code !== 0) {
                console.log("[SoundThemes] probe failed - exit code:", code, "stderr:", data["stderr"], "command:", source);
            }
            if (source === root.scanCommand) {
                root.applyScan(data["stdout"]);
            } else if (source === root.desktopThemeCommand) {
                root.desktopTheme = String(data["stdout"] || "").trim();
            }
            disconnectSource(source);
        }
    }
}
