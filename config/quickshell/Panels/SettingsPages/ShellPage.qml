import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Config
import qs.Services

// Página "Shell": preferencias del propio shell — reloj/fecha y el avatar del
// usuario. Cada bloque en su propia tarjeta.
SettingsPage {
    id: shellPage

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

    // Selector de imágenes propio (ver Components/ImagePickerSheet.qml). Antes
    // lanzaba 'zenity', que en este equipo NO está instalado (ni yad, ni
    // kdialog): el botón no abría nada. Y el diálogo de Qt, que sí funcionaba,
    // era una lista de nombres con tamaños y fechas — para elegir una foto hay
    // que verla, no leer cómo se llama.
    ImagePickerSheet {
        id: avatarPicker
        circularCrop: true      // el avatar se recorta en círculo
        onPicked: (p) => {
            Settings.avatarPath = p
            shellPage.greeterStatus = ""
            greeterApply.running = true
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

    // Disposición de la barra
    SettingsCard {
        title: I18n.tr("Bar layout")
        glyph: "󰉺"

        SegRow {
            glyph: "󰉺"
            skey: "barPosition"
            label: I18n.tr("Position on screen")
            options: [ { text: I18n.tr("Top"), value: "top" },
                       { text: I18n.tr("Bottom"), value: "bottom" } ]
            current: Settings.barPosition
            onPicked: (v) => Settings.barPosition = v
        }
        SwitchRow {
            glyph: "󰕰"
            skey: "barFloating"
            label: I18n.tr("Floating bar")
            desc: I18n.tr("Detached with margin and rounded corners; disabled sticks it edge to edge")
            checked: Settings.barFloating
            onToggled: Settings.barFloating = !Settings.barFloating
        }
    }

    // Teclado
    SettingsCard {
        title: I18n.tr("Keyboard")
        glyph: "󰌌"

        SwitchRow {
            glyph: "󰎠"
            skey: "numlockOn"
            label: I18n.tr("Num Lock on")
            desc: I18n.tr("Turns it on now and on every shell start")
            checked: Settings.numlockOn
            onToggled: Settings.numlockOn = !Settings.numlockOn
        }
    }

    // Bloqueo de pantalla
    SettingsCard {
        title: I18n.tr("Screen lock")
        glyph: "󰌾"

        // El selector solo aparece si HAY algo que elegir. Sin hyprlock
        // instalado sería un segmentado de una sola opción, que es un control
        // que no controla nada.
        SegRow {
            glyph: "󰍁"
            skey: "lockBackend"; aliases: ["hyprlock", "bloqueo", "lock", "pantalla de bloqueo"]
            label: I18n.tr("Lock screen")
            shown: Lock.hyprlockAvailable
            options: [ { text: I18n.tr("This shell"), value: "shell" },
                       { text: "hyprlock", value: "hyprlock" } ]
            current: Settings.lockBackend
            onPicked: (v) => Settings.lockBackend = v
        }
        Hint {
            skey: "lockBackend"
            text: I18n.tr("The shell's own lock screen uses your theme, palette and language, and authenticates with PAM.")
        }
        Hint {
            skey: "lockBackend"
            shown: !Lock.hyprlockAvailable
            text: I18n.tr("hyprlock is not installed, so this shell locks the screen.")
        }
        // Aviso, no adorno: si el archivo de PAM no está, el bloqueo propio no
        // puede autenticar. Lo que pasa entonces depende de si hay hyprlock, y
        // decir lo que no es sería peor que callarse: sin él no hay pantalla
        // ninguna, solo una sesión que logind marca como bloqueada.
        Hint {
            skey: "lockBackend"
            shown: Settings.lockBackend === "shell" && !Lock.pamReady
            color: Theme.red
            text: Lock.hyprlockAvailable
                  ? I18n.tr("No PAM service found (%1): hyprlock will be used instead.")
                      .arg(Lock.pamService)
                  : I18n.tr("No PAM service found (%1) and hyprlock is not installed: the session would be locked with no screen to unlock it.")
                      .arg(Lock.pamService)
        }

        SwitchRow { glyph: "󰅶"; skey: "keepAwakeOnMedia"; aliases: ["cafeina", "caffeine", "insomnio", "no dormir", "idle"]
            label: I18n.tr("Keep the screen on while playing")
            checked: Settings.keepAwakeOnMedia
            onToggled: Settings.keepAwakeOnMedia = !Settings.keepAwakeOnMedia }
        Hint {
            skey: "keepAwakeOnMedia"
            text: I18n.tr("While something is playing, the screen will not blank or lock on its own. Counts the same player the bar shows, so a browser tab that is merely open does not keep the screen awake.")
        }
    }

    // Solo tiene sentido con el bloqueo propio: lo que enseñe hyprlock lo
    // decide su archivo de configuración, no este panel.
    SettingsCard {
        title: I18n.tr("On the lock screen")
        glyph: "󰍁"
        shown: Settings.lockBackend === "shell"
        description: I18n.tr("A lock screen is what anyone walking past your desk gets to read.")

        SwitchRow { glyph: "󰝚"; skey: "lockShowMedia"; label: I18n.tr("Media player")
            desc: I18n.tr("With controls, so you can skip a track without unlocking")
            checked: Settings.lockShowMedia
            onToggled: Settings.lockShowMedia = !Settings.lockShowMedia }
        SwitchRow { glyph: "󰖐"; skey: "lockShowWeather"; label: I18n.tr("Weather")
            checked: Settings.lockShowWeather
            onToggled: Settings.lockShowWeather = !Settings.lockShowWeather }
        SwitchRow { glyph: "󰖩"; skey: "lockShowStatus"; label: I18n.tr("Network and battery")
            checked: Settings.lockShowStatus
            onToggled: Settings.lockShowStatus = !Settings.lockShowStatus }
        SwitchRow { glyph: "󰐥"; skey: "lockShowSessionButtons"; label: I18n.tr("Session buttons")
            desc: I18n.tr("Suspend, restart and shut down; each asks for a second click")
            checked: Settings.lockShowSessionButtons
            onToggled: Settings.lockShowSessionButtons = !Settings.lockShowSessionButtons }

        SliderRow {
            skey: "lockBlur"
            label: I18n.tr("Background blur"); glyph: "󰂵"
            from: 0.0; to: 1.0; value: Settings.lockBlur
            valueText: Settings.lockBlur < 0.005 ? I18n.tr("Off")
                                                 : Math.round(Settings.lockBlur * 100) + "%"
            onMoved: (v) => Settings.lockBlur = Math.round(v * 20) / 20
        }
        SliderRow {
            skey: "lockDim"
            label: I18n.tr("Background dim"); glyph: "󰃞"
            from: 0.0; to: 0.9; value: Settings.lockDim
            valueText: Math.round(Settings.lockDim * 100) + "%"
            onMoved: (v) => Settings.lockDim = Math.round(v * 20) / 20
        }
    }

    // Reloj y fecha
    SettingsCard {
        title: I18n.tr("Clock and date")
        glyph: "󰥔"

        SwitchRow { glyph: "󰥔"; skey: "clock24h"; label: I18n.tr("24-hour format"); desc: I18n.tr("Disabled uses AM/PM")
            checked: Settings.clock24h; onToggled: Settings.clock24h = !Settings.clock24h }
        SwitchRow { glyph: "󰔛"; skey: "clockShowSeconds"; label: I18n.tr("Show seconds"); checked: Settings.clockShowSeconds
            onToggled: Settings.clockShowSeconds = !Settings.clockShowSeconds }
        SwitchRow { glyph: "󰃭"; skey: "clockShowDate"; label: I18n.tr("Show date in the bar"); checked: Settings.clockShowDate
            onToggled: Settings.clockShowDate = !Settings.clockShowDate }
    }

    // Avatar del usuario
    SettingsCard {
        title: I18n.tr("Avatar")
        glyph: "󰀄"

        // Mismo patrón que el resto de filas: contenido a la izquierda (avatar +
        // nombre + pista) y los controles a la derecha, en vez de un bloque
        // suelto. Así encaja con el lenguaje del resto de la página.
        //
        // GridLayout, no RowLayout: en una columna estrecha los dos botones no
        // caben al lado del nombre y un RowLayout los sacaba por el borde de
        // la tarjeta. Aquí, cuando la fila ya no da para todo (medido contra
        // SU ancho, no contra la ventana — misma idea que SegRow.stacked),
        // pasa a una columna y los botones bajan a su propio renglón,
        // alineados a la derecha.
        GridLayout {
            id: avatarRow
            Layout.fillWidth: true
            columnSpacing: Theme.space12
            rowSpacing: Theme.space8
            readonly property bool stacked: width > 0 && width < Theme.dp(460)
            columns: stacked ? 1 : 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space12

                Avatar {
                    Layout.alignment: Qt.AlignVCenter
                    diameter: Theme.dp(48)
                    source: Settings.avatarPath
                    initial: shellPage.userInitial
                    initialPixelSize: Theme.sp(20)
                    tint: Theme.accent
                    fontFamily: Theme.fontFamily
                    isDark: Theme.isDark
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dp(1)
                    ThemedText {
                        Layout.fillWidth: true
                        text: shellPage.userName
                        color: Theme.fg
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: shellPage.greeterStatus !== ""
                            ? shellPage.greeterStatus
                            : I18n.tr("Round image, applied to the login screen")
                        color: Theme.fgMuted
                        font.pixelSize: Theme.fontSize - 2
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: Theme.space8

                TextButton {
                    text: I18n.tr("Choose image…")
                    primary: true
                    onClicked: avatarPicker.present(Settings.avatarPath)
                }
                TextButton {
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
}
