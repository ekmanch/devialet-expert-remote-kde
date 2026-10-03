// Phase 17.15.0 - "Follow system": is the desktop's colour scheme dark?
//
// Source (owner decision D1): the XDG settings portal's
// `org.freedesktop.appearance color-scheme`, which xdg-desktop-portal-kde
// computes from the application palette (kdeglobals) - 1 = prefer dark,
// 2 = prefer light, 0 = no preference. One source for both the applet and
// the ConfigDialog page, reachable with no C++ through
// org.kde.plasma.workspace.dbus (the same SessionBus.asyncCall /
// SignalWatcher API PendingAmpState.qml already uses).
//
// Contract (docs/context-on-light-theme-arc-phase-17.md, "Portal reader"):
//   - `dark` starts true (today's look) and changes only when a value
//     arrives, so nothing flashes light at load.
//   - One ReadOne at start. 1 -> dark, 2 -> light.
//   - 0, any other value, a D-Bus error, or no reply within `timeoutMs`
//     (a Timer racing the reply - asyncCall has no timeout of its own) ->
//     the fallback: the brightness of this item's Kirigami.Theme
//     background (Plasma Style colours in the applet, the window's scheme
//     in the ConfigDialog). A late 1/2 reply still wins.
//   - SettingChanged for exactly that namespace + key applies the same
//     mapping live; 0 there also means "use the fallback".
//   - The portal is D-Bus-activatable, so ReadOne starts it if needed; no
//     "appears later" handling.
// One journal line per change of `dark` or `source`.
//
// An Item (invisible, zero-size) rather than a QtObject so its attached
// Kirigami.Theme inherits the colours of wherever it is placed.

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as Dbus

Item {
    id: scheme

    visible: false
    width: 0
    height: 0

    // Result.
    property bool dark: true
    // "start" (no answer yet) | "portal" | "fallback"
    property string source: "start"

    // Tuning / test seams.
    property int timeoutMs: 2000
    property color fallbackColor: Kirigami.Theme.backgroundColor
    readonly property bool fallbackDark: Kirigami.ColorUtils.brightnessForColor(scheme.fallbackColor) === Kirigami.ColorUtils.Dark
    // Label for the journal line ("applet", "config page").
    property string context: ""

    readonly property string portalService: "org.freedesktop.portal.Desktop"
    readonly property string portalPath: "/org/freedesktop/portal/desktop"
    readonly property string portalIface: "org.freedesktop.portal.Settings"
    readonly property string appearanceNamespace: "org.freedesktop.appearance"
    readonly property string colorSchemeKey: "color-scheme"

    // True once the portal has given a usable 1/2 answer; a timeout or error
    // after that must not override it.
    property bool _portalAnswered: false

    function unwrap(v) {
        while (v !== null && v !== undefined && typeof v === "object" && v.value !== undefined) v = v.value;
        return v;
    }

    function settle(isDark, newSource, why) {
        const changed = isDark !== scheme.dark || newSource !== scheme.source;
        scheme.dark = isDark;
        scheme.source = newSource;
        if (changed) {
            console.log("[SystemScheme]" + (scheme.context ? " " + scheme.context : "") + ": dark", isDark,
                        "from", newSource, "-", why);
        }
    }

    // Map one portal value; anything but 1/2 means "use the fallback".
    function applyPortalValue(raw, why) {
        const v = Number(scheme.unwrap(raw));
        if (v === 1 || v === 2) {
            scheme._portalAnswered = true;
            scheme.timeout.stop();
            scheme.settle(v === 1, "portal", why + " (color-scheme " + v + ")");
        } else {
            scheme._portalAnswered = false;
            scheme.timeout.stop();
            scheme.settle(scheme.fallbackDark, "fallback", why + " (color-scheme " + v + ", no preference)");
        }
    }

    function useFallback(why) {
        if (scheme._portalAnswered) return;
        scheme.timeout.stop();
        scheme.settle(scheme.fallbackDark, "fallback", why);
    }

    // The fallback follows its colour live while it is in use.
    onFallbackDarkChanged: if (scheme.source === "fallback") scheme.settle(scheme.fallbackDark, "fallback", "desktop colours changed")

    function read() {
        Dbus.SessionBus.asyncCall(
            new Dbus.dbusMessage({
                service: scheme.portalService,
                path: scheme.portalPath,
                interface: scheme.portalIface,
                member: "ReadOne",
                arguments: [scheme.appearanceNamespace, scheme.colorSchemeKey]
            }),
            function (reply) {
                if (reply.isError) scheme.useFallback("portal error " + JSON.stringify(reply.error));
                else scheme.applyPortalValue(reply.value, "portal reply");
            },
            function (reply) {
                scheme.useFallback("portal call failed " + JSON.stringify(reply.error));
            }
        );
    }

    readonly property Timer timeout: Timer {
        interval: scheme.timeoutMs
        onTriggered: scheme.useFallback("no portal reply within " + scheme.timeoutMs + " ms")
    }

    // SignalWatcher calls a function named "dbus" + <member> on itself
    // (plasma-workspace's convention, see PendingAmpState.qml).
    readonly property Dbus.SignalWatcher changes: Dbus.SignalWatcher {
        busType: Dbus.BusType.Session
        service: scheme.portalService
        path: scheme.portalPath
        iface: scheme.portalIface

        function dbusSettingChanged(ns, key, value) {
            if (scheme.unwrap(ns) !== scheme.appearanceNamespace || scheme.unwrap(key) !== scheme.colorSchemeKey) return;
            scheme.applyPortalValue(value, "portal SettingChanged");
        }
    }

    Component.onCompleted: {
        scheme.timeout.start();
        scheme.read();
    }
}
