# CLAUDE.md

## Project

KDE Plasma panel-pinned widget (Plasmoid) for controlling the Devialet
Expert Pro 140 amplifier over UDP — an icon a user drags directly onto
their panel via "Add Widgets" (like Digital Clock or Compact Pager), not a
system tray item. Companion project to an existing Android app and an
in-progress Flutter app for the same amplifier — same protocol, different
platform. Rust + QML, no C++.

## Background

An Android app was developed earlier in Kotlin (source of truth for the
protocol and known bugs):
https://github.com/ekmanch/devialet-expert-remote

A Flutter port for Android/iOS is also in progress, in a separate repo:
https://github.com/ekmanch/devialet-expert-remote-app

This widget is a second, independent port of the same protocol to a third
platform (Linux desktop / KDE Plasma), not built on top of either of the
above — but the protocol itself, and known gotchas, are shared truth across
all three.

## Reference docs

- `docs/DESIGN.md` — how the widget works and why: architecture, the D-Bus
  surface, state and behaviour rules, the settings dialog, QML house rules,
  the light theme, and what was decided against. **Settled — read it
  before changing any of those areas, and don't re-derive or relitigate
  what it records.** Add a rule there when a new decision is made.
- `docs/protocol.md` — UDP packet structure, transport details, command
  types. Treat as the spec for the networking layer. Anything marked
  "inferred, not confirmed" should be verified against the real device
  before being relied on.
- `docs/known-gotchas.md` — bugs already found and fixed in the Kotlin/
  Flutter apps and this widget. Check before implementing anything
  networking/state related so we don't reintroduce a fixed bug — in
  particular the non-linear source-index-to-command-value lookup table
  and the forced startup-volume send after every source switch.
- `docs/app-overview.md` — architecture/feature overview of the original
  Android app. Most of its "platform-specific behavior" section doesn't
  transfer; the KDE equivalents are decided in `docs/DESIGN.md`.
- `TODO.md` — phase status and roadmap.

## Scope

Control-only: volume, mute, power, source selection. No SAM/Night
Mode/Bass/Treble (UDP bytes not reverse-engineered).

## Networking

- Follow `docs/protocol.md` exactly for packet structure — don't
  reconstruct it from guesswork.
- Cross-check any new networking/protocol code against
  `docs/known-gotchas.md`.
- The hard volume limit is enforced inside the protocol crate's volume
  constructor, not left to QML range limiting (`docs/DESIGN.md` §3).

## Testing

- Protocol crate: `cargo test`, fixed byte fixtures — packet building,
  CRC16 poly/init, the source remap table (encoded as a regression test
  with hardcoded expected output bytes, guarding against reintroducing
  known-gotchas.md bug #3 — source index treated as command value). No
  network or hardware required.
- QML: `scripts/test-qml.sh` runs `tests/qml/tst_*.qml` (QtTest,
  `/usr/lib/qt6/bin/qmltestrunner`) against the real plasmoid QML on a
  private session bus (`dbus-run-session`) with
  `tools/flyout-harness/fakeamp.py` as the Notify*Command sink — the real
  daemon and amp are never touched, nothing needs stopping.
  - Tests drive daemon pushes by emitting `ampProps.propertiesChanged()`
    one property per call in `emit_all()` order, the real message shape.
  - The runner uses `QT_QUICK_CONTROLS_STYLE=org.kde.desktop` (the style
    plasmashell loads; the default style overlays scrollbars without
    reserving width, which hid a real layout bug) and a private bus from
    `tests/qml/session-bus.conf` with no service activation (otherwise the
    desktop style auto-starts xdg-desktop-portal-kde on it, which outlives
    the run and hangs the script).
  - `tests/qml/fakeportal.py` stands in for the XDG settings portal on
    that bus (it refuses to start where the real portal's name is owned);
    `tst_SystemScheme.qml` drives it to cover every branch of the
    Follow-system reader.
  - Notable guards: `tst_PendingAmpState.qml` (the post-boot hold must not
    release on a VolumeRaw match before the send), `tst_SourceListOverlay.qml`
    (selected-row visibility, row width, six sources without a scrollbar,
    a longer list capped and scrolling).
  - Geometry assertions only: offscreen renders effects blank
    (`docs/DESIGN.md` §6, capture rule).
- Flyout harness: `tools/flyout-harness/harness.py` (Wayland, `spectacle`
  captures, a `theme` dimension, `expected-17.json` as the current
  allowlist); see its README. The real ConfigDialog and the tooltip hover
  remain owner checks.

## Working style

- This is a phased build (architecture → scaffold → protocol crate →
  daemon → command CLI → QML UI → polish). Don't jump ahead to UI before
  the daemon and protocol layer are verified against the real amp.
- Prefer flagging ambiguity over guessing, especially for protocol/state
  behavior — ask rather than assume if `docs/` doesn't cover it.
- Keep commits scoped to one phase/concern at a time.
- Current phase status and the full roadmap are tracked in `TODO.md`, not
  here. Check it before assuming what's done vs. pending — but the phase
  stated explicitly in the prompt for a given session takes precedence if
  the two ever seem to disagree (e.g. TODO.md hasn't been updated yet).
- never add files as tracked, commit changes, or push changes to remote.
  The user of Claude Code would like to do this himself after verifying
  that everything works the way he expects it to.

## Reloading changes into the live widget

The plasmoid installed at
`~/.local/share/plasma/plasmoids/com.ekmanch.devialetremote/` is a **copy**
of `plasmoid/`, not a symlink — `kpackagetool6` copies files on install.
Editing files under the repo's `plasmoid/` does nothing to the running
widget by itself. Reload workflow after any change under `plasmoid/`:

```
kpackagetool6 --type Plasma/Applet --upgrade plasmoid/
plasmashell --replace &
```

`--upgrade` re-copies the package contents; `plasmashell --replace` is
needed because Plasma caches compiled QML per process — there is no hot
reload for KPackage applets. `--replace` briefly restarts the whole shell
(panels, tray, desktop); expected, not a crash.

- An icon-only change needs the same restart: after `--upgrade` alone the
  Add Widgets picker showed "?" until the shell's per-process icon cache
  was rebuilt by `--replace`.
- Rust binaries are copies in `/usr/local/bin`: re-run
  `scripts/install-binaries.sh` (or `./install.sh`) after any `cargo
  build` that changes one; it copies only the binaries that differ.
- A symlink from the install path to `plasmoid/` would skip the
  `kpackagetool6` step, but it stops rehearsing the real install path (a
  copy). Not adopted without asking first.

## `target/` can go missing out from under a running daemon — every widget command then silently no-ops

**Symptom:** every control (volume, mute, source, power) applies
optimistically for well under a second, then reverts to what the amp last
reported — uniformly across every control type. It looks exactly like a
regression in the pending-command mask, but isn't one: the daemon's 400 ms
mask is falling back as designed because no real command was ever sent.

**Root cause (found once, pre-Phase 13):** `target/` was deleted outside
any workflow step. `devialet-ctl` was then a symlink into it, so every
executable-engine call failed with exit **127**, which QML only logs. The
daemon kept running from its deleted binary (`/proc/<pid>/exe` shows
`(deleted)`), so `systemctl --user status` looked healthy. Since Phase
13.0.0 all three binaries are copies in `/usr/local/bin`, so this exact
form cannot recur, but the diagnosis applies to any missing or unreadable
binary.

**Diagnose:**

```
journalctl --user -b | grep devialet-ctl          # exit 127 = the binary is missing on PATH
systemctl --user show devialet-remote-daemon.service -p MainPID --value \
  | xargs -I{} ls -la /proc/{}/exe                 # must NOT say "(deleted)"
devialet-ctl --help                                 # must print usage (exit 1), not exit 127
```

**Fix:** `./install.sh`. Also make sure no leftover `~/.local/bin/<name>`
symlink exists: `~/.local/bin` precedes `/usr/local/bin` on plasmashell's
PATH and would silently shadow the installed copy.

**Rule:** when every control type reverts identically, check the shared
dependency (the CLI binary, the daemon binary) before suspecting the
logic of any one control.

## Real flyout renders truncated (324×180) after a reload — the AppletPopup size-key collision

**Symptom:** after `plasmashell --replace`, a shell-managed flyout opens
cut off at a stale size (324×180 was the placeholder popup's size).

**Mechanism:** `AppletPopup::hideEvent()` writes `popupWidth` /
`popupHeight` into the applet's config on **every** close, and the popup
reads them back at construction. Two popups sharing one `appletInterface`
share one KConfig group, so one popup's size lands on the other after the
next restart. Closed since Phase 7.10.0: the flyout is a
`PlasmaCore.Dialog` that leaves `appletInterface` unset, so it never writes
or reads the keys. Relevant again only if anything hosts an `AppletPopup`
with `appletInterface` set.

**Cleanup** (find the group via the `plugin=com.ekmanch.devialetremote`
line in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`; the harness
snapshots and restores both keys itself):

```
F=plasma-org.kde.plasma.desktop-appletsrc
G="--group Containments --group 46 --group Applets --group 128 --group Configuration"
kwriteconfig6 --file $F $G --key popupWidth --delete
kwriteconfig6 --file $F $G --key popupHeight --delete
plasmashell --replace &
```

**Verify with a fresh shell, and against absence.** `KConfigGroup` only
writes a value that differs from the shell's in-memory copy, and an
external `kwriteconfig6 --delete` doesn't invalidate that cache, so a test
against a running shell shows no write and looks like a pass. Compare
"keys absent after a restart", never "values unchanged" (the values may
already be the corruption).

## Environment

- OS: CachyOS (Arch-based); Desktop: KDE Plasma (Wayland). Editors: Kate,
  terminal.
- Rust: installed via `pacman -S rust` (no rustup) — 1.97.1 at scaffold
  time. Workspace edition 2021, `rust-version = "1.75"` (an arbitrary
  conservative floor; raise it if a phase needs something newer).
- Cargo workspace (`Cargo.toml` at the root, `resolver = "2"`):
  `crates/protocol` (`devialet-protocol`, no dependencies),
  `crates/devialet-remote-daemon` (`protocol`, `zbus`, `socket2`,
  `async-io`, `mdns-sd`), `crates/devialet-ctl` (`protocol` only),
  `crates/devialet-chime`.
- Notable dependencies — re-check changelogs before bumping, don't blindly
  `cargo update`:
  - `zbus = "5"`: default features already include `blocking-api` (used
    throughout the daemon) and `async-io`; no extra flags.
  - `socket2 = "0.6"`: only for `SO_REUSEADDR` before bind.
  - `async-io = "2"`: a direct dependency because zbus's generated
    `<property>_changed()` emitters are `async fn` even under the blocking
    API; the daemon drives each with `async_io::block_on(...)` at the
    point of emission. The daemon loop itself stays synchronous.
  - No serde/JSON.
- Qt6 dev tooling and a C++ compiler are installed on this machine but
  unused by this repo.
- **`devialet-ctl` / `devialet-chime` on PATH:** QML invokes them by bare
  name through the executable engine, which runs every command via
  `/bin/sh -c`, so plasmashell's inherited `PATH` applies (check it in
  `/proc/<plasmashell-pid>/environ`). A missing binary returns exit 127
  and a shell stderr line, no crash. Installed copies live in
  `/usr/local/bin` (`docs/DESIGN.md` §1).
- **`spectacle -b -f` from a non-interactive shell needs
  `QT_QPA_PLATFORM=wayland`:** otherwise it picks xcb and an XWayland grab
  of this Wayland session is a fully transparent PNG with exit code 0.
  Fail hard on an all-transparent capture in any screenshot-driven check,
  as `tools/flyout-harness/harness.py` does.
- Standalone QML drivers: the toast, tooltip and settings page render under
  `/usr/lib/qt6/bin/qml` on Wayland (reparent a Dialog's `mainItem` into a
  plain Window; for the page, set `page.pageScheme.dark` after the portal
  reply and pin window colours with a scratch `XDG_CONFIG_HOME/kdeglobals`).
  `fakeamp.py --ui themeOverride=light --notify volume=<dB>|mute=<bool>`
  shows the real toast for a capture.
- Repo: `devialet-expert-remote-kde`
  (https://github.com/ekmanch/devialet-expert-remote-kde; renamed from
  `devialet-expert-remote-widget`, which survives only in history).

## Repository Layout

```
devialet-expert-remote-kde/
├── Cargo.toml                      # workspace root
├── CLAUDE.md, README.md, TODO.md
├── install.sh, uninstall.sh        # sequence the scripts/ steps
├── crates/
│   ├── protocol/                   # zero-I/O packet encode/decode, CRC16,
│   │                               #   dbConvert, source remap table
│   ├── devialet-remote-daemon/     # UDP listener, D-Bus service (zbus)
│   ├── devialet-ctl/               # single-shot command CLI
│   └── devialet-chime/             # volume chime player
├── plasmoid/                       # KPackage root, passed directly to
│   │                               #   kpackagetool6 — shape dictated by
│   │                               #   KPackage, don't nest or "clean up"
│   ├── metadata.json
│   └── contents/
│       ├── ui/                     # main.qml and every QML component
│       └── config/                 # config.qml, main.xml and the General
│                                   #   page (referenced as "../config/…",
│                                   #   docs/DESIGN.md §4)
├── assets/                         # source-only fonts and icons, outside the
│                                   #   KPackage payload (the plasmoid bundles
│                                   #   its own copies); hicolor/ holds the
│                                   #   Add Widgets picker icon
├── design/mockups/                 # HTML mockups: configDialog/, flyout/,
│                                   #   OSD/, tooltip/
├── scripts/                        # install-binaries.sh, install-daemon-unit.sh,
│                                   #   install-plasmoid.sh, test-qml.sh
├── systemd/devialet-remote-daemon.service
├── packaging/aur/                  # PKGBUILD, .SRCINFO, .install
├── tests/qml/                      # QtTest suites, fake portal, bus config
├── tools/flyout-harness/           # capture harness and fakeamp.py
└── docs/
    ├── DESIGN.md
    ├── protocol.md
    ├── known-gotchas.md
    ├── app-overview.md
    ├── devialet_source_mapping.md
    └── context-on-*.md             # investigation records (Phase 7, Phase 17)
```

- `crates/` vs `plasmoid/` mirrors the Rust-does-logic / QML-does-UI
  boundary: protocol or D-Bus logic is in `crates/`; layout, theming or
  the flyout is in `plasmoid/`.
- `plasmoid/` and `systemd/` are shaped by their tools (`kpackagetool6`,
  `systemctl --user`), not by project convention — check what each tool
  expects before restructuring them.
- Testing the AUR package on the dev machine requires `./uninstall.sh`
  first: the `~/.local`, `~/.config` and `/usr/local/bin` copies precede the
  packaged paths and would silently shadow them.

## Related repos

- Android (Kotlin, source of truth for protocol):
  https://github.com/ekmanch/devialet-expert-remote
- Flutter port (Android/iOS, in progress, independent port of the same
  protocol): https://github.com/ekmanch/devialet-expert-remote-app
