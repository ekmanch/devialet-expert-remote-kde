// The one owner of the transparency setting (main.xml transparencyEnabled
// + transparencyPercent), resolved into the alphas the flyout's panel tint
// (FlyoutContent.qml, `alpha`) and the overlay list cards
// (OverlayCardBackground.qml, `overlayAlpha`) paint with. The palettes
// supply opaque base colours; this object supplies only the alpha.
//
// Root-anchored like VolumeSettings.qml (docs/DESIGN.md §3): created once
// in main.qml with its inputs bound to Plasmoid.configuration there, and
// passed down as `required property`.
//
// percent is opacity, not transparency: alpha = percent / 100, 100 is
// fully opaque, and `enabled == false` is exactly 1.0.
import QtQuick

QtObject {
    id: root

    required property bool enabled
    required property int percent

    // Clamped defensively: kcfg <min>/<max> only guards a hand-edited
    // config, and an out-of-range value must never produce an invalid
    // colour.
    readonly property real alpha: root.enabled ? Math.min(1.0, Math.max(0.0, root.percent / 100)) : 1.0

    // Reads root.alpha live on every call (never a cached local), so a
    // binding like `color: transparencySettings.withAlpha(colors.x)` stays
    // reactive and a settings Apply/OK re-evaluates it with no reload.
    // Only the alpha channel is replaced; RGB stays the caller's.
    function withAlpha(c) {
        return Qt.rgba(c.r, c.g, c.b, root.alpha);
    }

    // The alpha for control chrome is not here: it is the palette's
    // fixed ColorPalette.controlAlphaK, applied by controlColor().

    // Overlay list card backgrounds. A raw alpha (no compositing
    // correction): the aim is a legibility margin that keeps the card
    // clearly apart from the panel, not a proportional match.
    // A plain Math.max(alpha, floor) would make the card equal the panel
    // once alpha passes the floor; the +0.20 offset keeps them apart until
    // the panel is >= 80 % opaque, where both are near-opaque anyway.
    readonly property real overlayAlphaFloor: 0.70
    readonly property real overlayAlphaOffset: 0.20
    readonly property real overlayAlpha: Math.max(root.overlayAlphaFloor, Math.min(1.0, root.alpha + root.overlayAlphaOffset))

    function withOverlayAlpha(c) {
        return Qt.rgba(c.r, c.g, c.b, root.overlayAlpha);
    }
}
