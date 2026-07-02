import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Config
import qs.Services

// 'notif' = objeto Notification.
Rectangle {
    id: item
    property var notif
    property bool popupMode: false
    readonly property bool closeHovered: closeButton.hovered

    readonly property string img: resolveImage()
    readonly property bool hasImagePayload: notif && notif.image
    readonly property string appName: notif && notif.appName ? notif.appName : "Sistema"
    readonly property string summary: notif && notif.summary ? notif.summary : ""
    readonly property string body: notif && notif.body ? notif.body : ""
    readonly property bool hasBody: body !== ""
    readonly property int actionCount: countActions()
    readonly property bool hasActions: actionCount > 0

    signal closeRequested()

    function countActions() {
        if (!notif || !notif.actions)
            return 0
        return notif.actions.length || 0
    }

    function actionAt(i) {
        if (!notif || !notif.actions || i < 0 || i >= actionCount)
            return null
        return notif.actions[i]
    }

    function resolveImage() {
        const im = notif && notif.image ? notif.image : ""
        if (im !== "") return im
        const ic = notif && notif.appIcon ? notif.appIcon : ""
        return ic !== "" ? Quickshell.iconPath(ic, true) : ""
    }

    function dismiss() {
        if (popupMode) {
            closeRequested()
        } else if (notif) {
            notif.dismiss()
        }
    }

    implicitHeight: content.implicitHeight + Theme.space12 * 2
    radius: Theme.pillRadius + Theme.space4
    color: item.closeHovered
        ? Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.92)
        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.88)
    border.width: Theme.hairline
    border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.42)
    clip: true

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.space12
            leftMargin: Theme.space14
        }
        spacing: Theme.space10

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space12

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Theme.dp(46)
                implicitHeight: Theme.dp(46)
                radius: height / 2
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                border.width: Math.max(1, Theme.dp(2))
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, item.popupMode ? 0.75 : 0.48)
                clip: true

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Theme.space4
                    radius: width / 2
                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                    visible: item.img !== ""
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: item.img !== "" ? Theme.dp(5) : Theme.space10
                    visible: item.img !== ""
                    source: item.img
                    fillMode: item.hasImagePayload ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: item.img === ""
                    text: "󰂚"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 3
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8

                    Text {
                        Layout.fillWidth: true
                        text: item.appName
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        text: NotifService.timeText(item.notif)
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: item.summary
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: item.hasBody
                    text: item.body
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    wrapMode: Text.WordWrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            Rectangle {
                id: closeButton
                property bool hovered: closeMa.containsMouse
                Layout.alignment: Qt.AlignTop
                implicitWidth: Theme.controlS
                implicitHeight: Theme.controlS
                radius: height / 2
                // Apagado = rojo con alfa 0 (no "transparent", que es negro
                // con alfa 0 y ensuciaba el fundido de salida).
                color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, closeButton.hovered ? 0.18 : 0)
                Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: closeButton.hovered ? Theme.red : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize - 1
                    // Funde junto al fondo; antes cambiaba de golpe.
                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: item.dismiss()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.dp(53)
            spacing: Theme.space8
            visible: item.hasActions

            Repeater {
                model: item.actionCount
                delegate: Rectangle {
                    readonly property var action: item.actionAt(index)
                    implicitWidth: Math.min(150, aTxt.implicitWidth + 22)
                    implicitHeight: Theme.controlS
                    radius: height / 2
                    color: aMa.containsMouse
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                        : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.8)
                    border.width: Theme.hairline
                    border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.38)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        id: aTxt
                        anchors.centerIn: parent
                        width: Math.min(128, implicitWidth)
                        text: parent.action && parent.action.text ? parent.action.text : ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: true
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                    MouseArea {
                        id: aMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (parent.action) {
                                parent.action.invoke()
                            }
                        }
                    }
                }
            }
        }
    }
}
