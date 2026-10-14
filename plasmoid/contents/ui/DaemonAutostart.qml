// The one place that reads and changes the daemon's launch-at-login
// state: `systemctl --user is-enabled` / `enable` / `disable` on
// devialet-remote-daemon.service. systemd's enablement state is the
// storage; there is no KConfig bool (docs/DESIGN.md §4).
// ConfigGeneral.qml instantiates one per dialog open.
//
// Plain QtObject (no qmldir/singleton in this KPackage) holding its
// P5Support.DataSource as an object-typed property, like SoundThemes.qml.
// Deliberately does not import org.kde.plasma.plasmoid.
//
// The query result is classified by the stdout TOKEN, not the exit code
// (measured, systemd 261):
//   enabled        -> stdout "enabled",   exit 0
//   disabled       -> stdout "disabled",  exit 1   (a normal answer)
//   unit missing   -> stdout "not-found", exit 4
//   user bus down  -> stdout EMPTY, exit 1, stderr "Failed to connect to
//                     user scope bus ..."   (same exit code as disabled!)
//   systemctl not on PATH -> exit 127, shell stderr, empty stdout
// So exit 1 alone cannot tell "genuinely disabled" from "the query itself
// failed"; the token can. The exit code and stderr are only consulted
// when there is no token at all. Full token list is systemctl(1)'s
// "is-enabled output" table: enabled, enabled-runtime, linked,
// linked-runtime, alias, masked, masked-runtime, static, indirect,
// disabled, generated, transient, not-found.
//
// For enable/disable the exit code IS the verdict: both print
// "Created symlink ..." / "Removed ..." on stderr with exit 0, so stderr
// is informational unless the exit code is non-zero.
import QtQuick
import org.kde.plasma.plasma5support as P5Support

QtObject {
    id: root

    readonly property string unitName: "devialet-remote-daemon.service"

    // Only a test driver overrides this (e.g. "/nonexistent/systemctl
    // --user", for the failing-query path); ConfigGeneral.qml never does.
    property string systemctl: "systemctl --user"

    // One of: "unknown" (never queried), "querying", "enabled",
    // "disabled", "not-found" (unit file missing - exit 4),
    // "unsupported" (a real token this toggle can't act on: static,
    // masked, indirect, linked, alias, generated, transient,
    // enabled-runtime - the last doesn't survive a reboot, so it is not
    // "launch at login" either), "error" (no token at all: bus
    // unreachable, systemctl missing, anything unexpected).
    property string state: "unknown"
    // Raw first stdout line of the last query ("" when there was none).
    property string token: ""
    // First stderr line of the last FAILED query; "" when the last
    // query produced a token.
    property string detail: ""

    property bool writing: false
    // Set when the last enable/disable exited non-zero, with its first
    // stderr line in writeDetail; both cleared by the next apply(). Kept
    // separate from `detail` on purpose: the re-query that follows a
    // failed write overwrites `detail`, and the page still needs to say
    // "couldn't change it" next to the real, re-queried state.
    property bool lastWriteFailed: false
    property string writeDetail: ""

    // The only two states a toggle may act on.
    readonly property bool toggleable: root.state === "enabled" || root.state === "disabled"

    // Emitted once per apply(), after the re-query has been ISSUED (not
    // completed): ok = the enable/disable command exited 0.
    signal applied(bool ok)

    // Each command gets a no-op DEVIALET_SYSTEMD_TICK=<n> env prefix: the
    // shared executable engine keys running jobs by command string, so a
    // second identical is-enabled while the first is in flight would
    // collapse into it. The exact strings are also the dispatch keys in
    // onNewData below. The tick wraps at tickSlots so the command strings
    // come from a fixed set (docs/DESIGN.md §5): 16 ticks x 3 commands
    // (is-enabled, enable, disable) = 48 strings for the life of the
    // shell. At most one query and one write are pending at a time, so a
    // tick is reused only after 15 newer commands; a superseded query
    // still running by then would have to outlive all of them.
    readonly property int tickSlots: 16
    property int tick: 0
    property string pendingQuery: ""
    property string pendingWrite: ""

    function nextPrefix() {
        const p = "DEVIALET_SYSTEMD_TICK=" + root.tick + " ";
        root.tick = (root.tick + 1) % root.tickSlots;
        return p;
    }

    function firstLine(s) {
        return String(s || "").split("\n")[0].trim();
    }

    function refresh() {
        root.state = "querying";
        root.pendingQuery = root.nextPrefix() + root.systemctl + " is-enabled " + root.unitName;
        root.probe.connectSource(root.pendingQuery);
    }

    // Plain enable/disable, no --now: the toggle means "launch at login",
    // not "run the daemon now". A running daemon keeps running after
    // disable, and enabling doesn't start a stopped one before next login.
    function apply(enable) {
        root.lastWriteFailed = false;
        root.writeDetail = "";
        root.writing = true;
        root.pendingWrite = root.nextPrefix() + root.systemctl + (enable ? " enable " : " disable ") + root.unitName;
        console.log("[DaemonAutostart] running:", root.pendingWrite);
        root.probe.connectSource(root.pendingWrite);
    }

    function classify(code, stdout, stderr) {
        root.token = root.firstLine(stdout);
        switch (root.token) {
        case "enabled":
            root.state = "enabled";
            root.detail = "";
            return;
        case "disabled":
            root.state = "disabled";
            root.detail = "";
            return;
        case "not-found":
            root.state = "not-found";
            root.detail = "";
            break;
        case "":
            root.state = "error";
            root.detail = root.firstLine(stderr);
            if (root.detail === "") root.detail = "exit code " + code;
            break;
        default:
            root.state = "unsupported";
            root.detail = "";
            break;
        }
        console.warn("[DaemonAutostart] is-enabled ->", root.state, "- exit code:", code, "token:", root.token, "stderr:", root.firstLine(stderr));
    }

    readonly property P5Support.DataSource probe: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            const code = data["exit code"];
            if (source === root.pendingQuery) {
                root.pendingQuery = "";
                root.classify(code, data["stdout"], data["stderr"]);
            } else if (source === root.pendingWrite) {
                root.pendingWrite = "";
                const ok = code === 0;
                if (!ok) {
                    root.lastWriteFailed = true;
                    root.writeDetail = root.firstLine(data["stderr"]);
                    if (root.writeDetail === "") root.writeDetail = "exit code " + code;
                    console.warn("[DaemonAutostart] enable/disable FAILED - exit code:", code, "stderr:", data["stderr"], "command:", source);
                } else {
                    console.log("[DaemonAutostart] enable/disable ok:", root.firstLine(data["stderr"]));
                }
                root.writing = false;
                // Never trust the click: the toggle is re-derived from
                // what systemd says now, whether the write worked or not.
                root.refresh();
                root.applied(ok);
            } else {
                console.log("[DaemonAutostart] ignoring stale result for:", source);
            }
            disconnectSource(source);
        }
    }
}
