// Single shared owner of the Appearance section's transparency setting
// (transparencyEnabled + transparencyPercent from main.xml), resolved once
// into the alpha every translucent surface paints with - the flyout's panel
// tint (FlyoutContent.qml), the OSD toast (VolumeToast.qml) and the hover
// tooltip (VolumeHoverTooltip.qml). Phase 9.0.0 design; wired in 9.1.0/9.2.0.
// Phase 9.1.1 adds two more computed alphas: controlAlpha (interactive
// chrome - buttons, source chip, closed source row) and overlayAlpha
// (the AmpListOverlay/SourceListOverlay dropdown cards) - see each
// property's own comment. Revised same-day after the first controlAlpha
// formula (a flat floor) was rejected live for an enormous panel/chrome
// gap - see controlAlpha's own comment for the compositing-corrected
// replacement, and TODO.md's Phase 9.1.1-revision entries for the full
// history of both formulas. Phase 17.19.2 moved controlAlpha into the
// palette (ColorPalette.controlAlphaK); overlayAlpha stays here.
//
// Same shape as VolumeSettings.qml / PendingAmpState.qml: a plain QtObject
// (no `pragma Singleton` - no qmldir exists anywhere under contents/ui/),
// instantiated exactly once in main.qml with its two inputs bound
// declaratively to Plasmoid.configuration there (main.qml is proven to have
// that context property; a bare QtObject file is not - see VolumeSettings.
// qml's header), and forwarded down via `required property` through
// CompactRepresentation.qml -> FlyoutPopup.qml -> FlyoutContent.qml, and
// from CompactRepresentation.qml straight into VolumeToast/VolumeHoverTooltip
// (both instantiated there). See CLAUDE.md's "Shared cross-view state" note.
//
// Why the alpha lives here and not in Theme.qml: Theme.qml is deliberately
// re-instantiated per consuming file (four sites, including the ConfigDialog
// page ConfigGeneral.qml, a separate QML tree with no access to main.qml's
// root-anchored objects). A `required property` on Theme.qml would break
// that page's `Ui.Theme {}`; a non-required default would silently let one
// surface fall back to a different alpha than the others - the exact
// divergence this object exists to rule out (owner decision, 2026-09-05:
// all three surfaces land on the same alpha). Theme.qml therefore keeps only
// the opaque base tint colours; this object supplies the alpha.
//
// percent is OPACITY, not transparency (owner decision, Phase 9.0.0):
// alpha = percent / 100, so 94 reproduces the OSD/tooltip's historical 0.94
// and 100 is fully opaque. `enabled == false` is exactly 1.0 - not a high
// value - which is what Phase 9.3.0's "off is truly opaque" check measures.
import QtQuick

QtObject {
    id: root

    required property bool enabled
    required property int percent

    // Clamped defensively: kcfg <min>/<max> would only guard a hand-edited
    // config file, not the value ConfigGeneral.qml's 0..100 slider writes -
    // but a stray out-of-range value must never produce an invalid colour.
    readonly property real alpha: root.enabled ? Math.min(1.0, Math.max(0.0, root.percent / 100)) : 1.0

    // Reads root.alpha live on every call (never a cached local), so a
    // GradientStop bound as `color: transparencySettings.withAlpha(theme.x)`
    // stays a normal reactive QML binding - a ConfigDialog Apply/OK
    // re-evaluates every consumer immediately, no reload. Same idiom as
    // VolumeSettings.clamp(). Only the alpha channel is replaced; RGB stays
    // the caller's Theme.qml colour.
    function withAlpha(c) {
        return Qt.rgba(c.r, c.g, c.b, root.alpha);
    }

    // controlAlpha (Phase 9.1.1 REVISION 4-6, k = 0.1) moved to the palette
    // in Phase 17.19.2: ColorPalette.controlAlphaK, set per palette
    // (DarkPalette 0.1 unchanged, LightPalette 0.1), applied by
    // ColorPalette.controlColor() for both themes. Its derivation comment
    // (why a flat raw alpha k is the compositing-corrected answer, and how
    // k = 0.1 was chosen live) moved with it. The light theme's glass alpha
    // (0.35 + 0.65 x alpha, 17.19.0) is gone: the 17.19.1 spike measured it
    // as the cause of the "grey slabs" on dark wallpapers.

    // Phase 9.1.1 REVISION 3: the AmpListOverlay/SourceListOverlay
    // dropdown card BACKGROUNDS specifically (not controlAlpha's targets
    // above) - a raw, uncorrected formula, decided independently and
    // deliberately NOT reusing controlAlpha's compositing correction.
    // The two chrome problems point in opposite directions: controlAlpha
    // was fixing values that read as unexpectedly darker/more opaque
    // than intended (real, sweep-confirmed overshoot - see its own
    // comment); this property is chasing a perceptual "clearly stands
    // apart from the panel" legibility margin for multi-row list text,
    // not a precise proportional match to a computed effective-opacity
    // number - so no inverse-compositing step here, the raw value below
    // IS the alpha painted.
    //
    // Plain Math.max(alpha, floor) (this property's own Revision 2 form)
    // had a real structural flaw: once panelAlpha reaches the floor, the
    // list card equals the panel EXACTLY (Math.max collapses to alpha
    // itself) - no separation at all above that point, the opposite of
    // "clearly stands apart." Math.max(0.70, Math.min(1.0, alpha + 0.20))
    // fixes this by construction: the +0.20 term keeps pushing the list
    // past the floor as the panel gets more opaque, rather than
    // flatlining into equality with it - the two can only re-converge
    // once alpha itself is within 0.20 of 1.0 (i.e. panel >= 80%), where
    // both are already near-opaque and the separation matters far less.
    readonly property real overlayAlphaFloor: 0.70
    readonly property real overlayAlphaOffset: 0.20
    readonly property real overlayAlpha: Math.max(root.overlayAlphaFloor, Math.min(1.0, root.alpha + root.overlayAlphaOffset))

    function withOverlayAlpha(c) {
        return Qt.rgba(c.r, c.g, c.b, root.overlayAlpha);
    }
}
