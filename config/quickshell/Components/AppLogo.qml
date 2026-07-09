import QtQuick
import qs.Config

// La marca "<A/>". Vive aquí y no dentro de la pantalla de arranque para que
// esa y la pestaña About dibujen exactamente lo mismo y no se me vayan
// separando con el tiempo. Es cuadrada y todo sale de 'box', así que escala
// sola; las proporciones salieron de medirla a 148 px.
Item {
    id: root

    property real box: Theme.dp(148)      // lo que mide de lado
    property bool animate: true           // los puntos de color laten

    width: box
    height: box

    // La placa de fuera.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.box * 0.054
        radius: root.box * 0.122
        color: Theme.withAlpha(Theme.surface, 0.28)
        border.width: Math.max(2, Theme.dp(2))
        border.color: Theme.withAlpha(Theme.accent, 0.78)
    }
    // Y el marquito de dentro.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.box * 0.149
        radius: root.box * 0.068
        color: "transparent"
        border.width: Math.max(1, Theme.dp(1))
        border.color: Theme.withAlpha(Theme.overlay, 0.44)
    }

    // <  A  />
    Text {
        anchors { left: parent.left; leftMargin: root.box * 0.135; verticalCenter: parent.verticalCenter }
        text: "<"
        color: Theme.accent
        font.family: Theme.monoFontFamily; font.pixelSize: Math.round(root.box * 0.338); font.bold: true
    }
    Text {
        anchors.centerIn: parent
        text: "A"
        color: Theme.fg
        font.family: Theme.monoFontFamily; font.pixelSize: Math.round(root.box * 0.432); font.bold: true
    }
    Text {
        anchors { right: parent.right; rightMargin: root.box * 0.108; verticalCenter: parent.verticalCenter }
        text: "/>"
        color: Theme.cyan
        font.family: Theme.monoFontFamily; font.pixelSize: Math.round(root.box * 0.257); font.bold: true
    }

    // Rayitas de adorno.
    Rectangle {
        x: root.width * 0.18; y: root.height * 0.28
        width: root.width * 0.2; height: Math.max(1, Theme.dp(2)); radius: height / 2
        color: Theme.withAlpha(Theme.accent, 0.64)
    }
    Rectangle {
        x: root.width * 0.62; y: root.height * 0.72
        width: root.width * 0.2; height: Math.max(1, Theme.dp(2)); radius: height / 2
        color: Theme.withAlpha(Theme.cyan, 0.64)
    }
    Rectangle {
        x: root.width * 0.5 - width / 2; y: root.height * 0.12
        width: Math.max(1, Theme.dp(2)); height: root.height * 0.18; radius: width / 2
        color: Theme.withAlpha(Theme.yellow, 0.54)
    }

    // Los tres puntos, latiendo uno detrás de otro.
    Repeater {
        model: [
            { x: 0.16, y: 0.28, c: Theme.accent, d: 0 },
            { x: 0.50, y: 0.12, c: Theme.yellow, d: 220 },
            { x: 0.84, y: 0.72, c: Theme.cyan,   d: 440 }
        ]
        delegate: Rectangle {
            required property var modelData
            width: root.box * 0.068; height: width; radius: width / 2
            x: root.width * modelData.x - width / 2
            y: root.height * modelData.y - height / 2
            color: modelData.c
            opacity: 0.82
            SequentialAnimation on opacity {
                running: root.animate
                loops: Animation.Infinite
                PauseAnimation { duration: modelData.d }
                NumberAnimation { from: 0.38; to: 1; duration: 420; easing.type: Easing.OutCubic }
                NumberAnimation { from: 1; to: 0.38; duration: 620; easing.type: Easing.InOutCubic }
            }
        }
    }
}
