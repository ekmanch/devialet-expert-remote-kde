// Panel icon: click toggles the flyout, middle-click toggles mute, and the
// wheel steps the volume. No hover tooltip (docs/DESIGN.md §7). The icon
// itself is PanelIcon.qml (docs/DESIGN.md §8). Keeps its
// own small D-Bus mirror (AmpIp, DeviceName, ActiveSourceName) and its own
// devialet-ctl DataSource. Cross-view state (volume/mute, volume range,
// transparency, theme, power) comes from main.qml's root-anchored objects,
// forwarded in as required properties and on to the flyout
// (docs/DESIGN.md §3).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as Dbus
import org.kde.plasma.plasma5support as P5Support

MouseArea {
    id: root

    required property PlasmoidItem plasmoidItem
    required property PendingAmpState pendingAmpState
    required property VolumeSettings volumeSettings
    required property TransparencySettings transparencySettings
    // Forwarded to the flyout and the toast.
    required property ThemeSettings themeSettings
    // The amp's PowerState, from main.qml's root mirror. Gates the wheel
    // and middle-click: off or booting, the amp drops volume commands, so
    // no command is sent at all (docs/DESIGN.md §3, known-gotchas.md #10).
    required property string powerState

    // ---- Local mirror of the D-Bus state this icon needs. Volume and
    // mute are read from pendingAmpState instead. All three are plain
    // string scalars, so no unwrap ambiguity and no debounce. ----
    property string ampIp: ""
    property string deviceName: ""
    // Source name for the toast's source row.
    property string activeSourceName: ""

    readonly property string devialetCtlCommand: "devialet-ctl"

    // ---- Volume chime ----
    // One gain-compensated chime per wheel step, only while the PC is the
    // amp's source (Optical 1 - the PC -> HDMI -> TV -> optical path).
    // devialet-chime does the math, reading the target and confirmed dB
    // from the daemon itself.
    readonly property string chimeCommand: "devialet-chime"
    // Round-robin pool of DataSources, so rapid chimes overlap and mix
    // like KDE's own libcanberra volume tone instead of interrupting each
    // other. Tick N uses chimePool[N % length]. `--tick` keeps the command
    // strings of concurrently running chimes distinct (the shared
    // executable engine keys running jobs by command string) while keeping
    // the set of strings fixed: see VolumeSettings.chimeArguments() and
    // docs/DESIGN.md §5.
    readonly property var chimePool: [chimeExec0, chimeExec1, chimeExec2, chimeExec3]
    property int chimeTick: 0

    // Gate on the amp's live broadcast name, trimmed + lowercased (the
    // SourceGlyph.kindFor() keyword-match precedent; never by index - see
    // crates/protocol command.rs). Any other source: no chime at all.
    function isPcSourceActive() {
        return String(root.activeSourceName || "").trim().toLowerCase() === "optical 1";
    }

    function maybeChime(targetDb) {
        // Master toggle (kcfg chimeEnabled). Checked first so an off toggle
        // spawns no devialet-chime process at all.
        if (!root.volumeSettings.chimeEnabled) return;
        if (!root.isPcSourceActive()) return;
        const confirmed = root.pendingAmpState.confirmedVolumeDb;
        if (typeof confirmed !== "number" || typeof targetDb !== "number") return;
        // Chime source (VolumeSettings.chimeFileArgument()): "" in follow
        // mode (no --file); " --file '<path>'" for a pinned theme or a
        // picked file; null when the mode needs a file but none resolves -
        // skip and warn, never silently fall back to another mode.
        const fileArg = root.volumeSettings.chimeFileArgument();
        if (fileArg === null) {
            console.warn("devialet-chime: source mode", root.volumeSettings.chimeSourceMode, "has no resolvable file - skipping");
            return;
        }
        const slot = root.chimeTick % root.chimePool.length;
        // The binary reads target/confirmed from the daemon itself (one
        // GetAll, see crates/devialet-chime/src/daemon.rs), so the command
        // is only `--tick k` - a fixed set of strings. QML's own values are
        // logged as the reference for the notch-vs-read timing comparison.
        const cmd = root.chimeCommand + root.volumeSettings.chimeArguments(root.chimeTick) + fileArg;
        root.chimeTick += 1;
        console.log("devialet-chime[" + slot + "] running:", cmd, "(qml target=" + targetDb.toFixed(1) + " confirmed=" + confirmed.toFixed(1) + ")");
        root.chimePool[slot].connectSource(cmd);
    }

    // The amp name the toast shows.
    readonly property string ampDisplayName: root.deviceName !== "" ? root.deviceName : "Devialet"
    readonly property string toastAmpName: root.ampIp === "" ? "No Amplifier" : root.ampDisplayName

    // 0..1 position of the shared volume for the toast's progress bar
    // and the panel icon. VolumeSettings.fractionFor() is the same math the flyout
    // slider uses, so the two can never disagree about the range.
    readonly property real volumeFraction: root.volumeSettings.fractionFor(root.pendingAmpState.volumeDb)

    function unwrap(prop, fallback) {
        if (prop === undefined || prop === null) return fallback;
        if (typeof prop === "object" && prop.value !== undefined) return prop.value;
        return prop;
    }

    function stepVolume(direction) {
        // Power gate - see `powerState` above. Also guards onWheel below,
        // whose notches all route through here.
        if (root.ampIp === "" || root.powerState !== "On") return;
        // Base is pendingAmpState.volumeDb: notifyVolume() writes it
        // synchronously before its D-Bus call, so a rapid second step
        // accumulates on this one rather than on a stale value.
        const clamped = root.volumeSettings.stepped(root.pendingAmpState.volumeDb, direction);
        // Scrolling while muted unmutes for real (KDE's Audio Devices
        // applet convention): a scroll must be audible at the new volume.
        // One notch sends the unmute command alongside the volume command.
        if (root.pendingAmpState.muted) {
            exec.connectSource(root.devialetCtlCommand + " --ip " + root.ampIp + " mute off");
            root.pendingAmpState.notifyMute(false);
        }
        exec.connectSource(root.devialetCtlCommand + " --ip " + root.ampIp + " volume " + clamped +
            " --hard-limit-db " + root.volumeSettings.hardLimitDb);
        // Tells the daemon, so every surface reading pendingAmpState shows
        // the commanded value before the amp's broadcast confirms it
        // (docs/DESIGN.md §3).
        root.pendingAmpState.notifyVolume(clamped);
        // muted is already false here (notifyMute() writes synchronously),
        // so one showVolume() covers both the unmute and the new volume.
        volumeToast.showVolume(root.toastAmpName, root.activeSourceName, clamped, root.volumeFraction, root.pendingAmpState.muted);
        // One chime per paced step, no debounce (like plasma-pa's own
        // tone). Middle-click mute (toggleMute) deliberately does not chime.
        root.maybeChime(clamped);
    }

    // Middle-click mute. Same logic as the flyout's Mute button, kept
    // separate like stepVolume().
    function toggleMute() {
        // Power gate - same as stepVolume() above.
        if (root.ampIp === "" || root.powerState !== "On") return;
        const newMuted = !root.pendingAmpState.muted;
        exec.connectSource(root.devialetCtlCommand + " --ip " + root.ampIp + " mute " + (newMuted ? "on" : "off"));
        root.pendingAmpState.notifyMute(newMuted);
        volumeToast.showMute(root.toastAmpName, root.activeSourceName, newMuted, root.volumeFraction);
    }

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton) {
            // Left-click only toggles FlyoutPopup. Nothing here sets
            // `plasmoidItem.expanded` (see main.qml on why that is safe
            // even though the shell's activation shortcut can flip it).
            flyoutPopup.visible = !flyoutPopup.visible;
        } else if (mouse.button === Qt.MiddleButton) {
            root.toggleMute();
        }
    }

    // The flyout (see FlyoutPopup.qml). Always instantiated and usually
    // hidden, like volumeToast below.
    FlyoutPopup {
        id: flyoutPopup
        flyoutVisualParent: root
        plasmoidItem: root.plasmoidItem
        // The shared root-anchored objects, forwarded on (docs/DESIGN.md §3).
        pendingAmpState: root.pendingAmpState
        volumeSettings: root.volumeSettings
        transparencySettings: root.transparencySettings
        themeSettings: root.themeSettings
    }

    property int wheelDelta: 0
    // Same pacing as the flyout slider (VolumeBlock.qml) - see
    // WheelStepPacer.qml. Each paced step shows the OSD; a dropped notch
    // shows nothing of its own.
    WheelStepPacer {
        id: wheelPacer
        intervalMs: root.volumeSettings.wheelStepMinIntervalMs
        onStep: (direction) => root.stepVolume(direction)
    }
    function wheelStep(direction) {
        wheelPacer.notch(direction);
    }
    onWheel: wheel => {
        const delta = (wheel.inverted ? -1 : 1) * (wheel.angleDelta.y ? wheel.angleDelta.y : -wheel.angleDelta.x);
        if ((root.wheelDelta > 0 && delta < 0) || (root.wheelDelta < 0 && delta > 0)) {
            root.wheelDelta = 0;
        }
        root.wheelDelta += delta;

        // Magic number 120 for common "one click" - see
        // https://doc.qt.io/qt-6/qml-qtquick-wheelevent.html#angleDelta-prop
        while (root.wheelDelta >= 120) {
            root.wheelDelta -= 120;
            root.wheelStep(1);
        }
        while (root.wheelDelta <= -120) {
            root.wheelDelta += 120;
            root.wheelStep(-1);
        }
    }

    // ---- The icon (docs/DESIGN.md §8) ----
    // The glyph takes the size a Kirigami.Icon filling this cell would
    // paint at, so it matches the neighbouring applets' icons.
    readonly property int glyphSize: Kirigami.Units.iconSizes.roundedIconSize(Math.min(root.width, root.height))

    // With the number shown the cell must be wider than the square the
    // panel gives an applet that states no size. The glyph keeps the
    // square cell's own padding ((height - glyphSize) / 2) on its left and
    // the number gets the same on its right, so the width is the square
    // plus the gap and the number: `height`, never `width`, feeds it. With
    // the number hidden the hints stay unset (-1) and the cell is the
    // panel's default square.
    readonly property real numberedWidth: root.height + panelIcon.implicitWidth - root.glyphSize
    Layout.minimumWidth: panelIcon.numberShown ? root.numberedWidth : -1
    Layout.preferredWidth: panelIcon.numberShown ? root.numberedWidth : -1
    Layout.maximumWidth: panelIcon.numberShown ? root.numberedWidth : -1

    PanelIcon {
        id: panelIcon
        anchors.centerIn: parent
        glyphSize: root.glyphSize
        // Never a hardcoded colour: the panel's own text colour, like a
        // symbolic icon.
        color: Kirigami.Theme.textColor
        style: Plasmoid.configuration.panelIconStyle
        showNumber: Plasmoid.configuration.panelIconShowVolume
        vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        hasAmp: root.ampIp !== ""
        powerState: root.powerState
        muted: root.pendingAmpState.muted
        volumeDb: root.pendingAmpState.volumeDb
        fraction: root.volumeFraction
        floorDb: root.volumeSettings.floorDb
        ceilingDb: root.volumeSettings.hardLimitDb
        // Reduced motion: no booting pulse when the desktop's animations
        // are off (durations are 0 then).
        animate: Kirigami.Units.longDuration > 0
    }

    VolumeToast {
        id: volumeToast
        themeSettings: root.themeSettings
    }

    // OSD for commands from other tools on this PC (e.g. the MPV volume
    // script). PendingAmpState re-emits the daemon's VolumeCommandNotified/
    // MuteCommandNotified minus this widget's own echoes, so stepVolume()/
    // toggleMute() never show twice and the flyout/settings-clamp paths
    // stay OSD-less. The fraction comes from the signal's own dB so it
    // does not depend on PropertiesChanged landing first. No chime: that
    // is a wheel-notch behaviour only.
    Connections {
        target: root.pendingAmpState
        function onExternalVolumeCommand(db) {
            volumeToast.showVolume(root.toastAmpName, root.activeSourceName, db,
                root.volumeSettings.fractionFor(db), root.pendingAmpState.muted);
        }
        function onExternalMuteCommand(muted) {
            volumeToast.showMute(root.toastAmpName, root.activeSourceName, muted, root.volumeFraction);
        }
    }

    // Runs devialet-ctl once per connectSource() call, then disconnects
    // the source (the panel-colorizer RunCommand.qml pattern). Command
    // strings per amp IP: one per volume step and hard limit, plus mute
    // on/off - a small fixed set (docs/DESIGN.md §5).
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-ctl finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    // The chimePool slots (see above). Same shape as `exec`, with a
    // per-slot log prefix for grepping the journal.
    P5Support.DataSource {
        id: chimeExec0
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[0] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: chimeExec1
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[1] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: chimeExec2
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[2] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: chimeExec3
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[3] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    Dbus.Properties {
        id: ampProps
        busType: Dbus.BusType.Session
        service: "com.ekmanch.DevialetRemote"
        path: "/com/ekmanch/DevialetRemote/Amp"
        iface: "com.ekmanch.DevialetRemote.Amp1"

        onRefreshed: {
            root.ampIp = root.unwrap(properties.AmpIp, "");
            root.deviceName = root.unwrap(properties.DeviceName, "");
            root.activeSourceName = root.unwrap(properties.ActiveSourceName, "");
        }

        // VolumeDb/Muted also arrive here but are ignored: this file reads
        // them only through pendingAmpState.
        onPropertiesChanged: (interfaceName, changed, invalidated) => {
            if ("AmpIp" in changed) root.ampIp = root.unwrap(changed.AmpIp, root.ampIp);
            if ("DeviceName" in changed) root.deviceName = root.unwrap(changed.DeviceName, root.deviceName);
            if ("ActiveSourceName" in changed) root.activeSourceName = root.unwrap(changed.ActiveSourceName, root.activeSourceName);
        }
    }
}
