import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Config

// Página "Shell": preferencias del propio shell — reloj/fecha y el avatar del
// usuario. Cada bloque en su propia tarjeta.
ColumnLayout {
    id: shellPage
    spacing: Theme.space14

    readonly property string userName: Quickshell.env("USER") || "usuario"
    readonly property string userInitial: userName.charAt(0).toUpperCase()

    // Estado de la sincronización del avatar con el greeter.
    property string greeterStatus: ""
    // uid del usuario, para la ruta del objeto AccountsService por D-Bus.
    property string uid: ""
    readonly property string userObjPath: "/org/freedesktop/Accounts/User" + uid
    Process {
        running: true
        command: ["id", "-u"]
        stdout: StdioCollector { onStreamFinished: shellPage.uid = (this.text || "").trim() }
    }

    // Selector de imagen (zenity): imprime la ruta elegida por stdout; cancelar
    // sale con código ≠0 y stdout vacío. Al elegir, se aplica solo al greeter.
    Process {
        id: avatarPicker
        command: ["zenity", "--file-selection",
                  "--title=" + I18n.tr("Choose avatar image"),
                  "--file-filter=" + I18n.tr("Images") + " | *.png *.jpg *.jpeg *.webp *.bmp *.gif"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = (this.text || "").trim()
                if (p !== "") {
                    Settings.avatarPath = p
                    shellPage.greeterStatus = ""
                    greeterApply.running = true
                }
            }
        }
    }

    // Publica el avatar vía AccountsService (D-Bus): el demonio, que corre
    // como root, copia la imagen a /var/lib/AccountsService/icons/<usuario>.
    // polkit autoriza la llamada sin contraseña al usuario de la sesión
    // activa. Requiere el paquete 'accountsservice'; si falta, el avatar
    // queda guardado en el escritorio pero sin sincronizar con el login.
    Process {
        id: greeterApply
        command: ["gdbus", "call", "--system",
                  "--dest", "org.freedesktop.Accounts",
                  "--object-path", shellPage.userObjPath,
                  "--method", "org.freedesktop.Accounts.User.SetIconFile",
                  Settings.avatarPath]
        onExited: (code) => {
            shellPage.greeterStatus = code === 0
                ? I18n.tr("Avatar applied to the login screen")
                : I18n.tr("To sync it to the login screen, install 'accountsservice'")
        }
    }

    // Un icono vacío hace que AccountsService borre el fichero del avatar.
    Process {
        id: greeterRemove
        command: ["gdbus", "call", "--system",
                  "--dest", "org.freedesktop.Accounts",
                  "--object-path", shellPage.userObjPath,
                  "--method", "org.freedesktop.Accounts.User.SetIconFile", ""]
        onExited: (code) => {
            shellPage.greeterStatus = code === 0
                ? I18n.tr("Avatar removed from the login screen")
                : I18n.tr("To sync it to the login screen, install 'accountsservice'")
        }
    }

    // ── Disposición de la barra ──────────────────────────────────────────────
    SettingsCard {
        title: I18n.tr("Bar layout")
        glyph: "󰉺"

        SegRow {
            skey: "barPosition"
            label: I18n.tr("Position on screen")
            options: [ { text: I18n.tr("Top"), value: "top" },
                       { text: I18n.tr("Bottom"), value: "bottom" } ]
            current: Settings.barPosition
            onPicked: (v) => Settings.barPosition = v
        }
        SwitchRow {
            skey: "barFloating"
            label: I18n.tr("Floating bar")
            desc: I18n.tr("Detached with margin and rounded corners; disabled sticks it edge to edge")
            checked: Settings.barFloating
            onToggled: Settings.barFloating = !Settings.barFloating
        }
    }

    // ── Reloj y fecha ────────────────────────────────────────────────────────
    SettingsCard {
        title: I18n.tr("Clock and date")
        glyph: "󰥔"

        SwitchRow { skey: "clock24h"; label: I18n.tr("24-hour format"); desc: I18n.tr("Disabled uses AM/PM")
            checked: Settings.clock24h; onToggled: Settings.clock24h = !Settings.clock24h }
        SwitchRow { skey: "clockShowSeconds"; label: I18n.tr("Show seconds"); checked: Settings.clockShowSeconds
            onToggled: Settings.clockShowSeconds = !Settings.clockShowSeconds }
        SwitchRow { skey: "clockShowDate"; label: I18n.tr("Show date in the bar"); checked: Settings.clockShowDate
            onToggled: Settings.clockShowDate = !Settings.clockShowDate }
    }

    // ── Avatar del usuario ─────────────────────────────────────────────────────
    SettingsCard {
        title: I18n.tr("Avatar")
        glyph: "󰀄"

        // Mismo patrón que el resto de filas: contenido a la izquierda (avatar +
        // nombre + pista) y los controles a la derecha, en vez de un bloque
        // suelto. Así encaja con el lenguaje del resto de la página.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space12

            Avatar {
                Layout.alignment: Qt.AlignVCenter
                diameter: Theme.dp(48)
                source: Settings.avatarPath
                initial: shellPage.userInitial
                initialPixelSize: Theme.sp(20)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.dp(1)
                Text {
                    Layout.fillWidth: true
                    text: shellPage.userName
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: shellPage.greeterStatus !== ""
                        ? shellPage.greeterStatus
                        : I18n.tr("Round image, applied to the login screen")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
            }

            TextButton {
                Layout.alignment: Qt.AlignVCenter
                text: I18n.tr("Choose image…")
                primary: true
                onClicked: avatarPicker.running = true
            }
            TextButton {
                Layout.alignment: Qt.AlignVCenter
                text: I18n.tr("Remove")
                enabled: Settings.avatarPath !== ""
                onClicked: {
                    Settings.avatarPath = ""
                    shellPage.greeterStatus = ""
                    greeterRemove.running = true    // quitar también del login
                }
            }
        }
    }
}
