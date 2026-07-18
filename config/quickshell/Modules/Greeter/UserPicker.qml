//  PASO 1 · Selector de usuario (teclado ↑/↓/Tab/Enter + ratón).
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Modules.Greeter

FocusScope {
    id: sel
    implicitHeight: selCol.implicitHeight

    property int hi: 0
    Component.onCompleted: hi = GreeterState.preferredIndex

    Keys.onUpPressed:     hi = Math.max(0, hi - 1)
    Keys.onDownPressed:   hi = Math.min(GreeterState.users.length - 1, hi + 1)
    // Tab cicla con vuelta (a diferencia de ↑/↓, que paran en los extremos).
    Keys.onTabPressed:     if (GreeterState.users.length) hi = (hi + 1) % GreeterState.users.length
    Keys.onBacktabPressed: if (GreeterState.users.length) hi = (hi - 1 + GreeterState.users.length) % GreeterState.users.length
    Keys.onEscapePressed:  hi = GreeterState.preferredIndex
    Keys.onReturnPressed: if (GreeterState.users.length) GreeterState.pickUser(GreeterState.users[hi].name)
    Keys.onEnterPressed:  if (GreeterState.users.length) GreeterState.pickUser(GreeterState.users[hi].name)

    Column {
        id: selCol
        width: parent.width
        spacing: Theme.dp(12)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Selecciona usuario", "Select user")
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.sp(14)
            bottomPadding: Theme.dp(2)
        }

        Repeater {
            model: GreeterState.users
            delegate: Rectangle {
                id: urow
                required property int index
                required property var modelData
                width: selCol.width
                height: Theme.dp(58)
                radius: Theme.dp(13)
                readonly property bool active: index === sel.hi || urowMa.containsMouse
                color: active ? Theme.alpha(Theme.surfaceHi, 0.85)
                              : Theme.alpha(Theme.surface, 0.35)
                border.width: active ? 1 : 0
                border.color: Theme.alpha(Theme.accent, 0.45)
                // Resalte instantáneo: el fundido de 130 ms dejaba dos filas
                // marcadas a la vez al mover el ratón rápido.

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.dp(12)
                    anchors.rightMargin: Theme.dp(12)
                    spacing: Theme.dp(12)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.dp(38); height: Theme.dp(38); radius: width / 2
                        color: Theme.alpha(Theme.accent, urow.active ? 0.22 : 0.14)
                        border.width: 1
                        border.color: Theme.alpha(Theme.accent, 0.5)
                        // Inicial de fondo; si este usuario tiene avatar propio
                        // en AccountsService, se pinta encima recortado.
                        Text {
                            anchors.centerIn: parent
                            visible: rowAvatar.status !== Image.Ready
                            text: (urow.modelData.full || urow.modelData.name).charAt(0).toUpperCase()
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.sp(16)
                            font.bold: true
                        }
                        ClippingRectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            visible: rowAvatar.status === Image.Ready
                            Image {
                                id: rowAvatar
                                anchors.fill: parent
                                source: {
                                    const p = Config.avatarFor(urow.modelData.name)
                                    return p !== "" ? "file://" + p : ""
                                }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: Math.round(parent.width * 2)
                                sourceSize.height: Math.round(parent.height * 2)
                            }
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            text: urow.modelData.full
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.sp(15)
                            font.bold: true
                        }
                        Text {
                            visible: urow.modelData.full !== urow.modelData.name
                            text: urow.modelData.name
                            color: Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.sp(12)
                        }
                    }
                }
                // Insignia "último" en el usuario que entró la vez anterior.
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.dp(14)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: GreeterState.lastUser !== "" && urow.modelData.name === GreeterState.lastUser
                    text: "󰋚"
                    color: Theme.alpha(Theme.accent, 0.8)
                    font.family: Theme.font
                    font.pixelSize: Theme.sp(13)
                }
                MouseArea {
                    id: urowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: sel.hi = urow.index
                    onClicked: GreeterState.pickUser(urow.modelData.name)
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: GreeterState.users.length === 0
            text: I18n.tr("No se han encontrado usuarios", "No users found")
            color: Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: Theme.sp(13)
        }
    }
}
