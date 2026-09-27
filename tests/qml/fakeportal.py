#!/usr/bin/env python3
"""Fake org.freedesktop.portal.Settings for tst_SystemScheme.qml (Phase 17.15.0).

Owns org.freedesktop.portal.Desktop on the PRIVATE test bus that
scripts/test-qml.sh creates, and answers
`ReadOne("org.freedesktop.appearance", "color-scheme")` the way the test
asks it to, through a small control interface the QML test calls:

  com.ekmanch.Test.FakePortal1 at /com/ekmanch/Test/FakePortal
    SetReply(s mode, u value, u delay_ms)
        mode "value"  - reply with the uint32 `value` (wrapped in a variant,
                        exactly like xdg-desktop-portal-kde), after delay_ms
        mode "error"  - reply with a D-Bus error
        mode "silent" - never reply
    EmitChanged(s namespace, s key, u value)
        emit Settings.SettingChanged(namespace, key, <uint32 value>)

Safety: refuses to start if org.freedesktop.portal.Desktop already has an
owner - which it always does on the real session bus - so it can never
stand in for the desktop's own portal.
"""

import signal
import sys

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PORTAL_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SETTINGS_IFACE = "org.freedesktop.portal.Settings"
CTL_PATH = "/com/ekmanch/Test/FakePortal"
CTL_IFACE = "com.ekmanch.Test.FakePortal1"

XML = f"""<node>
  <interface name="{SETTINGS_IFACE}">
    <method name="ReadOne">
      <arg name="namespace" type="s" direction="in"/>
      <arg name="key" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <signal name="SettingChanged">
      <arg name="namespace" type="s"/>
      <arg name="key" type="s"/>
      <arg name="value" type="v"/>
    </signal>
    <property name="version" type="u" access="read"/>
  </interface>
  <interface name="{CTL_IFACE}">
    <method name="SetReply">
      <arg name="mode" type="s" direction="in"/>
      <arg name="value" type="u" direction="in"/>
      <arg name="delay_ms" type="u" direction="in"/>
    </method>
    <method name="EmitChanged">
      <arg name="namespace" type="s" direction="in"/>
      <arg name="key" type="s" direction="in"/>
      <arg name="value" type="u" direction="in"/>
    </method>
  </interface>
</node>"""


class FakePortal:
    def __init__(self):
        self.mode, self.value, self.delay_ms = "value", 1, 0
        self.pending = []  # silent-mode invocations kept alive, never answered
        self.conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def start(self):
        owner = self._owner(PORTAL_NAME)
        if owner is not None:
            print(f"fakeportal: {PORTAL_NAME} is already owned by {owner} - refusing "
                  "(this must only run on a private test bus)", file=sys.stderr)
            sys.exit(3)
        info = Gio.DBusNodeInfo.new_for_xml(XML)
        settings = next(i for i in info.interfaces if i.name == SETTINGS_IFACE)
        ctl = next(i for i in info.interfaces if i.name == CTL_IFACE)
        self.conn.register_object(PORTAL_PATH, settings, self._on_settings, self._get_prop, None)
        self.conn.register_object(CTL_PATH, ctl, self._on_ctl, None, None)
        reply = self.conn.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
            GLib.Variant("(su)", (PORTAL_NAME, 4)), GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 2000, None)
        if reply.unpack()[0] != 1:
            print(f"fakeportal: could not own {PORTAL_NAME}", file=sys.stderr)
            sys.exit(3)

    def _owner(self, name):
        try:
            return self.conn.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner",
                GLib.Variant("(s)", (name,)), GLib.VariantType("(s)"), Gio.DBusCallFlags.NONE, 2000,
                None).unpack()[0]
        except GLib.Error:
            return None

    def _get_prop(self, conn, sender, path, iface, name):
        return GLib.Variant("u", 2)

    def _on_settings(self, conn, sender, path, iface, method, params, inv):
        if method != "ReadOne":
            inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)
            return
        ns, key = params.unpack()
        if (ns, key) != ("org.freedesktop.appearance", "color-scheme"):
            inv.return_dbus_error("org.freedesktop.portal.Error.NotFound", f"{ns}.{key}")
        elif self.mode == "error":
            inv.return_dbus_error("org.freedesktop.portal.Error.Failed", "fake portal: error mode")
        elif self.mode == "silent":
            self.pending.append(inv)
        else:
            body = GLib.Variant("(v)", (GLib.Variant("u", self.value),))
            if self.delay_ms:
                GLib.timeout_add(self.delay_ms, lambda: (inv.return_value(body), False)[1])
            else:
                inv.return_value(body)

    def _on_ctl(self, conn, sender, path, iface, method, params, inv):
        if method == "SetReply":
            self.mode, self.value, self.delay_ms = params.unpack()
        elif method == "EmitChanged":
            ns, key, value = params.unpack()
            self.conn.emit_signal(None, PORTAL_PATH, SETTINGS_IFACE, "SettingChanged",
                                  GLib.Variant("(ssv)", (ns, key, GLib.Variant("u", value))))
        inv.return_value(None)


def main():
    portal = FakePortal()
    portal.start()
    loop = GLib.MainLoop()
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    signal.signal(signal.SIGINT, lambda *_: loop.quit())
    loop.run()


if __name__ == "__main__":
    main()
