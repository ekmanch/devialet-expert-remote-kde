pragma ComponentBehavior: Bound

// The "General" settings page (docs/DESIGN.md §4): the brand header,
// then SectionLabel / SettingsRow items in one flat ColumnLayout, like the
// mockup's flat DOM. Not Kirigami.FormLayout: its label column does not
// fit this row shape.
//
// Root is KCM.SimpleKCM, a plain Kirigami.ScrollablePage meant for
// arbitrary content, so no Breeze form styling fights the custom look.
// org.kde.plasma.plasmoid is unused here but imported, as in every
// working precedent. This page makes no D-Bus calls.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
// Volume Feedback section: the executable engine (P5Support) runs the
// Preview, the Browse dialog is QtQuick.Dialogs in a Loader (as in KDE's
// kcm_soundtheme), and StandardPaths (QtCore) gives its start folder.
import QtCore
import QtQuick.Dialogs as QtDialogs
import org.kde.plasma.plasma5support as P5Support
import "../ui" as Ui

KCM.SimpleKCM {
    id: root

    readonly property Ui.Theme theme: Ui.Theme {}
    // The page's palette, forwarded to every settings component below.
    // The page follows the desktop's colour scheme (pageScheme), not the
    // widget's Theme setting, and cannot reach main.qml's ThemeSettings.
    readonly property Ui.ColorPalette darkColors: Ui.DarkPalette {}
    readonly property Ui.ColorPalette lightColors: Ui.LightPalette {}
    readonly property Ui.ColorPalette colors: root.pageScheme.dark ? root.darkColors : root.lightColors

    // Light: pure white like the mockup (`--win-bg:#ffffff`, configDialog
    // mockup v30 :34), not the scheme's window colour (#eff0f1 under Breeze
    // Light). Dark keeps the scheme's colour. Plasma's header strip and
    // button bar around the page stay in the scheme's colour.
    background: Rectangle {
        color: root.colors.isLight ? root.colors.surface : Kirigami.Theme.backgroundColor
    }

    // The desktop's colour scheme as seen from this dialog; also what the
    // Follow-system status line reports.
    readonly property Ui.SystemScheme pageScheme: Ui.SystemScheme {
        context: "config page"
    }

    // cfg_<entryName> is the Plasma convention: the shell's
    // AppletConfiguration.qml pushes the stored KConfig value in on open,
    // reads it back on Apply/OK, and its cfg_*Changed dirty-check enables
    // Apply.
    property real cfg_volumeStepDb: 1.0
    // KCMUtils' ConfigModule loader expects a cfg_<name>Default companion
    // for every cfg_<name> (otherwise it logs "does not have a property
    // called cfg_<name>Default"). All come from shippedDefaults below.
    readonly property real cfg_volumeStepDbDefault: root.shippedDefaults.volumeStepDb
    readonly property var stepValues: [0.5, 1, 2]

    // main.xml `theme`: the widget's colour theme for the flyout, OSD and
    // tooltip (read by ThemeSettings.qml). Order matches the segments:
    // Dark, Light, Follow system.
    readonly property var themeModes: ["dark", "light", "system"]
    property string cfg_theme: "system"
    readonly property string cfg_themeDefault: root.shippedDefaults.theme

    // Appearance: see main.xml and TransparencySettings.qml.
    property bool cfg_transparencyEnabled: true
    property int cfg_transparencyPercent: 90
    readonly property bool cfg_transparencyEnabledDefault: root.shippedDefaults.transparencyEnabled
    readonly property int cfg_transparencyPercentDefault: root.shippedDefaults.transparencyPercent

    // Volume limits (main.xml volumeFloorDb/hardLimitDb/startupVolumeDb).
    // -96..0 dB is the Expert Pro range, used by every DbStepper below.
    property real cfg_volumeFloorDb: -50.0
    property real cfg_hardLimitDb: -10.0
    property real cfg_startupVolumeDb: -40.0
    readonly property real cfg_volumeFloorDbDefault: root.shippedDefaults.volumeFloorDb
    readonly property real cfg_hardLimitDbDefault: root.shippedDefaults.hardLimitDb
    readonly property real cfg_startupVolumeDbDefault: root.shippedDefaults.startupVolumeDb
    readonly property real dbRangeMin: -96.0
    readonly property real dbRangeMax: 0.0

    // Floor and hard limit stay strictly ordered (floor < hard limit; an
    // empty range is meaningless), at least one stepper increment apart.
    // Named so both steppers and this gap agree by construction.
    readonly property real limitStepDb: 1.0

    // Self-heal, run on every change to either limit. User steps cannot
    // produce an invalid pair (the steppers' from/to bindings below), and
    // Defaults writes in a widen-first order, so this only catches other
    // in-process writes. Resets the pair to -40/-39.
    //
    // It cannot catch an external edit to the config file while
    // plasmashell runs: Plasmoid.configuration is one KConfigPropertyMap
    // per process that reads the file once, at construction, and never
    // again until plasmashell restarts. main.qml's on-load check covers a
    // bad pair already on disk.
    function healLimitOrdering() {
        if (root.cfg_volumeFloorDb >= root.cfg_hardLimitDb) {
            console.log("[ConfigGeneral] floor/hardLimit invalid (" + root.cfg_volumeFloorDb +
                        " >= " + root.cfg_hardLimitDb + ") - self-healing to -40.0/-39.0");
            root.cfg_volumeFloorDb = -40.0;
            root.cfg_hardLimitDb = -39.0;
        }
    }

    onCfg_volumeFloorDbChanged: root.healLimitOrdering()
    onCfg_hardLimitDbChanged: root.healLimitOrdering()

    // Mirrors main.xml's <default> entries; feeds the cfg_<name>Default
    // properties and the Defaults button. Nothing generates this from
    // main.xml, so update both together.
    readonly property var shippedDefaults: ({
        theme: "system",
        transparencyEnabled: true,
        transparencyPercent: 90,
        volumeStepDb: 1.0,
        startupVolumeDb: -40.0,
        volumeFloorDb: -50.0,
        hardLimitDb: -10.0,
        chimeEnabled: true,
        chimeSourceMode: "follow",
        chimePinnedTheme: "ocean",
        chimeSoundFile: "",
        // Not a main.xml entry (systemd's enablement is the storage) but
        // still the page's default: install.sh enables the unit. Defaults
        // resets it through the same pending-then-Apply/OK path as a click.
        launchAtLogin: true
    })

    // ---- Chime ----
    // main.xml chimeEnabled / chimeSourceMode / chimePinnedTheme /
    // chimeSoundFile. These cfg_ values are the dialog's live selection
    // (persisted only on Apply/OK), which is what Preview must play. The
    // widget reads them through VolumeSettings.qml (bound in main.qml).
    property bool cfg_chimeEnabled: true
    readonly property bool cfg_chimeEnabledDefault: root.shippedDefaults.chimeEnabled

    readonly property var chimeSourceModes: ["follow", "theme", "file"]
    property string cfg_chimeSourceMode: "follow"
    // Sound-theme directory id (what kdeglobals stores and what
    // devialet-chime reads), never the display name.
    property string cfg_chimePinnedTheme: "ocean"
    // "" = nothing picked yet (main.xml has no other "unset" convention).
    property string cfg_chimeSoundFile: ""
    readonly property string cfg_chimeSourceModeDefault: root.shippedDefaults.chimeSourceMode
    readonly property string cfg_chimePinnedThemeDefault: root.shippedDefaults.chimePinnedTheme
    readonly property string cfg_chimeSoundFileDefault: root.shippedDefaults.chimeSoundFile
    property int chimePreviewTick: 0

    // Theme enumeration, the kdeglobals read, follow-mode resolution and
    // shell quoting live in ../ui/SoundThemes.qml, so the widget resolves
    // a pinned theme with the same code this dialog lists it with. Own
    // instance, like Theme.qml.
    readonly property Ui.SoundThemes soundThemes: Ui.SoundThemes {}

    // ---- Launch at login ----
    // No cfg_ property and no main.xml entry: systemd's enablement of
    // devialet-remote-daemon.service is the storage. ../ui/DaemonAutostart.qml
    // runs `systemctl --user is-enabled` on every page open (the page is
    // re-created per open, so no polling) and enable/disable on Apply/OK,
    // through the shell's two undocumented page hooks (docs/DESIGN.md §4):
    //   - `unsavedChanges`: enables Apply and triggers the discard prompt.
    //   - `saveConfig()`: called on Apply and OK before the cfg_* copy-back,
    //     so it must not touch any cfg_ value.
    // OK closes the dialog at once, so an async failure there is only
    // logged and re-queried on the next open. Apply keeps the dialog open:
    // a failed write shows its note and the toggle reverts to the
    // re-queried state.
    readonly property Ui.DaemonAutostart daemonAutostart: Ui.DaemonAutostart {}
    // The toggle's pending value: re-derived from every completed query
    // (dialog open, and the re-query after every write), then changed by
    // clicks.
    property bool launchDesired: false
    property bool unsavedChanges: root.daemonAutostart.toggleable
        && !root.daemonAutostart.writing
        && root.launchDesired !== (root.daemonAutostart.state === "enabled")

    // Every completed query re-derives the switch, including the
    // non-toggleable outcomes; otherwise a failed write would leave the
    // clicked value showing next to a note claiming the real state.
    readonly property Connections daemonAutostartSync: Connections {
        target: root.daemonAutostart
        function onStateChanged() {
            if (root.daemonAutostart.state !== "querying") {
                root.launchDesired = root.daemonAutostart.state === "enabled";
            }
        }
    }

    function saveConfig() {
        if (root.unsavedChanges) {
            root.daemonAutostart.apply(root.launchDesired);
        }
    }

    // The status/error line under the Launch at login row. "" = nothing
    // to say (enabled/disabled with no failed write, or still querying).
    function launchAtLoginNote() {
        const d = root.daemonAutostart;
        if (d.lastWriteFailed) {
            return "Couldn't change it — " + d.writeDetail + ". Showing the real current state.";
        }
        switch (d.state) {
        case "not-found":
            return "Service not installed — expected at ~/.config/systemd/user/" + d.unitName + " (README: Daemon autostart)";
        case "unsupported":
            return "Unit is " + d.token + " — can't be toggled from here";
        case "error":
            return "Couldn't query systemd — " + d.detail;
        default:
            return "";
        }
    }

    function escapeStyledText(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function chimeFileBaseName() {
        const p = root.cfg_chimeSoundFile;
        return p.substring(p.lastIndexOf("/") + 1);
    }

    // What Preview plays for the CURRENT dialog selection - the cfg_
    // values, applied or not. Same three branches maybeChime() takes on
    // the widget side via VolumeSettings.chimeFileArgument().
    function chimePreviewPath() {
        if (root.cfg_chimeSourceMode === "follow") {
            const entry = root.soundThemes.resolveFollow();
            return entry ? entry.path : "";
        }
        if (root.cfg_chimeSourceMode === "theme") {
            return root.soundThemes.pathFor(root.cfg_chimePinnedTheme);
        }
        return root.cfg_chimeSoundFile;
    }

    // Mockup setChimeSource() (line 634-640): switch variant, close the
    // theme dropdown if it was open.
    function setChimeSourceMode(mode) {
        root.cfg_chimeSourceMode = mode;
        themeDropdown.close();
    }

    // Preview: `paplay --volume=65536` (PA_VOLUME_NORM, unity: the sound's
    // own level, which is what devialet-chime plays at delta 0 dB /
    // headroom 0). Not routed through devialet-chime: its gain
    // compensation only means something during a scroll gesture.
    // DEVIALET_PREVIEW_TICK=<n> is a no-op environment assignment that
    // keeps overlapping presses' command strings distinct (the shared
    // executable engine keys jobs by command string). It wraps at 16, so
    // this produces at most 16 strings per file (docs/DESIGN.md §5).
    function previewChime() {
        const path = root.chimePreviewPath();
        if (path === "") return;
        const cmd = "DEVIALET_PREVIEW_TICK=" + (root.chimePreviewTick % 16)
            + " paplay --volume=65536 " + root.soundThemes.shellQuote(path);
        root.chimePreviewTick += 1;
        console.log("[ConfigGeneral] chime preview running:", cmd);
        previewExec.connectSource(cmd);
    }

    // Re-read the desktop theme each time "System theme" is selected: a
    // cheap refresh without polling. Also read once at page load below.
    onCfg_chimeSourceModeChanged: {
        if (root.cfg_chimeSourceMode === "follow") root.soundThemes.refreshDesktopTheme();
    }

    Component.onCompleted: {
        root.soundThemes.scan();
        root.soundThemes.refreshDesktopTheme();
        root.daemonAutostart.refresh();
    }

    P5Support.DataSource {
        id: previewExec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("[ConfigGeneral] chime preview finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    // Browse: QtQuick.Dialogs FileDialog (the native KDE dialog under
    // plasmashell's platform theme), created lazily and torn down after
    // use via a Loader, as in KDE's kcm_soundtheme main.qml.
    Loader {
        id: chimeFileDialogLoader
        active: false
        sourceComponent: QtDialogs.FileDialog {
            title: "Choose Chime Sound"
            fileMode: QtDialogs.FileDialog.OpenFile
            // The mockup's .wav/.ogg/.mp3, widened to what paplay decodes
            // via libsndfile (.oga is what installed themes ship).
            nameFilters: ["Audio files (*.oga *.ogg *.opus *.wav *.flac *.mp3)", "All files (*)"]
            currentFolder: root.cfg_chimeSoundFile !== ""
                ? "file://" + root.cfg_chimeSoundFile.substring(0, root.cfg_chimeSoundFile.lastIndexOf("/"))
                : StandardPaths.writableLocation(StandardPaths.HomeLocation)
            Component.onCompleted: open()
            onAccepted: {
                // selectedFile is a file:// URL; the chip and paplay want
                // a plain local path.
                root.cfg_chimeSoundFile = decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""));
                chimeFileDialogLoader.active = false;
            }
            onRejected: chimeFileDialogLoader.active = false
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        // Spacing per the mockup's `.brand-header` (gap 9px, margin-bottom
        // 22px, configDialog mockup v30 :235) and `.brand-sub` (4px above,
        // letter-spacing 0.2em, :257).
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 22
            spacing: 9

            // The app icon's ring + disk (BrandMark.qml).
            BrandMark { colors: root.colors }

            ColumnLayout {
                spacing: 4

                Label {
                    text: "Devialet Expert Remote"
                    font.family: root.theme.fontDisplay
                    font.weight: Font.DemiBold
                    font.pixelSize: 17
                    color: root.colors.text
                }

                Label {
                    text: "WIDGET SETTINGS"
                    font.family: root.theme.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: root.colors.textFaint
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ---- Appearance ----
        SectionLabel { colors: root.colors; text: "Appearance"; first: true }

        // Theme (configDialog mockup v2 :574-584). Recolours the flyout,
        // hover tooltip and OSD, not this page.
        SettingsRow {
            colors: root.colors
            name: "Theme"
            desc: "Colors for the popup, hover tooltip and volume overlay"

            SegmentedControl {
                id: themeSegmented
                colors: root.colors
                labels: ["Dark", "Light", "Follow system"]
                activeIndex: root.themeModes.indexOf(root.cfg_theme)
                onPicked: index => root.cfg_theme = root.themeModes[index]
            }
        }

        // Follow-system status line (configDialog mockup v2 :585-590,
        // `.kcm-sub-row` padding 10px 2px 14px + border-bottom). Shown while
        // Follow system is selected, before Apply; the value is this
        // dialog's reading of the XDG portal (pageScheme), the same value
        // the widget follows.
        ColumnLayout {
            id: themeFollowStatus
            objectName: "themeFollowStatus"
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 0
            visible: root.cfg_theme === "system"

            RowLayout {
                Layout.leftMargin: 2
                spacing: 9

                StatusDot {
                    Layout.alignment: Qt.AlignVCenter
                    colors: root.colors
                }

                // Gold-gradient value in light (FollowStatusText.qml).
                FollowStatusText {
                    objectName: "themeFollowLabel"
                    Layout.alignment: Qt.AlignVCenter
                    colors: root.colors
                    prefix: "Following your desktop's color scheme — currently "
                    value: root.pageScheme.dark ? "Dark" : "Light"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.preferredHeight: 1
                color: root.colors.divider
            }
        }

        SettingsRow {
            colors: root.colors
            name: "Transparency"
            desc: "Let the desktop show through the panel"

            SettingsSwitch {
                id: transparencySwitch
                colors: root.colors
                checked: root.cfg_transparencyEnabled
                // Stateless switch: store the value here (SettingsSwitch.qml).
                onToggled: (checked) => root.cfg_transparencyEnabled = checked
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: -6
            Layout.bottomMargin: 8
            spacing: 10
            // Mockup's .kcm-sub-row.disabled - dims/disables the slider
            // whenever Transparency is off, matching toggleTransSub().
            opacity: transparencySwitch.checked ? 1.0 : 0.35
            enabled: transparencySwitch.checked

            // Full 0..100 range, step 1, as mocked. Below ~50% the panel
            // tint all but disappears while the opaque chrome stays solid.
            Slider {
                id: transparencySlider
                Layout.fillWidth: true
                // Widens the hit area beyond the painted 4px track / 15px
                // handle: a Slider's interaction region is its bounds, not
                // what it paints. Same 26px as VolumeBlock.qml's slider.
                implicitHeight: 26
                from: 0
                to: 100
                stepSize: 1
                value: root.cfg_transparencyPercent
                onMoved: root.cfg_transparencyPercent = value

                // Same track/handle styling as VolumeBlock.qml's slider,
                // inline since this is the page's only slider.
                background: Rectangle {
                    x: transparencySlider.leftPadding
                    y: transparencySlider.topPadding + transparencySlider.availableHeight / 2 - height / 2
                    implicitHeight: 4
                    width: transparencySlider.availableWidth
                    height: 4
                    radius: 999
                    color: root.colors.surface3

                    Rectangle {
                        width: transparencySlider.visualPosition * parent.width
                        height: parent.height
                        radius: 999
                        // accentFill (copper in dark, flat gold in light),
                        // as the flyout's slider.
                        color: root.colors.accentFill
                    }
                }

                // The dark disc or the light gold sphere (15 px, 3 px halo;
                // configDialog mockup v30 :87-88), as in VolumeBlock.qml.
                handle: Item {
                    x: transparencySlider.leftPadding + transparencySlider.visualPosition * (transparencySlider.availableWidth - width)
                    y: transparencySlider.topPadding + transparencySlider.availableHeight / 2 - height / 2
                    width: 15
                    height: 15

                    Rectangle {
                        anchors.fill: parent
                        visible: !root.colors.isLight
                        radius: 999
                        color: root.colors.copperBright
                    }
                    Loader {
                        anchors.fill: parent
                        active: root.colors.isLight
                        sourceComponent: Ui.GoldSphere {
                            diameter: 15
                            haloWidth: 3
                            shadowColor: "#6e480a"
                            shadowVerticalOffset: 1
                            shadowBlur: 0.2
                        }
                    }
                }

                // Scroll-to-adjust, as VolumeBlock.qml's slider:
                // Qt.NoButton lets press/drag reach the Slider, deltas
                // accumulate in 120-unit notches (org.kde.desktop's
                // Slider.qml convention), one notch = one stepSize, and
                // scroll up increases.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton

                    property int wheelDelta: 0

                    onWheel: (wheel) => {
                        if (transparencySlider.pressed) return;

                        const delta = (wheel.angleDelta.y || -wheel.angleDelta.x) * (wheel.inverted ? -1 : 1);
                        wheelDelta += delta;
                        while (wheelDelta >= 120) {
                            wheelDelta -= 120;
                            root.cfg_transparencyPercent = Math.min(transparencySlider.to, root.cfg_transparencyPercent + transparencySlider.stepSize);
                        }
                        while (wheelDelta <= -120) {
                            wheelDelta += 120;
                            root.cfg_transparencyPercent = Math.max(transparencySlider.from, root.cfg_transparencyPercent - transparencySlider.stepSize);
                        }
                    }
                }
            }

            Label {
                text: Math.round(transparencySlider.value) + "%"
                font.family: root.theme.fontMono
                font.pixelSize: 11
                // Neutral in light (mockup v30 :108).
                color: root.colors.controlValueText
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
            }
        }

        // ---- Volume ----
        SectionLabel { colors: root.colors; text: "Volume" }

        SettingsRow {
            colors: root.colors
            name: "Volume Step Size"
            desc: "Change how large one increment change in volume is"

            // activeIndex is derived from cfg_volumeStepDb, so it follows
            // both the stored value and a click.
            SegmentedControl {
                id: stepSegmented
                colors: root.colors
                labels: ["0.5 dB", "1 dB", "2 dB"]
                activeIndex: root.stepValues.indexOf(root.cfg_volumeStepDb)
                onPicked: index => root.cfg_volumeStepDb = root.stepValues[index]
            }
        }

        SettingsRow {
            colors: root.colors
            name: "Startup / Source-Switch Volume"
            desc: "Default volume at startup and when source is changed"

            DbStepper {
                colors: root.colors
                value: root.cfg_startupVolumeDb
                from: root.dbRangeMin
                to: root.dbRangeMax
                onStepped: (value) => root.cfg_startupVolumeDb = value
            }
        }

        // ---- Volume Limits ----
        // Steppers rather than a slider: two interdependent thresholds on
        // one track are easy to mis-drag (mockup v13 legend). Floor comes
        // before ceiling, as in the mockup.
        SectionLabel { colors: root.colors; text: "Volume Limits" }

        SettingsRow {
            colors: root.colors
            name: "Volume Floor"
            desc: "Lowest volume possible to set"

            DbStepper {
                colors: root.colors
                value: root.cfg_volumeFloorDb
                from: root.dbRangeMin
                // Capped one step below the hard limit, not at dbRangeMax:
                // "+" disables at the cap and clamp() lands exactly on it.
                to: root.cfg_hardLimitDb - root.limitStepDb
                stepDb: root.limitStepDb
                onStepped: (value) => root.cfg_volumeFloorDb = value
            }
        }

        SettingsRow {
            colors: root.colors
            name: "Volume Ceiling"
            desc: "Highest volume possible to set"
            showDivider: false

            DbStepper {
                colors: root.colors
                value: root.cfg_hardLimitDb
                // Mirror of the floor: capped one step above it.
                from: root.cfg_volumeFloorDb + root.limitStepDb
                to: root.dbRangeMax
                stepDb: root.limitStepDb
                onStepped: (value) => root.cfg_hardLimitDb = value
            }
        }

        // ---- Volume Feedback ----
        // The v16 mockup's Volume Feedback section (lines 472-541): the
        // master toggle, then a sub-section (#chimeSub) it dims and
        // disables like the Transparency sub-row (opacity 0.35 +
        // enabled:false, `.kcm-sub-row.disabled`), holding the source
        // segmented control and the one visible variant block.
        SectionLabel { colors: root.colors; text: "Volume Feedback" }

        SettingsRow {
            colors: root.colors
            name: "Volume Feedback Chime"
            desc: "Plays a short tone on each scroll tick, matching the volume you're setting"

            SettingsSwitch {
                id: chimeSwitch
                colors: root.colors
                checked: root.cfg_chimeEnabled
                onToggled: (checked) => root.cfg_chimeEnabled = checked
            }
        }

        // Mockup .kcm-sub-row{padding:8px 2px 4px} - the 2px side inset
        // is not reproduced (nothing here is flush with the page edge).
        ColumnLayout {
            id: chimeSub
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 4
            spacing: 0
            opacity: chimeSwitch.checked ? 1.0 : 0.35
            enabled: chimeSwitch.checked
            // A dropdown left open while the section is disabled would
            // still be interactive (the Popup lives in the window
            // overlay, outside this item's enabled/opacity), so close it.
            onEnabledChanged: if (!enabled) themeDropdown.close()

            // Mockup line 481: .kcm-row with border-bottom:none and
            // padding-top:0.
            SettingsRow {
                colors: root.colors
                name: "Chime Sound"
                desc: "Which sound plays on each tick"
                showDivider: false
                topPadding: 0

                // Three string-valued modes.
                SegmentedControl {
                    id: chimeSegmented
                    colors: root.colors
                    labels: ["System theme", "Choose theme", "Custom file"]
                    activeIndex: root.chimeSourceModes.indexOf(root.cfg_chimeSourceMode)
                    onPicked: index => root.setChimeSourceMode(root.chimeSourceModes[index])
                }
            }

            // Mockup .chime-source-block{padding:8px 2px 4px}; exactly one
            // .chime-source-variant is shown (flex, space-between, gap
            // 20, padding-top 12) - the other two are display:none, i.e.
            // visible:false here, taking no layout space.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 4
                spacing: 0

                // ===== mode: follow the desktop's own configured theme =====
                // A read-only status line, deliberately NOT a control
                // (mockup CSS comment, lines 245-247): this mode has
                // nothing to configure, it tracks kdeglobals live.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    spacing: 20
                    visible: root.cfg_chimeSourceMode === "follow"

                    // .theme-follow-status: dot (its box-shadow glow not
                    // drawn, as in AmpHeader.qml) + mono status text.
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 9

                        StatusDot {
                            Layout.alignment: Qt.AlignVCenter
                            colors: root.colors
                        }

                        FollowStatusText {
                            Layout.alignment: Qt.AlignVCenter
                            colors: root.colors
                            prefix: "Following your desktop's sound theme — currently "
                            value: root.soundThemes.followDisplayName()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ChimeIconButton {
                        colors: root.colors
                        kind: "play"
                        tooltip: "Preview"
                        enabled: root.chimePreviewPath() !== ""
                        onClicked: root.previewChime()
                    }
                }

                // ===== mode: pin to one specific installed theme =====
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    spacing: 20
                    visible: root.cfg_chimeSourceMode === "theme"

                    Label {
                        Layout.maximumWidth: 260
                        Layout.alignment: Qt.AlignVCenter
                        text: "Always use this theme's tone, regardless of your desktop setting"
                        font.pixelSize: 11
                        color: root.colors.textFaint
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillWidth: true }

                    // .file-picker-row: gap 8.
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8

                        ThemeDropdown {
                            id: themeDropdown
                            colors: root.colors
                            themes: root.soundThemes.themes
                            currentId: root.cfg_chimePinnedTheme
                            onThemeChosen: (id) => root.cfg_chimePinnedTheme = id
                        }

                        ChimeIconButton {
                            colors: root.colors
                            kind: "play"
                            tooltip: "Preview"
                            enabled: root.chimePreviewPath() !== ""
                            onClicked: root.previewChime()
                        }
                    }
                }

                // ===== mode: any arbitrary file =====
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    spacing: 20
                    visible: root.cfg_chimeSourceMode === "file"

                    Label {
                        Layout.maximumWidth: 260
                        Layout.alignment: Qt.AlignVCenter
                        text: "Any sound file on disk"
                        font.pixelSize: 11
                        color: root.colors.textFaint
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillWidth: true }

                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8

                        // .file-picker-field: the filename chip (mono
                        // 11px, max-width 170, ellipsis; full path as its
                        // tooltip, the mockup's title=). With no file
                        // picked ("") it shows a dimmed "No file chosen"
                        // instead of the mockup's placeholder filename,
                        // and Preview stays disabled.
                        Rectangle {
                            id: chimeFileChip
                            Layout.maximumWidth: 170
                            implicitWidth: chimeFileLabel.implicitWidth + 20
                            implicitHeight: chimeFileLabel.implicitHeight + 12
                            radius: root.theme.radiusSm
                            color: root.colors.surface
                            border.width: 1
                            border.color: root.colors.controlBorder
                            // Light-theme card shadow.
                            Ui.CardShadow { colors: root.colors; radius: parent.radius }

                            readonly property bool hasFile: root.cfg_chimeSoundFile !== ""

                            Label {
                                id: chimeFileLabel
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: Text.AlignVCenter
                                text: chimeFileChip.hasFile ? root.chimeFileBaseName() : "No file chosen"
                                font.family: root.theme.fontMono
                                font.pixelSize: 11
                                color: chimeFileChip.hasFile ? root.colors.textDim : root.colors.textFaint
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: chimeFileChipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            ToolTip.text: root.cfg_chimeSoundFile
                            ToolTip.visible: chimeFileChip.hasFile && chimeFileChipArea.containsMouse
                            ToolTip.delay: 500
                        }

                        ChimeIconButton {
                            colors: root.colors
                            kind: "browse"
                            tooltip: "Browse…"
                            onClicked: chimeFileDialogLoader.active = true
                        }

                        ChimeIconButton {
                            colors: root.colors
                            kind: "play"
                            tooltip: "Preview"
                            enabled: root.cfg_chimeSoundFile !== ""
                            onClicked: root.previewChime()
                        }
                    }
                }
            }
        }

        // ---- Startup ----
        SectionLabel { colors: root.colors; text: "Startup" }

        SettingsRow {
            colors: root.colors
            name: "Launch at Login"
            desc: "Automatically start the daemon used for UDP communication to amplifier"
            // The switch shows launchDesired (systemd's answer, or an
            // unapplied click) and is clickable only while systemd reports
            // plain enabled/disabled and no write is in flight. Every other
            // outcome disables it and says why in the note, so a failure
            // never looks like an unchecked toggle.
            note: root.launchAtLoginNote()

            SettingsSwitch {
                colors: root.colors
                checked: root.launchDesired
                enabled: root.daemonAutostart.toggleable && !root.daemonAutostart.writing
                onToggled: (checked) => root.launchDesired = checked
            }
        }

        // ---- Reset ----
        // Defaults lives in the page: the dialog's Cancel/Apply/OK footer
        // is shell chrome with no slot for a plasmoid's button.
        SectionLabel { colors: root.colors; text: "Reset" }

        SettingsRow {
            colors: root.colors
            name: "Restore Defaults"
            desc: "Resets every setting on this page back to its default values"
            showDivider: false

            Rectangle {
                id: defaultsBtn
                radius: root.theme.radiusSm
                implicitWidth: defaultsLabel.implicitWidth + 28
                implicitHeight: defaultsLabel.implicitHeight + 14
                color: root.colors.surface
                border.width: 1
                border.color: defaultsArea.containsMouse ? root.colors.copperDim : root.colors.controlBorder
                // Light-theme card shadow.
                Ui.CardShadow { colors: root.colors; radius: parent.radius }

                Label {
                    id: defaultsLabel
                    anchors.centerIn: parent
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    text: "Defaults"
                    color: defaultsArea.containsMouse ? root.colors.copperBright : root.colors.text
                }

                MouseArea {
                    id: defaultsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    // Writes the cfg_* properties like every other
                    // control, so the shell's dirty-check enables Apply.
                    onClicked: {
                        root.cfg_theme = root.shippedDefaults.theme;
                        root.cfg_transparencyEnabled = root.shippedDefaults.transparencyEnabled;
                        root.cfg_transparencyPercent = root.shippedDefaults.transparencyPercent;
                        root.cfg_volumeStepDb = root.shippedDefaults.volumeStepDb;
                        root.cfg_startupVolumeDb = root.shippedDefaults.startupVolumeDb;
                        // Widen the hard limit to dbRangeMax first, so
                        // every intermediate pair stays valid and
                        // healLimitOrdering() never fires mid-reset. Without
                        // it, e.g. floor -90 / hard limit -89 would see
                        // floor -50 >= -89, heal to -40/-39, and end at
                        // floor -40 instead of -50.
                        root.cfg_hardLimitDb = root.dbRangeMax;
                        root.cfg_volumeFloorDb = root.shippedDefaults.volumeFloorDb;
                        root.cfg_hardLimitDb = root.shippedDefaults.hardLimitDb;
                        root.cfg_chimeEnabled = root.shippedDefaults.chimeEnabled;
                        // Also resets the pinned theme, which the mockup's
                        // handleDefaults() (v17 lines 698-717) does not.
                        root.cfg_chimeSourceMode = root.shippedDefaults.chimeSourceMode;
                        root.cfg_chimePinnedTheme = root.shippedDefaults.chimePinnedTheme;
                        root.cfg_chimeSoundFile = root.shippedDefaults.chimeSoundFile;
                        // Launch at Login resets like a click on its
                        // switch: a pending launchDesired that saveConfig()
                        // applies on Apply/OK and Cancel drops. Only while
                        // the switch is clickable; non-toggleable states
                        // keep showing their note.
                        if (root.daemonAutostart.toggleable && !root.daemonAutostart.writing) {
                            root.launchDesired = root.shippedDefaults.launchAtLogin;
                        }
                        themeDropdown.close();
                    }
                }
            }
        }
    }
}
