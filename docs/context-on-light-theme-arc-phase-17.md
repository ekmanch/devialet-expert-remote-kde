# Light Theme Arc (Phase 17) — Investigation & Design Document

Saved verbatim from the plan approved by the project owner on 2026-09-26
(rev 3, after two review rounds), so the report outlives the planning
session. Branch `feature/light-theme`. Investigation only at the time of
writing; no implementation code had been written or modified. Every
file:line below was read in that session; commands ran on the dev machine
(CachyOS, Plasma 6.7.5, Qt 6.11.2, KF 6.30, qmllint 6.11.2). Inferences are
labelled. Mockup references are to the **v2** files (commit 8526a10):
`design/mockups/<dir>/Devialet Expert Remote <Surface> Design Mockup v2.html`.
The live phase status is tracked in TODO.md's Phase 17 entries, not here.

Rev 3 folds in the second review: the spike is unnumbered and on its own
branch, portal `0` goes to the fallback, the reader only uses APIs shown in
the qmltypes, the qmllint claim is marked unproven until 17.11.0 proves it,
one `controlColor` mechanism, the Light-before-LightPalette window is stated,
and D8 is closed by the v2 mockups.

## Context

Four v2 mockups are the spec. They add a Dark / Light / Follow-system Theme setting
(default Follow system) that recolours the flyout, hover tooltip and OSD toast (not
the ConfigDialog page, which follows its window's scheme), a full light palette, and
seven behaviour changes that apply in both themes. The owner may later theme the
OSD/tooltip separately from the flyout/ConfigDialog; the plumbing must make that a
one-key, one-binding change.

Environment: screen scale is **2** (`kscreen-doctor`; kdeglobals `ScaleFactor=1.5` is
stale) so 1 mockup CSS px = 2 device px. `plasmoid/` == installed copy (`diff -rq`).

## Owner decisions

| # | Decision |
|---|---|
| D1 | "Follow system" source = **portal / application colour scheme** (`org.freedesktop.appearance color-scheme`), one source for both contexts. |
| D2 | **Remove the outer border** on flyout, OSD and tooltip; screenshot first; only if it reads badly add a barely-visible hairline. |
| D3 | Toast/tooltip alpha stays **hardcoded** as the mockups specify (dark OSD 0.96, tooltip opaque; light both opaque). Not forwarded from the transparency setting. |
| D4 | Flyout radius stays **16** (Phase 7.14.0 precedent, Better Blur DX `CornerRadius=16`, Darkly). |
| D5 | **Bundle the speaker SVGs** (deterministic across icon themes; needed as mask sources for the gold light variant). |
| D6 | About icon: **one icon**, no per-theme swap (Q6: no runtime mechanism exists). No phase. |
| D7 | Flyout mute button shows the **action** (unmuted → speaker+X "Mute"; muted → speaker+waves "Unmute"). OSD is not interactive and shows **state** (unmuted → speaker+waves; muted → speaker+X). |
| D8 | **Closed by v2**: one sphere gradient everywhere — `radial-gradient(circle at 32% 28%, #fcecc0 0%, #f0a623 38%, #a8710b 100%)` for thumb (flyout :99, configDialog :87), header/list dots (flyout :101), OSD/tooltip dot (:97), ConfigDialog dot (:89). Light slider/bar fill is **flat `#e2b865`** (flyout :98, OSD :95, tooltip :95, configDialog :86). Dark OSD/tooltip bars keep the copper sweep `#9a5a2c → #c17f4e → #e8a974` (OSD/tooltip :81); dark flyout fill stays solid copper (flyout :32). |
| D9 | The gradient-rendering **spike is unnumbered**, on `spike/gradient-rendering`, run right after 17.0.0/17.0.1; its components land in the arc only after the 2× captures are judged, cited by the first light phase that uses them. |

---

## Answers to the open questions

### 1. Theme plumbing

**Today.** `Theme.qml` is a plain `QtObject` (:28) holding palette colours (:32-75),
the flyout tint `#131313` (:109-110), the OSD/tooltip 0.94-alpha pair (:124-125),
fonts (:160-175), radii/sizes (:187-201) and the text source glyphs (:216-225). It is
instantiated 10 times: FlyoutContent.qml:83, VolumeToast.qml:89,
VolumeHoverTooltip.qml:83, and in the ConfigDialog tree ConfigGeneral.qml:66 plus
SettingsRow:35, SettingsSwitch:32, SectionLabel:19, DbStepper:33, ThemeDropdown:47,
ChimeIconButton:41 (`Ui.Theme {}` via `import "../ui" as Ui`). Flyout children get it
as `required property Theme theme` (AmpHeader:32, VolumeBlock:65, ActionRow:67,
SourceSelector:44, Footer:51, AmpListOverlay:53, SourceListOverlay:41,
OverlayCardBackground:20). No `qmldir`/`pragma Singleton` anywhere (confirmed).

Cross-view precedent: `TransparencySettings.qml`, one instance at main.qml:236-240 fed
from `Plasmoid.configuration`, forwarded main.qml:352 → CompactRepresentation (:59,
:329) → FlyoutPopup (:118, :283) → FlyoutContent (:77) → VolumeBlock (:801), ActionRow
(:817), SourceSelector (:830), AmpListOverlay (:867), SourceListOverlay (:884) →
OverlayCardBackground (:30). `Plasmoid.configuration.*` is a live binding, so Apply
repaints without a reload (FlyoutContent.qml:760-762, proven in Phase 9.1.x).

**Correction to the brief:** VolumeToast and VolumeHoverTooltip receive **no**
transparency object (CompactRepresentation.qml:343-362, :399-401 pass none); they
paint Theme.qml's hardcoded 0.94 pair. Theme.qml:117-123 defers unification to a
"Phase 9.2.0" that TODO.md never had. CLAUDE.md's Phase 9.0.0 bullet states the
decision, not the code. With D3 the code stays; CLAUDE.md is corrected in 17.0.0.

**Design (recommended):**

- `Theme.qml` **stays per-file** with fonts, radii, sizes, icon map only. All colour
  properties move out.
- **Typed palette.** `Palette.qml` is the *type*: a `QtObject` declaring every token
  with a concrete type (`property color text`, `property color accentFill`, `property
  color sphereStop0/1/2`, `property bool isLight`, …) and **one** function:

  ```qml
  function controlColor(ts) {            // ts: TransparencySettings
      return isLight ? ts.withGlassAlpha(surface) : ts.withControlAlpha(surface);
  }
  ```

  `DarkPalette.qml` / `LightPalette.qml` are `Palette { … }` instances that only
  assign values (no function redeclaration, so no shadowing for qmllint to flag).
  Consumers declare `required property Palette palette`; `ThemeSettings` exposes
  `readonly property Palette flyoutPalette` / `osdPalette`. Token names follow the
  mockups' CSS variables; gradients are stored as named colour stops and composed by
  the spike's components.

  **Intended lint benefit, unproven until 17.11.0**: qmllint 6.11.2 has a
  `--missing-property` category (default warning; `qmllint --help` :154-156) and this
  repo already lints files that use sibling-file types with no `qmldir` (Phase
  12.0.0 linted `ActionRow.qml`, which declares `required property Theme theme`,
  TODO.md:7175 entry), so type resolution through the implicit directory import is
  expected to work. Whether a misspelt member on a QML-defined type is actually
  reported is **not** shown yet. A missed rename does **not** fail at runtime — an
  unknown member on a `QtObject` reads `undefined` and a `color` binding falls back to
  its default silently — which is exactly why 17.11.0 plants a deliberate
  `palette.copperBrigth`, records the real qmllint output in TODO.md, and reverts it.
  If qmllint stays silent, the fallback is a `Component.onCompleted` token audit in
  `Palette.qml` (iterate the declared property names once per consumer in a debug
  build), decided at that point.
- `ThemeSettings.qml`, root-anchored in `main.qml` like TransparencySettings:
  `required property string mode` ← `Plasmoid.configuration.theme`
  (`"dark"|"light"|"system"`), `property bool systemDark: true` (see Q2),
  `readonly property bool resolvedDark: mode === "system" ? systemDark : mode ===
  "dark"`, **two** palettes from day one — `flyoutPalette` and `osdPalette`, both
  `resolvedDark ? dark : light`. Flyout files bind `flyoutPalette`; toast and tooltip
  bind `osdPalette`. A future split = one more kcfg key + one binding here. Plus
  `property string harnessOverride: ""` that wins over `mode` when non-empty.
- Forwarding: the TransparencySettings chain, **plus** two new hops
  CompactRepresentation → VolumeToast / → VolumeHoverTooltip (`required property
  ThemeSettings themeSettings`).
- ConfigDialog tree has no path to `main.qml`, so `ConfigGeneral.qml` owns a small
  `PageTheme` resolver: `palette: systemDark ? darkPalette : lightPalette`, with
  `systemDark` from the same portal reader (Q2). Sibling components take `required
  property Palette palette` forwarded from ConfigGeneral. If the page should later
  follow the widget setting instead, that is this one binding (`cfg_theme`).
- Setting: one new `main.xml` entry `theme` (String, default `system`) next to
  `transparencyEnabled` (main.xml:45-50). `config.qml` unchanged (config.qml:89-95).

### 2. "Follow system": what each context can see

- Kirigami picks its colour plugin **per QQmlEngine**: `PlatformTheme::
  qmlAttachedProperties` reads `engine->property("_kirigamiTheme")` and calls
  `PlatformPluginFactory::findPlugin(name)`; empty name → `QQuickStyle::name()`;
  plugins are matched by **filename substring** (kirigami v6.30.0 `platformtheme.cpp`,
  `platformpluginfactory.cpp`, fetched). Both plugins are mapped in the running
  plasmashell (`/proc/1172/maps`: libplasma's `KirigamiPlasmaStyle.so` and
  qqc2-desktop-style's `org.kde.desktop.so`). `libPlasma.so.7` (PlasmaQuick is merged
  into it) contains the `_kirigamiTheme` string among applet strings (`strings`
  offset 4175); the setter was not located in the sixteen v6.7.5 source files fetched.
  **Inference:** the applet engine is served by `KirigamiPlasmaStyle`.
- `KirigamiPlasmaStyle` colours come from `Plasma::Theme::color()` (symbols in the
  .so). `Plasma::Theme` uses the Plasma Style's own `colors` file when present, else
  kdeglobals (libplasma `theme_p.cpp` `setThemeName()`). So in the **applet**
  `Kirigami.Theme` = Plasma Style colours, equal to the application scheme only when
  the Style ships no `colors` file.
- The **ConfigDialog** is a `PlasmaQuick::ConfigView` with its **own** `QQmlEngine`
  (`configview.cpp`: `engine = new QQmlEngine(q)`; nothing there sets
  `_kirigamiTheme`). Which plugin serves it is unresolved from source.
- **Portal** `org.freedesktop.appearance color-scheme` = `1` here (`gdbus … ReadOne`).
  xdg-desktop-portal-kde v6.7.5 `settings.cpp`: `qGray(QApplication::palette().
  window().color()) < 192 → 1 (dark) else 2` — it never returns `0` — and emits
  `SettingChanged` on `paletteChanged`. It tracks the **application scheme
  (kdeglobals)**, never the Plasma Style, and is D-Bus-activatable.
- `Kirigami.ColorUtils.brightnessForColor(c)` gives Dark/Light from a colour
  (KirigamiPlatform.qmltypes:12-27; re-exported by `org.kde.kirigami`, qmldir:7). No
  `isDark` exists on `Kirigami.Theme`; Plasma 6's `org.kde.plasma.core` exports no
  `Theme` type.
- This machine: Plasma Style `CachyOS-Nord-round` has **no `colors` file**, so it
  follows the application scheme `Darkly_modified` (`BackgroundNormal=21,21,21`). Both
  signals agree today.

| Context | Plasma Style colours | Application scheme (kdeglobals) |
|---|---|---|
| Applet engine (flyout/OSD/tooltip) | `Kirigami.Theme.backgroundColor` = `#151515`, brightness Dark (measured 17.0.1, 2026-09-26 13:23:39; plugin still inferred) | portal via D-Bus |
| ConfigDialog engine (status line, page) | `Kirigami.Theme.backgroundColor` = `#151515`, brightness Dark (measured 17.0.1, 13:43:27; plugin unknown) | portal via D-Bus |

17.0.1 result: both engines report `Darkly_modified`'s window background. With
this Plasma Style shipping no `colors` file the two colour sources coincide, so
the measurement confirms the values but cannot separate the plugins; the
edge case stays theoretical and is covered by D1 plus 17.15.0's in-context
fallback.

**D1 = portal.** The two unknown cells still matter for one edge case (a Plasma Style
with its own colours could make the dialog chrome disagree with our portal-driven
page). **17.0.1** measures them with a temporary `console.log` in `main.qml` and
`ConfigGeneral.qml`; it needs a plasmoid edit + `kpackagetool6 --upgrade` +
`plasmashell --replace` + the owner opening the dialog once, run as 17.0.1
immediately after approval, before any phase code.

**Portal reader contract** (`SystemScheme.qml`, one object, used by both
`ThemeSettings` and `PageTheme`). Only APIs shown in
`/usr/lib/qt6/qml/org/kde/plasma/workspace/dbus/dbusplugin.qmltypes` are used:

- `systemDark` **starts `true`** (today's look) and changes only when a value arrives.
- On start, `Dbus.SessionBus.asyncCall(message, resolve, reject)` (qmltypes :302-306;
  no timeout parameter exists) with `ReadOne("org.freedesktop.appearance",
  "color-scheme")`. Because the portal is activatable, this call autostarts it; no
  "appears later" handling and no `DBusServiceWatcher` (the type exists, qmltypes :26,
  `LayoutProbe.qml:78`, but is not needed here).
- Mapping: `1 → dark`, `2 → light`. **`0` ("no preference") and any other value →
  the same fallback as an error**, since the portal does not know.
- Fallback (reject callback, unexpected value, or a **QML `Timer` of 2 s racing the
  reply** — that is what the timeout is): `systemDark = Kirigami.ColorUtils.
  brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark`
  (Plasma Style colours, second-best), logged once. A late reply after the timer
  still wins when it carries `1`/`2`.
- `Dbus.SignalWatcher` (as in `PendingAmpState.qml:440`) on
  `org.freedesktop.portal.Desktop` / `/org/freedesktop/portal/desktop` /
  `org.freedesktop.portal.Settings`, acting only on `SettingChanged` whose namespace
  and key match, same mapping.

### 3. Gradient text / fills in QML (no C++)

- `Qt5Compat.GraphicalEffects`: **installed** (`qt6-5compat 6.11.2`); not used here;
  would add a runtime dependency to the PKGBUILD. **Not recommended.**
- `QtQuick.Effects` `MultiEffect` (qt6-declarative): **installed and already used**
  (VolumeToast.qml:82,200-209; VolumeHoverTooltip.qml:69,140-141). qmltypes expose
  `maskEnabled/maskSource/maskThresholdMin/maskSpreadAtMin/maskInverted` (:195-250)
  and `shadowEnabled/Blur/Color/Opacity/Scale`. Docs: `maskSource` = ShaderEffectSource,
  a `layer.enabled` item, or an Image; alpha masks. **Gradient text** = gradient
  `Rectangle` sized to the `Label` with `layer.effect: MultiEffect { maskEnabled:
  true; maskSource: label }`; glow = `shadowEnabled` gold at zero offset. Docs do not
  state mask-vs-shadow order → spike question.
- `QtQuick.Shapes` (qt6-declarative): **installed and already used** (ActionRow :60,
  ThemeDropdown :36, ChimeIconButton :27). `ShapePath.fillGradient` Linear/Radial/
  Conical (qmltypes :215-603), `capStyle/joinStyle/strokeStyle` (:443-470),
  `CurveRenderer` (:44-52, :112). **No stroke gradient** — the gold glyph strokes use
  the mask trick (Shape as `maskSource` over a radial fill) or per-theme SVG files via
  `Image`. Recommend the mask trick: one `GradientMask` component for text, glyphs,
  thumb and dots; the spike decides.
- Custom `ShaderEffect` needs pre-baked `.qsb` (`fragmentShader` is a `QUrl`, QtQuick
  qmltypes :14917-14930; `qsb` present). Unneeded if the above holds.
- Radial sphere: `Rectangle.gradient` is linear-only; `Shape` + `RadialGradient` +
  MultiEffect drop shadow. Light bars are now flat (D8), so only the sphere, the
  gradient text and the glyph gold need the spike.

### 4. Outer flyout border — our QML

All three surfaces are `PlasmaCore.Dialog` + `NoBackground` (FlyoutPopup.qml:126-128,
VolumeToast.qml:100-103, VolumeHoverTooltip.qml:86-88): no Plasma frame SVG. The grey
edge is **our own** 1px border: FlyoutContent.qml:767-768 (`theme.divider` =
`Qt.rgba(1,1,1,0.08)`, Theme.qml:69), VolumeToast.qml:155-156,
VolumeHoverTooltip.qml:97-98. KWin adds nothing (kwinrc: no outline effect; Better
Blur DX blurs, draws no edge — inference from its config; decorations never apply to
undecorated popups). A `NoBackground` Dialog also gets **no KWin shadow** (inference,
confirmed by screenshot in 17.5.0). **D2**: remove, screenshot, judge.

### 5. Mute/Power button widths

`ActionRow.qml` root `GridLayout` (:63), `columns: 2`, `columnSpacing: 8`, margins 16
(:128-135). Since Phase 12.0.0 the split is **static**: `TextMetrics` worst-case labels
(:107-116) → equal worst-case margins (:117-126); `Layout.fillWidth: true` +
`Layout.preferredWidth` per button (:143-146, :226-229); measured 108/152 px in every
mute×pow state (:103-106; TODO.md:7175-7240). Installed copy == HEAD, so "currently
resizes them" is not what the code does; the only motion on a toggle is the icon+label
re-centring inside its button. 17.4.0 logs widths across `--vary mute,pow` first.

Cleanest 11:14: drop the `TextMetrics` and margin maths; `muteButtonWidth =
Math.round(buttonsAvailable * 11 / 25)`, `powerButtonWidth = buttonsAvailable -
muteButtonWidth`. 300 − 32 − 8 = 260 px → **114 / 146** (mockup :408
`11fr 14fr`, gap 8.5 → 114.2/145.3). Worst-case margins: "Unmute" 25.5 px, "Powering
on…" 20 px per side.

### 6. About page icon — no runtime switch exists, by either theme

- The About page is Plasma's `AboutPlugin.qml:112-131`: `Kirigami.Icon { source:
  page.metaData.iconName }`, no `isMask`/`color`; the name comes from
  `metadata.json:12`, read once per plasmashell process.
- Pages are **replaced**, not stacked (`AppletConfiguration.qml:110-113`: `push` only
  at depth 0, else `replace`). Our General page is destroyed when About is shown, so
  nothing of ours can reach the About icon item at runtime.
- The only way to change it is rewriting the installed `metadata.json`/SVG and
  restarting plasmashell — writes into the install, breaks the AUR path. Rejected.
- Scheme-following recolouring (`kiconcolors.h:154-161`) substitutes eight flat
  semantic classes only, under icon themes with `FollowsColorScheme=true` (Tela/breeze
  yes, hicolor no), no gradients. Per-icon-theme files follow the icon theme, not the
  scheme. `AboutPlugin.qml:118-125` accepts an `Icon` starting with `/` (bundled
  file) but that breaks the picker's `QIcon::fromTheme` and is still one file.

**D6**: one icon. Current tile is self-contained and legible on white.

### 7. Light theme + transparency

Today: `transparencyEnabled` / `transparencyPercent` (main.xml:45-50; the number is
**opacity**) → `TransparencySettings.alpha` (:50) → `withAlpha` on the flyout panel
(FlyoutContent.qml:770-771). Controls: constant `controlAlpha = 0.1` over `surface`
(TransparencySettings.qml:126-132; ActionRow.qml:159-161,243; SourceSelector.qml:117;
VolumeBlock.qml:177,222,343); overlay cards `overlayAlpha = clamp(alpha + 0.20, 0.70,
1)` (:157-163; OverlayCardBackground.qml:33,48-49). Opaque: `surface3` glyph boxes
(gone after 17.7.0), slider track, row hovers, gear hover.

Light (flyout :56-59, :84-89): background `rgba(255,255,255,alpha)`; buttons, source
row, ± steppers, source chip `rgba(255,255,255, 0.35 + 0.65·alpha)` (`--glass`, :67,
:85); overlay popups `--popup-bg:#ffffff` (:75) carries no alpha var despite the :56
comment — keep the existing overlayAlpha formula in both themes, noted. Dark keeps the
0.1 constant. Mechanism: `Palette.controlColor(ts)` above; `TransparencySettings`
grows `glassAlpha` / `withGlassAlpha(c)`. Glyphs/dots keep painted gold, so Better
Blur DX frosts the whole thing.

Toast/tooltip (D3): hardcoded — dark OSD `#121212` at 0.96 (OSD :124), tooltip opaque
(tooltip :121), light both opaque white (OSD :118).

---

## Mockup notes carried into the phases (v2 lines)

1. Header dot: `.amp-header .amp-dot` 12px (flyout :140); live **8**
   (AmpHeader.qml:73-79). Amp list dots 10 (:141; live 7, AmpListOverlay.qml:213-220);
   tooltip 7 (tooltip :133; live 5, VolumeHoverTooltip.qml:134-150); footer 4 stays.
2. Brand tile 37 (configDialog :236-242), live 36 (ConfigGeneral.qml:417-418) → 37.
   Dark ring `#654c3a` + disk `#e3a06a` (:245-249); light ring sweep `#ecd3a0 → #dcb068
   → #cfa052`, disk `#efc977 → #e0aa4b → #cf9738`, no sphere (:250-255).
3. Two gold text gradients: readout `#dca136 → #f3cf7c` + glow (flyout :110-115, OSD
   :161-166, tooltip :145-150 incl. the "Muted" word) vs heading/word `#a8710b →
   #d99a1f → #efc36a` (OSD `.gold-text` :104-110 for "Muted"; configDialog
   `--label-bg` :90, :102-105, :111-114). Implement as written.
4. Fills per D8. Muted bar: dark `#5c5c60`, light `#d8d3cb` (OSD :87, :103, :176).
5. Source glyph containers 26px/20px glyph in the row, 22px/17px in the list (flyout
   :131-133); strokes 1.6 / 1.1 (:128-129); light `drop-shadow(0 2px 2.5px
   rgba(160,110,10,0.35))` + `glyphGold` stroke/fill (:134-136).
6. Speaker glyphs (D5/D7): paths at flyout :565-566 / OSD :228,:245, filled body +
   stroked waves/X, rendered with `Kirigami.Icon { isMask: true }` so the palette
   colours them; light muted OSD icon gets the gold treatment (OSD :144-148).
7. Wordmark eyebrow light gradient `#97691f → #cf9c45` (flyout :103, :116-119).
8. Ticks: 16px box, 2-unit round stroke (flyout :452-453). Action row `11fr 14fr`
   (:408). Outer border `0` (flyout :280, OSD :125, tooltip :122).
9. ConfigDialog light: switch-on gold gradient + sheen (:93), white knob (:76, :97),
   selected segment outlined in text colour (:95, :315), neutral stepper values
   (:107), status-line value gradient bold (:111-114), Theme row copy and IDs
   (:577-585).

---

## Unnumbered spike — `spike/gradient-rendering` (after 17.0.0 / 17.0.1, before
## any light phase)

Standalone `/usr/lib/qt6/bin/qml` driver, no plasmoid change, on its own branch per
the project's spike convention (`spike/flyout-appletpopup-rebuild`,
`experiment/real-transparency`). Questions: MultiEffect mask for gradient text + glow
(one stage or two?), Shape radial sphere + drop shadow, gradient-stroked glyph via
mask, bundled speaker SVG as mask source; all captured at scale 2 and judged by the
owner. Output: `GradientMask.qml`, `GoldSphere.qml`, `GradientText.qml` drafts + a
go/no-go on Qt5Compat (expected: not needed). Components land in the arc only after
the captures are judged; **17.19.0/17.20.0/17.21.0 cite the merged spike**. If
gradient text reads badly at 2×, the light mockups change before plumbing is built.

## Phase breakdown — Phase 17.x.x (own block in TODO.md "Up next", each moved to
## "Done" on completion, per the memory rule)

Order: record + measure, spike (unnumbered), dark-visible behaviour phases (each
checkable against the current harness baseline), zero-visual-change plumbing, then
the light surfaces. One concern per phase.

| Phase | Concern | Mockup | Verification |
|---|---|---|---|
| **17.0.0** | Record this report + decisions D1–D9 in TODO.md; CLAUDE.md corrections (Phase 9.0.0 alpha wording; radius 16 note; About-icon closure; spike branch noted as the next task) | all | n/a |
| **17.0.1** | Two-context `Kirigami.Theme` measurement: temporary `console.log` in `main.qml` + `ConfigGeneral.qml`, upgrade + `plasmashell --replace`, owner opens the dialog once, read `journalctl --user`, revert | none | journal lines quoted in TODO.md |
| *(spike)* | `spike/gradient-rendering`, see above | all light | owner judges 2× captures |
| **17.1.0** | Remove "Scroll over the panel icon to adjust" (`VolumeBlock.qml:359-373`) | flyout | harness smoke; new baseline `expected-17.json` (item gone, everything below shifts up by its height, nothing else) |
| **17.2.0** | Bundle the two speaker SVGs under `contents/icons/`; swap the flyout mute icon (`ActionRow.qml:184-208`) and the OSD icon (`VolumeToast.qml:191-219`, `Theme.volumeIconSources`) from theme names to the files, **same mapping as today** | flyout, OSD | `harness run --vary mute` crops; toast via the fakeamp `--notify` hook |
| **17.3.0** | Flip the flyout mapping to show the action (D7) (`ActionRow.qml:206,213`); OSD keeps state | flyout | `--vary mute` crops |
| **17.4.0** | Fixed 11:14 split (`ActionRow.qml:107-126`) → 114/146 px | flyout | `--vary mute,pow`: widths logged before/after, identical in all 6 states, margins ≥ 20 px |
| **17.5.0** | Remove the outer borders (flyout :767-768, toast :155-156, tooltip :97-98) (D2) | flyout, OSD, tooltip | edge crops over dark and light backdrops (white-window recipe); owner looks; hairline fallback only if asked |
| **17.6.0** | Status dots: header 8→12, amp list 7→10, tooltip 5→7; drop the tooltip dot glow | flyout, tooltip | harness Δ report (header height must not change); tooltip = owner hover |
| **17.7.0** | Painted source glyphs: `SourceGlyph.qml` (QtQuick.Shapes, flat colour, `kind`+`size`), 20 px row / 17 px list, delete the `surface3` boxes (`SourceSelector.qml:132-145`, `SourceListOverlay.qml:154-167`) and `Theme.sourceGlyph` | flyout | `--vary src,slist`; 2× crops for stroke weight |
| **17.8.0** | Painted 16 px ticks (`Tick.qml`) replacing "✓" (`AmpListOverlay.qml:150-156,252-258`, `SourceListOverlay.qml:183-189`) | flyout | `--vary list,slist` |
| **17.9.0** | OSD/tooltip dark palette alignment: flat `#121212` (0.96 / opaque per D3), `#252525` lines, remove the muted-icon glow (`VolumeToast.qml:200-209`) | OSD, tooltip | toast capture; tooltip owner |
| **17.10.0** | Copper gradient bars on dark OSD/tooltip, muted bar colours | OSD, tooltip | toast capture; tooltip owner |
| **17.11.0** | **Typed palette, zero visual change**: `Palette.qml` type (+ `controlColor`) + `DarkPalette.qml`; Theme.qml loses its colours; flyout consumers take `required property Palette palette` (FlyoutContent instantiates `DarkPalette {}` for now); toast/tooltip/config components instantiate `DarkPalette {}` locally. **Includes the qmllint proof**: deliberate `palette.copperBrigth`, real output pasted into TODO.md, reverted; fallback audit if silent | none | full harness smoke vs `expected-17.json` → zero Δ; `scripts/test-qml.sh`; qmllint clean |
| **17.12.0** | `ThemeSettings.qml` + `main.xml` `theme` key + forwarding chain to the flyout; `harnessOverride` + `FlyoutContent.themeOverride` UiState hook + `theme` harness dimension. **Both `light` and `system` resolve to the dark palette until 17.19.0** (no LightPalette yet) | none yet | harness `--vary theme` → zero Δ; reload persistence check |
| **17.13.0** | Toast/tooltip hop: forward `themeSettings` from CompactRepresentation, bind `osdPalette` | none | toast capture identical; qmllint |
| **17.14.0** | ConfigDialog components take a forwarded `Palette` from ConfigGeneral's `PageTheme` (dark for now) | none | standalone driver screenshot identical; qmllint |
| **17.15.0** | `SystemScheme.qml` portal reader per the contract above; used by ThemeSettings and PageTheme | none visible | driver: fake `org.freedesktop.portal.Settings` on a private bus (`dbus-run-session`, python) returning 1 / 2 / 0 / error / no reply (timer path); live: owner flips the scheme, surfaces follow without reload |
| **17.16.0** | Extract `SegmentedControl.qml` from the two inline copies (`ConfigGeneral.qml:602-656`, :762-813), zero visual change | configDialog | driver screenshot identical; `saveConfig` path unchanged |
| **17.17.0** | Theme row (Dark / Light / Follow system) as the first Appearance row, writing `cfg_theme` (copy: configDialog :577). **Picking Light is visually a no-op until 17.19.0**; stated in the TODO entry | configDialog | driver TestEvent clicks; close/reopen + widget reload keep the value (CLAUDE.md rule); owner opens the real dialog |
| **17.18.0** | "Following your desktop's color scheme — currently …" status line (chime pattern, `ConfigGeneral.qml:830-872`, `escapeStyledText`), visible only for Follow system | configDialog | driver with fake portal values |
| **17.19.0** | `LightPalette.qml` + light flyout base: white surfaces, text/divider tokens, glass control alpha, card shadows, white overlay cards, flat `#e2b865` slider fill, gold sphere thumb (`GoldSphere` from the merged spike) | flyout | `--vary theme` light states; alpha sweep recipe; owner soak with Better Blur DX |
| **17.20.0** | Light readout: gradient digits + glow, grey "dB", gold wordmark eyebrow (`AmpHeader.qml:100`) (`GradientText` from the merged spike) | flyout | light crops; Δy 0 on the readout row (AlignBaseline house rule) |
| **17.21.0** | Light gold treatment on glyphs, dots, ticks (radial + warm shadow) (`GradientMask` from the merged spike) | flyout | `--vary theme,src,slist,list` |
| **17.22.0** | Light OSD: opaque white, gradient readout, gold muted glyph, gold-gradient "Muted", flat gold bar | OSD | toast capture via `--notify` |
| **17.23.0** | Light tooltip: opaque white, gold sphere dot, gradient value, flat gold bar | tooltip | owner hover; driver instantiating the tooltip's mainItem for pixel checks |
| **17.24.0** | Brand mark: ring + disk filling a 37 px tile, dark and light (`ConfigGeneral.qml:411-429`) | configDialog | driver both schemes |
| **17.25.0** | ConfigDialog light page base: white background, text/divider/control tokens, card shadows | configDialog | driver with light kdeglobals (memory recipe) |
| **17.26.0** | Gradient section headings + gradient bold status values (`SectionLabel.qml`, status lines) | configDialog | driver crops at 2× |
| **17.27.0** | Light switches (gold gradient track + sheen, white knob, `SettingsSwitch.qml`), neutral stepper values, outlined selected segment | configDialog | driver crops; owner opens the real dialog under a light scheme |
| **17.28.0** | Wrap-up: CLAUDE.md (Theme.qml = fonts/sizes only; typed Palette rule; portal reader contract; harness `theme` dim), README settings section, PKGBUILD dependency check (none added), final `expected-17.json`, owner soak, ready for the owner's commits/merge | all | full harness + test-qml + owner soak report |

### Verification tooling added inside the arc (no new dependencies)

- **Light captures without KConfig writes** (17.12.0): `FlyoutContent.themeOverride`
  as a UiState key — the probe assigns UiState keys onto FlyoutContent
  (`LayoutProbe.qml:62-63`, `FlyoutPopup.qml:270`, hooks `FlyoutContent.qml:554-560`)
  — forwarded to `ThemeSettings.harnessOverride`; `scenarios.py` gains a `theme`
  dimension.
- **Toast hands-free** (17.2.0): `fakeamp.py` only emits `PropertiesChanged` (`_emit`,
  :247-251); the toast shows on `VolumeCommandNotified`/`MuteCommandNotified` (Phase
  16.0.0). Add `--notify volume=<db>|mute=<bool>` emitting those Amp1 signals; capture
  with the white-window recipe.
- **Fake portal** (17.15.0): a short python `org.freedesktop.portal.Settings` on a
  private bus for the driver, covering 1 / 2 / 0 / error / silence.
- **Tooltip** stays an owner hover check (real pointer needed; memory rule).
