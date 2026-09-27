#!/usr/bin/env bash
# QML unit tests (tests/qml/tst_*.qml) against the real plasmoid QML.
#
# Runs on a private session bus (dbus-run-session) with
# tools/flyout-harness/fakeamp.py owning the daemon's bus name inside it, so
# the tests never touch the real daemon or the real amp and need nothing
# stopped first. The fake is only a sink for the Notify*Command calls the
# code under test makes; the tests drive property pushes themselves.
#
# Tooling: the Qt 6 runner is /usr/lib/qt6/bin/qmltestrunner (/usr/bin/qml*
# are Qt 5 on Arch); QT_FORCE_STDERR_LOGGING keeps console output out of
# journald; offscreen QPA so no window is needed.
# QT_QUICK_CONTROLS_STYLE=org.kde.desktop: the controls style plasmashell
# loads (qqc2-desktop-style). The runner's default style overlays a 10 px
# ScrollBar without reserving width, the desktop one reserves 21 px - the
# difference tst_SourceListOverlay.qml's row-width check depends on
# (Phase 17.1.1). Geometry only: offscreen still renders effects blank, so
# never add a rendered-pixel assertion here (Phase 17 capture rule).
#
# Usage: scripts/test-qml.sh [qmltestrunner args, e.g. -functions or
#        "PendingAmpState::test_fallback_restarts_from_the_send"]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
QMLTESTRUNNER=${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}
[ -x "$QMLTESTRUNNER" ] || { echo "qmltestrunner not found at $QMLTESTRUNNER (pacman -S qt6-declarative)" >&2; exit 2; }
command -v dbus-run-session >/dev/null || { echo "dbus-run-session not found (pacman -S dbus)" >&2; exit 2; }

# --config-file: a session bus with no service activation, see the file's
# own comment (the desktop style would otherwise auto-start a portal that
# outlives the run and hangs this script).
exec dbus-run-session --config-file="$REPO/tests/qml/session-bus.conf" -- bash -c '
    repo=$1; runner=$2; shift 2
    python3 "$repo/tools/flyout-harness/fakeamp.py" >/dev/null 2>&1 &
    fake=$!
    # Phase 17.15.0: fake XDG settings portal for tst_SystemScheme.qml (it
    # refuses to start where the real portal name is owned, so it can only
    # ever run here, on this private bus).
    python3 "$repo/tests/qml/fakeportal.py" >/dev/null 2>&1 &
    portal=$!
    trap "kill $fake $portal 2>/dev/null; wait $fake $portal 2>/dev/null" EXIT
    gdbus wait --session --timeout 10 com.ekmanch.DevialetRemote
    gdbus wait --session --timeout 10 org.freedesktop.portal.Desktop
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
        "$runner" -input "$repo/tests/qml" "$@"
' _ "$REPO" "$QMLTESTRUNNER" "$@"
