// Phase 17.21.0 - a source glyph painted for the active theme: SourceGlyph
// in flat copper (dark), or the same glyph as the alpha mask of the
// glyphGold radial gradient with a warm drop shadow (light; flyout mockup
// v22 :135-137 and the `#glyphGold` gradient at :485 - centre 6.4/5.6 and
// radius 15.5 on the glyph's 20-unit grid).
//
// The light branch lives in a Loader so its layers exist from creation
// (see GradientText.qml / CardShadow.qml on why not a runtime
// `layer.enabled` toggle).

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: themed

    required property ColorPalette colors
    property string sourceName: ""
    property real size: 20

    implicitWidth: themed.size
    implicitHeight: themed.size

    SourceGlyph {
        anchors.fill: parent
        visible: !themed.colors.isLight
        sourceName: themed.sourceName
        size: themed.size
        color: themed.colors.copperBright
    }

    Loader {
        anchors.fill: parent
        active: themed.colors.isLight
        sourceComponent: GradientMask {
            maskSource: maskGlyph
            radial: true
            radialCenterX: themed.size * 0.32
            radialCenterY: themed.size * 0.28
            radialRadius: themed.size * 0.775
            // drop-shadow(0 2px 2.5px rgba(160,110,10,0.35))
            shadowEnabled: true
            shadowVerticalOffset: 2
            shadowBlur: 0.3
            shadowBlurMax: 16
            shadowOpacity: 0.35

            SourceGlyph {
                id: maskGlyph
                anchors.fill: parent
                visible: false
                layer.enabled: true
                sourceName: themed.sourceName
                size: themed.size
                color: "black"
            }
        }
    }
}
