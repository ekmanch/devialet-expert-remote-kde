# TODO

Build order for devialet-expert-remote-kde. Architecture decisions are in CLAUDE.md; this file is sequencing and status only.

The detailed record of every phase up to Phase 17 (investigations, measurements, owner decisions) that code comments and CLAUDE.md cite as "TODO.md's Phase X entry" is in this file's history at commit `5adc386` (`git show 5adc386:TODO.md`).

## Phase 1: Protocol, daemon and CLI

- [x] Cargo workspace with the protocol crate, the daemon and `devialet-ctl`, verified against the real amp

## Phase 2: Minimal plasmoid

A bare plasmoid bound to the daemon's D-Bus properties, with one working command.

- [x] 2 Live volume display and a −1 dB button round-tripped to the real amp
- [x] 2.5 Cleanup: `devialet-ctl` resolved through `PATH`; the D-Bus reactivity claim labelled as inference

## Phase 3: Functional controls and the daemon

Every control working against the real amp with default styling, and the daemon made multi-amp, supervised and mDNS-aware.

- [x] 3 Volume slider and steps, mute, power and source picker on real D-Bus properties
- [x] 3.5 Multi-amp daemon support
- [x] 3.6 systemd user unit: create, enable and verify
- [x] 3.7 mDNS amp model name resolution

## Phase 4: Styling, amp picker, settings page and panel input

The copper/graphite look, the move from system tray to panel applet, the first settings page and the panel icon's scroll and middle-click.

- [x] 4.0 Main view restyled to the flyout mockup
- [x] Panel-pinned applet instead of a system tray item
- [x] 4.1 Amp picker UI
- [x] 4.2 Amp selection persisted in the daemon
- [x] 4.2.1 Settings trigger: gear icon instead of dots
- [x] 4.2.2 Wider click and drag target on the volume slider
- [x] 4.2.3 Power button hover green when off
- [x] 4.2.4 Power button hover red when on
- [x] 4.2.5 Panel icon: Glow Dot variant
- [x] 4.3.0 Three-state `PowerState` with boot tracking in the daemon
- [x] 4.3.1 Booting presentation in the widget
- [x] 4.4.0 General page added to Plasma's ConfigDialog
- [x] 4.4.0.1 General category icon in the settings sidebar
- [ ] 4.4.0.2 About page polish, including its own icon
- [x] 4.4.1 Full settings page UI, controls not yet wired
- [x] 4.4.2 Volume step size wired
- [x] 4.4.2.1 Blur row moved below Transparency and dimmed with it
- [x] 4.4.2.2 Blur background setting removed
- [x] 4.4.3 Transparency on/off wired and persisted
- [x] 4.5.0 Scroll over the panel icon to adjust volume, with an on-screen indicator
- [x] 4.5.1 Scroll over the volume slider
- [x] 4.5.2 Middle-click the panel icon to mute
- [x] 4.5.3 Tooltip and OSD polish and positioning
- [x] 4.11 Custom panel icon

## Phase 5: Daemon-owned pending state

Optimistic volume and mute state moved into the daemon, so every surface shows the same value.

- [x] 5.0.0 Daemon-owned pending `VolumeDb` / `Muted`
- [x] 5.0.1 One shared, root-anchored QML consumer
- [x] 5.0.2 Cut over, then delete what is redundant
- [x] 5.0.3 Live verification across every consumer

## Phase 7: Flyout rebuild

The flyout rebuilt as a hand-made popup, first on `AppletPopup`, then on `PlasmaCore.Dialog` for real transparency.

- [x] 7.0.0 AppletPopup infrastructure spike
- [x] 7.1.0 The spike promoted into the real flyout shell
- [x] 7.2.0 Verification harness
- [x] 7.3.0 Amp header and amp list
- [x] 7.4.0 Volume block: readout, source chip, slider
- [x] 7.5.0 Action row: mute and power
- [x] 7.6.0 Source selector and footer
- [x] 7.7.0 Full-suite verification gate
- [x] 7.8.0 Cutover
- [x] 7.9.0 Dialog + `Overlay.overlay` spike
- [x] 7.10.0 FlyoutPopup rebuilt on `PlasmaCore.Dialog`
- [x] 7.11.0 Full re-verification
- [x] 7.12.0 Darkly corner-radius mismatch (gone on its own)
- [x] 7.13.0 Cleanup
- [x] 7.14.0 Amp list and source selector restyled to the updated mockup

## Phase 8: Volume limits

Floor, hard limit and startup volume as persisted settings, with the hard limit enforced in the protocol crate.

- [x] 8.0.0 Persistence and settings UI for the three dB values
- [x] 8.0.1 Startup volume wired through `devialet-ctl`
- [x] 8.1.0 Hard-limit clamp in the shared protocol crate
- [x] 8.2.0 Slider spans floor to hard limit
- [x] 8.3.0 Settings page blocks an invalid floor/ceiling order and self-heals
- [x] 8.4.0 Immediate clamp when a limit changes

## Phase 9: Transparency

The transparency setting wired through to the flyout's gradient and its controls.

- [x] 9.0.0 Design pass: how transparency reaches `Theme.qml`
- [x] 9.1.0 Flyout gradient wired
- [x] 9.1.1 Control and overlay opacity track the panel alpha, with a Darkly colour update
- [x] 9.1.2 Transparency slider: scroll to adjust and a larger hit target

## Phase 10: Volume feedback chime

A volume-compensated chime after volume changes, like Plasma's Audio Devices applet, with its own settings.

- [x] 10.0.0 Investigation: Audio Devices feedback parity
- [x] 10.1.0 Volume-compensated chime (spike, merged)
- [x] 10.1.1 Chime settings UI
- [x] 10.1.2 Chime on/off wired
- [x] 10.1.3 Chime sound source wired

## Phase 11: Settings page

Launch at login and the page's shipped defaults and wording.

- [x] 11.0.0 Launch at login reads and writes the real systemd state
- [x] 11.1.0 Amplifiers section removed (known amps are never persisted)
- [x] Shipped defaults reviewed (transparency 90 %, floor −50 dB)
- [x] Setting names and descriptions per mockup v28; asset and mockup folders reorganised

## Phase 12: Flyout action row

- [x] 12.0.0 Mockup v12: mute icon follows state, weighted action buttons

## Phase 13: Install and v1.0.0

An install script for the binaries, the systemd unit and the plasmoid, then the first release.

- [x] 13.0.0 `devialet-ctl` and `devialet-chime` built and placed on `PATH`
- [x] 13.0.1 Plasmoid install step
- [x] 13.0.2 systemd user unit install
- [x] 13.0.3 Combined `install.sh`
- [x] 13.0.4 Uninstall script
- [x] Flyout cursor: pointing hand on the amp header only (mockup v14)
- [x] 13.0.5 README rewrite
- [x] Custom plasmoid icon in the Add Widgets picker
- [x] 13.1.0 Tag v1.0.0 and the GitHub release

## Phase 14: AUR

- [x] 14.0.0 PKGBUILD, install hook and `.SRCINFO`
- [ ] 14.1.0 Submit to the AUR and install it with a helper on a clean Arch system

## Phase 15: KDE Store

- [x] 15.0.0 Abandoned: a `.plasmoid` cannot carry the daemon, the CLI or the systemd unit

## Phase 16: OSD for PC-originated commands

- [x] 16.0.0 A daemon signal for volume/mute commands sent by other tools, so they show the widget's OSD

## Phase 17: Light theme

A Dark / Light / Follow system setting across the flyout, OSD, tooltip and settings page. Spec: the mockups under `design/mockups/{configDialog,flyout,OSD,tooltip}/`; design and decisions in `docs/context-on-light-theme-arc-phase-17.md`.

- [x] 17.0.0 Record the arc
- [x] 17.0.1 Two-context `Kirigami.Theme` measurement
- [x] 17.0.2 Gradient rendering spike
- [x] 17.1.0 Scroll hint removed
- [x] 17.1.1 Source list scrolls correctly
- [x] AIR source name shown as the acronym
- [x] 17.2.0 Speaker glyphs bundled
- [x] 17.3.0 Flyout mute button shows the action
- [x] 17.4.0 Fixed 11:14 action-button split
- [x] 17.5.0 Outer borders removed
- [x] 17.6.0 Larger status dots
- [x] 17.7.0 Painted source glyphs
- [x] 17.8.0 Painted ticks
- [x] 17.9.0 OSD icon box with a transparent fill (dark)
- [x] 17.10.0 Copper gradient bars on the dark OSD and tooltip (dropped)
- [x] 17.11.0 Typed palette, no visual change
- [x] 17.12.0 `ThemeSettings`, the kcfg key and the flyout chain
- [x] 17.13.0 Theme forwarded to the toast and tooltip
- [x] 17.14.0 Settings page components take a forwarded palette
- [x] 17.15.0 `SystemScheme.qml` portal reader
- [x] 17.16.0 `SegmentedControl.qml` extracted
- [x] 17.17.0 Theme row
- [x] 17.18.0 Follow-system status line
- [x] 17.19.0 `LightPalette` and the light flyout base
- [x] 17.19.1 Light-glass spike
- [x] 17.19.2 Fixed-k light controls
- [x] 17.19.3 Light flyout re-based on mockup v22
- [x] 17.20.0 Light readout and wordmark
- [x] 17.21.0 Light gold glyphs and dots
- [x] 17.21.1 Six sources without a scrollbar
- [x] 17.22.0 Light OSD
- [x] 17.23.0 Light tooltip
- [x] 17.24.0–17.27.0 Light settings page
- [x] 17.28.0 Wrap-up
- [x] 17.29.0 Rust tests re-run on `main`

## Later

- [ ] The verification harness can leave the real daemon down: restart it from its enabled state and assert it owns the bus name after every run
- [ ] Option for the OSD and tooltip to follow the desktop's appearance instead of the widget's theme (owner idea, not decided)
