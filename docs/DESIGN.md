# Design

How the widget works and why: the settled decisions. Each rule is stated with its reason; the investigations behind them are in the git history of `CLAUDE.md` and `TODO.md` (before the 2026-10 condensing). Protocol facts are in `docs/protocol.md`, fixed bugs in `docs/known-gotchas.md`.

## 1. Architecture

**Rust + QML only; no C++, no CMake.** A hard constraint. If a design seems to need C++ (cxx-qt or similar), stop and flag it.

**Panel-pinned applet, not a system tray item.** The tray hosts every applet inside its own shared popup, which draws a back-arrow and title row that no hosted applet can remove; the flyout must be our own panel, edge to edge. `metadata.json` therefore has no `X-Plasma-NotificationArea*` keys (they are what makes an applet tray-eligible). The user adds the widget through "Add Widgets", like Digital Clock.

**Three Rust binaries around one pure library.**
- `crates/protocol`: zero I/O (no sockets, files or async). Packet building, CRC16, `dbConvert`, the source remap table, model-name parsing. Everything else is a thin I/O shim around it, so the protocol is testable with byte fixtures and no hardware.
- `devialet-ctl`: single-shot command CLI. Builds one packet, sends it, exits. Takes `--ip` per call and never talks to the daemon.
- `devialet-remote-daemon`: the one long-running process. Owns UDP port 45454, parses every broadcast, keeps per-amp state. Plain synchronous Rust on a blocking `recv_from` loop; no async runtime (zbus's blocking API drives its async signal emitters with a local `async_io::block_on`, which is not a runtime).
- `devialet-chime`: plays the volume chime (Phase 10); reads its volumes from the daemon over D-Bus.

**Commands go QML → `devialet-ctl`; state comes daemon → D-Bus → QML.** QML runs the CLI through `Plasma5Support.DataSource`'s executable engine and reads state from session-bus properties (`PropertiesChanged` push via zbus, `Plasma.DBusProperties` in QML). No polling, no status file.

**The daemon runs as a `systemd --user` unit**, `Restart=on-failure`, wanted by the Plasma session. Not XDG autostart: the daemon needs crash recovery and a queryable state (`systemctl --user is-active / is-enabled`).

**In-process alternative (cxx-qt plugin inside plasmashell) rejected.** A crash would take down the whole panel, Rust panics across the FFI boundary are undefined behaviour unless guarded at every entry, and plugins have no hot reload. Do not revisit without a new reason.

**Binaries are installed by copy to `/usr/local/bin`.** It is on every default `PATH` on Arch (login shells, SDDM, systemd's `ExecStart` search path); `~/.local/bin` is not (it only appears through fish), and `cargo install` writes state and is Arch's fallback, not its rule. Because systemd resolves a bare `ExecStart=` against `/usr/local/bin`, the unit file uses `ExecStart=devialet-remote-daemon` and serves both `install.sh` and the AUR package unchanged. `./install.sh` runs `scripts/install-binaries.sh` → `install-daemon-unit.sh` → `install-plasmoid.sh`; the exit code is the failing step, no rollback, each step leaves a valid state.

**The AUR package (`packaging/aur/`) is a separate install path.** It installs under `/usr` itself (plasmoid to `/usr/share/plasma/plasmoids/<id>/`, binaries to `/usr/bin` via `cargo build --frozen --release` + `install`, unit to `/usr/lib/systemd/user/`), never calls `install.sh`, and its `.install` hook only prints the `systemctl --user enable --now` line. The source is the git tag with a `makepkg -g` checksum of `git archive`, not GitHub's tarball, so anything `package()` uses must be committed before tagging.

**KDE Store distribution is not possible.** A `.plasmoid` can only carry the plasmoid, not the daemon, the CLI or the unit (Phase 15, abandoned).

## 2. D-Bus surface

Bus name `com.ekmanch.DevialetRemote`, object `/com/ekmanch/DevialetRemote/Amp`, interface `com.ekmanch.DevialetRemote.Amp1`, session bus.

- **Primary-amp properties** (`DeviceName`, `AmpIp`, `Online`, `Power`, `PowerState`, `Muted`, `VolumeRaw`, `VolumeDb`, `ActiveSourceIndex`, `ActiveSourceName`, `Sources`) describe whichever amp is selected.
- **Discovery:** `KnownAmps` lists every amp ever heard as `(ip, device_name, online, model_name)`, never pruned; a silent amp flips to `online = false` after 8 s. `SelectedAmpIp` (`""` = nothing explicitly chosen) and `SelectAmp(ip)` (`""` clears; an unheard IP is accepted, as manual entry). The selection is persisted by the daemon.
- **Auto-select:** with nothing chosen and exactly one known amp, that amp drives the primary properties; with zero or two or more, they show the not-connected state rather than guessing.
- **Model name** is resolved over mDNS (`_spotify-connect._tcp`, `mdns-sd` crate), trusted only for an IP already heard over UDP, resolved once and never cleared. `DeviceName` is `model_name` if known, else the raw UDP name.
- **Power** is three-state (`Off` / `Booting` / `On`); `BeginPowerOnBoot(ip)` starts tracking a boot, which falls back to Off after a 20 s `BOOT_TIMEOUT`, also for a selected amp not yet heard.
- **`NotifyVolumeCommand` / `NotifyMuteCommand`** record the widget's optimistic value (see section 3) and emit `VolumeCommandNotified` / `MuteCommandNotified`, so a command from another tool (an MPV script) shows the widget's OSD. Changes the daemon only observes from the amp never take that path, and the widget filters its own echoes in `PendingAmpState.qml`.
- **Structured properties reach QML as an opaque `QDBusArgument`** (arrays of structs, dicts): no keys, no length. Scalars round-trip; for structured control data prefer a JSON string property.

## 3. State and behaviour

**The daemon owns pending command state.** After `NotifyVolumeCommand` / `NotifyMuteCommand`, `VolumeDb` / `Muted` show the commanded value until a broadcast confirms it or 400 ms pass (`PENDING_COMMAND_TIMEOUT`), then fall back to the amp. One owner means every surface (panel icon, flyout, OSD, tooltip) shows the same value; per-view copies diverged before Phase 5.

**Shared cross-view state is a root-anchored `QtObject`, forwarded as a `required property`.** `PendingAmpState`, `VolumeSettings`, `TransparencySettings` and `ThemeSettings` are instantiated once at `main.qml`'s root (the one owner that outlives both representations) and passed down `CompactRepresentation → FlyoutPopup → FlyoutContent`. Never reach into a sibling's state; there is no QML singleton in this KPackage. `required` makes a missed hand-off fail at load instead of silently diverging. Per-file constants with nothing to keep in sync (`Theme.qml`) are re-instantiated per file instead.

**Post-boot volume hold.** The amp misreports its volume after a boot and drops volume commands sent too early (gotchas #8, #9), so after a widget-initiated power-on confirms, the startup volume is sent 500 ms later and the display holds that value until a confirmed match after the send, or 1.5 s (`PendingAmpState.qml`).

**Controls are disabled unless the amp is On** (gotcha #10). Every input except power (slider, −/+, mute, source row, panel wheel, middle-click, the settings clamp) requires `powerState === "On"`; dimmed to 0.4 with last-known labels kept. Power stays live while Off and is disabled while Booting.

**The hard volume limit is enforced in the protocol crate.** The volume constructor clamps to the configured hard limit itself (`hard_limit_db`), so no caller can bypass it; QML range limiting is a convenience, not the safety. The floor is UI-only and never reaches the wire. A limit change clamps the amp at once, in one command.

**Every source switch sends the startup volume** (gotcha #5), so no casual gesture is bound to cycling sources.

**Flyout overlay lists are plain `QtQuick.Controls.Popup`s, not ComboBox.** The amp list and source list are Popups we own, content in a synchronous `ColumnLayout` + `Repeater` so the height is known before `open()`. `FlyoutContent.qml` holds one bool per list, opens and closes them imperatively and keeps them mutually exclusive. Restyling a ComboBox's popup broke three times: its ListView gets its model only once visible and its height chases the delegates.

**The flyout is a `PlasmaCore.Dialog` with `NoBackground`.** It is the only popup class that drops the theme's frame and so allows real transparency; `AppletPopup` (`PlasmaWindow`) has no `NoBackground`. The Dialog deliberately leaves `appletInterface` unset, so it never writes `popupWidth` / `popupHeight` into the applet's config.

## 4. Settings dialog

**Plasma provides the dialog.** `Plasmoid.internalAction("configure")` already opens one with Keyboard Shortcuts and About; `contents/config/config.qml` + `main.xml` add our General page beside them (they cannot be removed). No `metadata.json` key is involved.

**`ConfigCategory.source` resolves relative to `contents/ui/`,** wherever `config.qml` lives, for bare strings and `Qt.resolvedUrl` alike. Our pages live in `contents/config/`, so they are referenced as `"../config/ConfigGeneral.qml"`. The wrong path shows up as a misleading Kirigami `PageRow` "Could not convert argument" error that breaks every other page for that dialog session.

**Every setting persists to KConfig, not just applies its effect.** Each control has a `main.xml` entry, is read on load and written on change; a control that only drives its effect resets on the next open. Exception: a control that mirrors external state (Launch at login shows real `systemctl --user is-enabled` output) stores nothing. Verify settings work through a dialog reopen and a widget reload, not an in-session toggle.

**Non-KConfig controls ride Apply/OK through two undocumented page hooks:** a `bool unsavedChanges` property (enables Apply, triggers the discard prompt) and a `saveConfig()` function (called on Apply and OK before the `cfg_*` copy-back, so it must not touch `cfg_*`). OK closes the dialog at once, so an async failure can only be logged and re-queried on the next open; only Apply can show it inline. Classify `systemctl --user is-enabled` by its stdout token, not its exit code (`disabled` and "bus unreachable" both exit 1).

**One About page icon for every theme.** Plasma renders `metadata.json`'s icon name through the icon theme, once per shell process, and our page never coexists with the About page, so nothing of ours can change it. Do not plan a light/dark About icon without a new Plasma API.

**The Add Widgets picker icon is a theme icon, not a bundled file.** `KPlugin.Icon` is resolved by name through `QIcon::fromTheme`, so the icon is installed into hicolor (`~/.local/share/icons/` by `install-plasmoid.sh`, `/usr/share/icons/` by the PKGBUILD). The panel icon is a separate mechanism (`Plasmoid.icon` set to the bundled SVG in `main.qml`).

## 5. QML rules

**No `Qt.AlignBaseline` in a row with a child whose text or font can change at runtime.** The shared baseline moves with that child's metrics and drags its static siblings by a pixel or two; it happened three times (tooltip, toast). Use `Qt.AlignVCenter` on every child and pin the row's `Layout.preferredHeight` to the tallest child's measured implicit height across all its states. Measure it each time; a borrowed number left a 1 px shift.

**Size elements that change content to their worst case.** Buttons whose label or icon changes, and readouts that swap between a number and a word, get a fixed size so nothing beside them moves.

**Executable-engine command strings come from a small, fixed set.** The engine is shared by all of plasmashell, and every never-seen command string adds a key to every executable DataSource's property map and rebuilds its metaobject, a cost that grows until the shell restarts (a chime with a growing `--tick N` drove the UI thread to ~95 % CPU). Never put counters, timestamps or measured values in a command string: wrap counters at a measured bound (`--tick k`, k < 16), let the program fetch per-call data itself, or keep the value space small (one string per volume step). Count the distinct strings a new `connectSource()` call can produce and say so in a comment.

## 6. Light theme

A Dark / Light / Follow system setting (kcfg `theme`, default `system`). Design record: `docs/context-on-light-theme-arc-phase-17.md`.

**Palettes.** `Theme.qml` holds no colours: fonts, sizes, radii and the volume icon map only. Every colour is a typed `required` token in `ColorPalette.qml`; `DarkPalette.qml` and `LightPalette.qml` only assign values; consumers declare `required property ColorPalette colors`. A new colour is a new token in all three files, with the dark value equal to what dark painted before. Branch on `colors.isLight` only where the themes need a different mechanism (a gradient or effect against a flat fill), never to choose between two colours.

**Who picks the palette.**
- Flyout, OSD toast and tooltip: `ThemeSettings.qml` (root-anchored), which exposes `flyoutPalette` and `osdPalette` separately so a per-surface split later is one key and one binding.
- Settings page: the **desktop's** scheme, since it cannot reach `main.qml`'s root. Plasma's own header, button bar, other tabs and About icon stay in the scheme's colours.
- Sidebar icon: picked from `SystemPalette.window`'s lightness, because it must be right synchronously.

**Follow system** reads the XDG portal's `org.freedesktop.appearance color-scheme` once plus a change watcher (`SystemScheme.qml`): `1` dark, `2` light; anything else, an error or no reply in 2 s falls back to `Kirigami.Theme.backgroundColor`'s brightness. Starts dark.

**One `LightPalette` for all four surfaces;** the owner kept the flyout's darker dim/faint text everywhere. In light the flyout follows the transparency setting, the toast and tooltip are opaque white; dark keeps their hardcoded 0.94 gradient. Controls use the fixed-k opacity model in both themes (`ColorPalette.controlColor()`).

**Gold effects** (`GradientMask`, `GradientText`, `GoldSphere`, `CardShadow`, all `MultiEffect`):
1. Build effect items in a `Loader { active: colors.isLight }` with layers on from creation; toggling `layer.enabled` later stopped masking after a theme flip. Keep the plain item in the layout with transparent text and paint over it, so geometry is identical in both themes.
2. Soften the mask edge on solid strokes and text (`maskThresholdMin` 0.5, `maskSpreadAtMin` 1.0); the default is a hard, jagged cut. A blurred shadow's cut-out (`CardShadow`) doesn't need it: measured, the straight edges are identical and the corners differ by at most 10/255. Do not force `layer.textureSize`.
3. A shadowed MultiEffect keeps its creation-time geometry: toggle the shadow after every size change, and test any resizable effect item through a resize.
4. Mask and shadow need two stages; one MultiEffect doing both misaligns the mask.

**Capture rule:** offscreen rendering uses the software scenegraph and paints effects blank, so pixel captures run on Wayland and `grabToImage` output is composited onto a solid backdrop before judging. `scripts/test-qml.sh` runs offscreen and stays geometry-only.

## 7. Decided against

**Flyout radius stays 16 px** (mockups draw 12; matches Better Blur DX's corner radius and the 7.14.0 precedent). The old Darkly corner seam came from Darkly's Bezier frame corner under our circular one; the `NoBackground` Dialog removed the frame, so it is gone. Don't hand-replicate a theme's corner curve.

**No blur setting.** Real blur needs `KWindowEffects::enableBlurBehind`, which is C++ only. Users can get a frosted flyout themselves by adding `org.kde.plasmashell` to Better Blur DX's force-blur list (corner radius 16 to match); the widget neither ships nor controls it, so the Transparency setting is the only appearance control we own.

**Real transparency is impossible on a shell-managed popup** (`AppletPopup` has no `NoBackground`; a theme's translucent frame is the theme's doing), which is why the flyout is a hand-built `Dialog` (section 3).

**No automatic text colour from the wallpaper.** Prototyped on 2026-09-30 and dropped by the owner (open-ended calibration, out of scope); fixed colours per theme instead. If it comes up again: `org.kde.PlasmaShell.grabContainmentImage` stalls the whole shell while it renders and cannot be called from the widget's own QML, and Plasma emits no wallpaper-changed signal.

**Not planned:** "Forget remembered amps" (known amps are never persisted, and the active one could never be forgotten); SAM, Night Mode, Bass and Treble (no known wire commands).
