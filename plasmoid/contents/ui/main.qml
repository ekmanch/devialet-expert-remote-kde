// Applet root. Owns the cross-view state objects and forwards them to
// CompactRepresentation as required properties (docs/DESIGN.md §3). A
// panel-pinned applet, not a tray item (docs/DESIGN.md §1).

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as Dbus

PlasmoidItem {
    id: root

    // Panel icon, a bundled SVG (Plasmoid.icon accepts a resolvable path,
    // not just a theme name). metadata.json's KPlugin.Icon is a separate,
    // theme-only mechanism (docs/DESIGN.md §4). The artwork uses hardcoded
    // copper, not currentColor; see CompactRepresentation.qml for why
    // isMask is off.
    Plasmoid.icon: Qt.resolvedUrl("../icons/devialet_icon_glow_dot.svg")

    // Duplicated from CompactRepresentation/FlyoutContent because
    // applyImmediateClamp() must work whichever representation is resident.
    readonly property string devialetCtlCommand: "devialet-ctl"

    // Shared VolumeDb/Muted view (see PendingAmpState.qml). Anchored at the
    // root because it outlives both representations (docs/DESIGN.md §3).
    PendingAmpState {
        id: pendingAmpState

        // Re-check the clamp when the amp connects: a check run before
        // ampIp arrived (e.g. the on-load self-heal below) no-op'd, and
        // floorDb/hardLimitDb will not change again to retry it. Also
        // covers starting up with an out-of-range stored volume.
        // Deferred because the D-Bus handlers assign ampIp before
        // volumeDb; a synchronous call would read the stale volume.
        onAmpIpChanged: Qt.callLater(root.applyImmediateClamp)
    }

    // Volume range and chime settings, root-anchored and forwarded like
    // PendingAmpState (see VolumeSettings.qml).
    VolumeSettings {
        id: volumeSettings
        floorDb: Plasmoid.configuration.volumeFloorDb
        hardLimitDb: Plasmoid.configuration.hardLimitDb
        stepDb: Plasmoid.configuration.volumeStepDb
        startupVolumeDb: Plasmoid.configuration.startupVolumeDb
        chimeEnabled: Plasmoid.configuration.chimeEnabled
        // The pinned theme is resolved to a file by soundThemes below;
        // pathFor() reads its `themes`, so this re-evaluates when a scan
        // lands.
        chimeSourceMode: Plasmoid.configuration.chimeSourceMode
        chimePinnedTheme: Plasmoid.configuration.chimePinnedTheme
        chimeSoundFile: Plasmoid.configuration.chimeSoundFile
        chimePinnedThemePath: soundThemes.pathFor(Plasmoid.configuration.chimePinnedTheme)
        soundThemes: soundThemes

        // One Apply/OK can change floor and hard limit in the same tick as
        // two separate signals; a direct call would clamp against one new
        // and one stale value. Qt.callLater dedupes calls to the same
        // function value within one event-loop turn, so pass the bare
        // function (a lambda is a new closure each time and would not
        // dedupe) to get exactly one settled check.
        onFloorDbChanged: Qt.callLater(root.applyImmediateClamp)
        onHardLimitDbChanged: Qt.callLater(root.applyImmediateClamp)

        // Self-heal an invalid floor/hard-limit pair already on disk (e.g.
        // the INI edited by hand); ConfigGeneral.qml's steppers only stop
        // new ones. Runs before either representation binds to this
        // object, so no invalid range is ever visible. This is the only
        // reliable point: Plasmoid.configuration reads the file once per
        // plasmashell process and never sees later external writes.
        // Resets to -40/-39 (floor below hard limit).
        Component.onCompleted: {
            if (Plasmoid.configuration.volumeFloorDb >= Plasmoid.configuration.hardLimitDb) {
                console.log("[VolumeSettings] floor/hardLimit invalid on load (" +
                            Plasmoid.configuration.volumeFloorDb + " >= " +
                            Plasmoid.configuration.hardLimitDb + ") - self-healing to -40.0/-39.0");
                Plasmoid.configuration.volumeFloorDb = -40.0;
                Plasmoid.configuration.hardLimitDb = -39.0;
            }
        }
    }

    // Widget-side theme-id -> file resolver, the same SoundThemes.qml the
    // settings page uses (see its header for why it is per-file). Rescans
    // when the pinned theme changes, so a theme installed after the shell
    // started resolves without a restart.
    SoundThemes {
        id: soundThemes
        readonly property string watchedPinnedTheme: Plasmoid.configuration.chimePinnedTheme
        onWatchedPinnedThemeChanged: soundThemes.scan()
        Component.onCompleted: soundThemes.scan()
    }

    TransparencySettings {
        id: transparencySettings
        enabled: Plasmoid.configuration.transparencyEnabled
        percent: Plasmoid.configuration.transparencyPercent
    }

    // The colour theme resolved to palettes (see ThemeSettings.qml).
    ThemeSettings {
        id: themeSettings
        mode: Plasmoid.configuration.theme
        // "Follow system", from the XDG settings portal.
        systemDark: systemScheme.dark
    }

    // Reads the desktop's colour scheme (see its header). An invisible
    // Item here so its Kirigami.Theme fallback sees the applet's own
    // colours.
    SystemScheme {
        id: systemScheme
        context: "applet"
    }

    // Executable engine for applyImmediateClamp(); its own instance
    // because the representations' DataSources may not be resident.
    P5Support.DataSource {
        id: clampExec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-ctl finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    // Clamp the connected amp's volume into [floorDb, hardLimitDb] at once
    // when a settings change (or the self-heal) leaves it outside, in both
    // directions. Only the current AmpIp is touched. Same two steps as
    // every volume call site: devialet-ctl, then notifyVolume() for the
    // optimistic mirror (the daemon never sends UDP itself).
    //
    // Does not unmute: the amp stays muted through a settings correction.
    // A volume packet carries no mute bit, so the command alone does not
    // unmute; the unmute in stepVolume() is a UX choice for user input.
    //
    // Gated on power "On" (gotcha #10): the amp drops commands while Off
    // or Booting and the 400 ms pending mask would only flash the value.
    // An out-of-range volume on a powered-off amp is corrected at the
    // next ampIp/setting change or user volume action.
    function applyImmediateClamp() {
        if (pendingAmpState.ampIp === "" || pendingAmpState.volumeDb === undefined) return;
        if (root.ampPowerState !== "On") return;
        const clamped = volumeSettings.clamp(pendingAmpState.volumeDb);
        if (clamped === pendingAmpState.volumeDb) return;
        clampExec.connectSource(root.devialetCtlCommand + " --ip " + pendingAmpState.ampIp +
            " volume " + clamped + " --hard-limit-db " + volumeSettings.hardLimitDb);
        pendingAmpState.notifyVolume(clamped);
    }

    // The amp's PowerState ("Off"/"Booting"/"On"), read once here and
    // forwarded down, used only to gate inputs. FlyoutContent keeps its own
    // copy on purpose: that one carries the power button's 400 ms
    // optimistic guard and arms the boot hold, so this one lags its
    // optimistic "Booting" by up to one broadcast (~200 ms). Not part of
    // PendingAmpState, which is limited to volume/mute.
    property string ampPowerState: "Off"
    // Re-run the clamp when the amp comes on. Needed for ordering: the
    // daemon sends one PropertiesChanged per property, so onAmpIpChanged's
    // deferred check can run between the AmpIp and PowerState messages and
    // read a stale "Off". Same Qt.callLater target, so both collapse into
    // one call. Known gap: a command at the first "On" can be dropped by
    // the amp (gotcha #9); the next ampIp/setting change or volume action
    // re-checks. That only matters when the amp's startup volume is
    // outside [floor, hardLimit], so no extra delay is added.
    onAmpPowerStateChanged: if (root.ampPowerState === "On") Qt.callLater(root.applyImmediateClamp)

    Dbus.Properties {
        id: powerProps
        busType: Dbus.BusType.Session
        service: pendingAmpState.serviceName
        path: pendingAmpState.objectPath
        iface: pendingAmpState.interfaceName
        onRefreshed: root.ampPowerState = pendingAmpState.unwrap(properties.PowerState, "Off")
        onPropertiesChanged: (interfaceName, changed, invalidated) => {
            if ("PowerState" in changed) root.ampPowerState = pendingAmpState.unwrap(changed.PowerState, root.ampPowerState);
        }
    }

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
        pendingAmpState: pendingAmpState
        volumeSettings: volumeSettings
        transparencySettings: transparencySettings
        themeSettings: themeSettings
        powerState: root.ampPowerState
    }

    // Placeholder, but required: with no fullRepresentation the panel icon
    // does not render at all. The flyout is FlyoutPopup.qml, opened by
    // CompactRepresentation.
    fullRepresentation: Item {}

    // Nothing here sets `expanded`, but PlasmoidItem always connects
    // Applet::activated to setExpanded(true), so the auto-generated
    // "Activate" global shortcut (or Enter/Space/accessibility activation
    // on the icon) can still show the shell's popup with this empty
    // placeholder. Left unhandled: no shortcut is bound by default, the
    // box dismisses on Escape or any outside click, and the real flyout
    // and tooltip follow flyoutPopup.visible, not `expanded`.

    // CompactRepresentation draws its own hover tooltip
    // (VolumeHoverTooltip.qml), so the shell's must stay silent. Leaving
    // these unset is not enough: PlasmoidItem falls back to metadata.json's
    // Name/Comment while the string is null. Assigning "" makes it empty
    // and non-null, so ToolTipArea::isValid() is false.
    toolTipMainText: ""
    toolTipSubText: ""
}
