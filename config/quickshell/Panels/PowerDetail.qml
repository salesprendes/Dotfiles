import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Selector de perfil de energía: cabecera con estado y lista de perfiles, el
// activo resaltado. Click fija el perfil (lo escribe a power-profiles-daemon
// vía Power).
ColumnLayout {
    id: root
    width: parent ? parent.width : implicitWidth
    spacing: Theme.space10

    // Caja única: DetailCard compartida; el perfil actual va como extra de
    // cabecera.
    DetailCard {
        icon: Power.icon
        iconColor: Power.color
        title: I18n.tr("Power profile")
        header: Text {
            text: Power.name
            color: Power.color
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }

        // Filas de perfiles; el perfil activo queda resaltado.
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

    // Fila de perfil: DeviceRow compartido + etiqueta "activo" y check como
    // contenido extra a la derecha.
    component ProfileRow: DeviceRow {
        id: pr
        property var info

        Layout.fillWidth: true
        active: Power.matches(info?.value ?? -1)
        accent: info?.color ?? Theme.accent
        icon: info?.icon ?? ""
        title: info?.label ?? ""
        onClicked: Power.set(info.value)

        Text {
            visible: pr.active
            text: I18n.tr("Active")
            color: pr.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
            font.bold: true
        }
        Text {
            visible: pr.active
            text: "󰓏"
            color: pr.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }
    }
}
