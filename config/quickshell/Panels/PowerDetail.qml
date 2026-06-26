import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services

// Selector de perfil de energía unificado en una "caja" (como audio / WiFi):
// cabecera con estado y lista de perfiles con el activo RESALTADO estilo DMS.
// Click fija el perfil (escribe a power-profiles-daemon vía el servicio Power).
ColumnLayout {
    id: root
    width: parent ? parent.width : implicitWidth
    spacing: Theme.space10

    // ── Caja única ───────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Theme.space16 * 2
        radius: Theme.barRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.62)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.space14
            spacing: Theme.space10

            // Cabecera: icono + título + perfil actual.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    text: Power.icon
                    color: Power.color
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Power profile")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    text: Power.name
                    color: Power.color
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: true
                }
            }

            // Filas de perfiles, activo resaltado estilo DMS.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                Repeater {
                    model: Power.profiles
                    delegate: ProfileRow {
                        required property var modelData
                        info: modelData
                    }
                }
            }
        }
    }

    // Fila de perfil (mismo estilo que DeviceRow del audio / NetRow del WiFi).
    component ProfileRow: Rectangle {
        id: pr
        property var info
        readonly property bool active: Power.profile === (info?.value ?? -1)

        Layout.fillWidth: true
        implicitHeight: Theme.rowL
        radius: Theme.pillRadius
        color: active ? Qt.rgba(info.color.r, info.color.g, info.color.b, 0.16)
                      : prMa.containsMouse ? Theme.surfaceHi : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.36)
        border.width: active ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: active ? info.color : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            Text {
                text: pr.info?.icon ?? ""
                color: pr.active ? pr.info.color : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                text: pr.info?.label ?? ""
                color: pr.active ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: pr.active
                elide: Text.ElideRight
            }
            // "activo" + check cuando es el perfil en uso.
            Text {
                visible: pr.active
                text: I18n.tr("Active")
                color: pr.info.color
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
                font.bold: true
            }
            Text {
                visible: pr.active
                text: "󰓏"
                color: pr.info.color
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
        }

        MouseArea {
            id: prMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Power.set(pr.info.value)
        }
    }
}
