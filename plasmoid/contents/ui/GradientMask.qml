// Paint a gradient through the alpha of another item. This is the one
// mechanism the light theme needs for gradient text (readout, headings),
// gradient-"stroked" glyphs (Shapes has no stroke gradient) and
// gradient-filled SVG icons. The gold-effect rules are in docs/DESIGN.md
// §6.
//
// Usage: the caller places an invisible alpha source (Text, Shape, Image)
// as a child of this item, sized like it, and points `maskSource` at it.
// The gradient is painted by a Rectangle (linear) or a Shape (radial) the
// size of this item; a standalone MultiEffect (not layer.effect, so its
// auto padding can draw the shadow outside our bounds) applies the mask and
// optionally a drop shadow / glow.
//
// One MultiEffect cannot do mask + shadow (its shadow padding misaligns
// the mask), so the mask is applied first and a second MultiEffect
// shadows the masked result (`twoStage`).
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item {
    id: root

    required property Item maskSource

    // Gradient: three stops, linear (horizontal, left -> right) or radial.
    property bool radial: false
    property color stop0Color: "#fcecc0"
    property real stop0Pos: 0.0
    property color stop1Color: "#f0a623"
    property real stop1Pos: 0.38
    property color stop2Color: "#a8710b"
    property real stop2Pos: 1.0
    // Radial geometry in this item's coordinates (CSS "circle at 32% 28%",
    // farthest-corner radius by default).
    property real radialCenterX: width * 0.32
    property real radialCenterY: height * 0.28
    property real radialRadius: Math.hypot(Math.max(radialCenterX, width - radialCenterX),
                                           Math.max(radialCenterY, height - radialCenterY))

    // Shadow / glow (CSS drop-shadow(x y blur colour) / text-shadow).
    property bool shadowEnabled: false
    property color shadowColor: "#a06e0a"
    property real shadowOpacity: 0.35
    property real shadowBlur: 0.3
    property int shadowBlurMax: 16
    property real shadowHorizontalOffset: 0
    property real shadowVerticalOffset: 2
    property real shadowScale: 1.0

    // Single stage is only kept for the record: with shadowEnabled its auto
    // padding enlarges the effect and the mask texture is stretched over the
    // padded area, so two stages is the default.
    property bool twoStage: true

    // MultiEffect's defaults (threshold 0, spread 0) cut the mask hard -
    // every pixel with any coverage becomes fully opaque, so text and glyph
    // strokes come out about a device pixel fatter per side and jagged.
    // Threshold 0.5 with spread 1 maps the mask's alpha linearly, which
    // keeps its antialiased edges.
    readonly property real maskThreshold: 0.5
    readonly property real maskSpread: 1.0

    // A MultiEffect with a shadow keeps its padded shadow geometry from the
    // size it was created at. When this item is resized afterwards (the
    // readout's "—" placeholder becoming "-25.0", or the value changing
    // length), the shadow stage paints the old texture stretched over the
    // new size. The mask stage alone resizes correctly. Switching the
    // shadow off and on again after a resize rebuilds it.
    property bool shadowRefreshing: false
    function refreshShadow() { root.shadowRefreshing = false; }
    function sizeChanged() {
        if (!root.shadowEnabled) return;
        root.shadowRefreshing = true;
        Qt.callLater(root.refreshShadow);
    }
    onWidthChanged: root.sizeChanged()
    onHeightChanged: root.sizeChanged()

    // ---- gradient painters (hidden; only sampled by the effects) ----
    Rectangle {
        id: linearPaint
        anchors.fill: parent
        visible: false
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: root.stop0Pos; color: root.stop0Color }
            GradientStop { position: root.stop1Pos; color: root.stop1Color }
            GradientStop { position: root.stop2Pos; color: root.stop2Color }
        }
    }
    Shape {
        id: radialPaint
        anchors.fill: parent
        visible: false
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.radialCenterX
                centerY: root.radialCenterY
                focalX: root.radialCenterX
                focalY: root.radialCenterY
                centerRadius: root.radialRadius
                GradientStop { position: root.stop0Pos; color: root.stop0Color }
                GradientStop { position: root.stop1Pos; color: root.stop1Color }
                GradientStop { position: root.stop2Pos; color: root.stop2Color }
            }
            startX: 0; startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // ---- single stage: mask + shadow in one MultiEffect ----
    MultiEffect {
        id: single
        anchors.fill: parent
        visible: !root.twoStage
        source: root.radial ? radialPaint : linearPaint
        maskEnabled: true
        maskSource: root.maskSource
        maskThresholdMin: root.maskThreshold
        maskSpreadAtMin: root.maskSpread
        shadowEnabled: root.shadowEnabled
        shadowColor: root.shadowColor
        shadowOpacity: root.shadowOpacity
        shadowBlur: root.shadowBlur
        blurMax: root.shadowBlurMax
        shadowHorizontalOffset: root.shadowHorizontalOffset
        shadowVerticalOffset: root.shadowVerticalOffset
        shadowScale: root.shadowScale
        autoPaddingEnabled: true
    }

    // ---- two stages: mask, then shadow the masked result ----
    MultiEffect {
        id: masked
        anchors.fill: parent
        visible: false
        source: root.radial ? radialPaint : linearPaint
        maskEnabled: true
        maskSource: root.maskSource
        maskThresholdMin: root.maskThreshold
        maskSpreadAtMin: root.maskSpread
        layer.enabled: root.twoStage
    }
    MultiEffect {
        id: shadowed
        anchors.fill: parent
        visible: root.twoStage
        source: masked
        shadowEnabled: root.shadowEnabled && !root.shadowRefreshing
        shadowColor: root.shadowColor
        shadowOpacity: root.shadowOpacity
        shadowBlur: root.shadowBlur
        blurMax: root.shadowBlurMax
        shadowHorizontalOffset: root.shadowHorizontalOffset
        shadowVerticalOffset: root.shadowVerticalOffset
        shadowScale: root.shadowScale
        autoPaddingEnabled: true
    }
}
