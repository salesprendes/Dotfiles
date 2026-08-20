import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Polkit
import qs.Components
import qs.Config

// Agente de polkit propio: el diálogo de "se requiere autenticación" que sale
// al hacer algo privilegiado (montar un disco, cambiar la red, reiniciar…).
//
// Antes lo pintaba hyprpolkitagent, un binario aparte cuyo QML va compilado
// dentro: no se puede rediseñar, y como no hay ningún tema de Qt configurado
// en este equipo, salía con la paleta gris por defecto de Qt — ajeno al resto
// del shell. Al implementar el agente aquí, el diálogo usa la misma ventana
// modal, los mismos campos y la misma paleta que todo lo demás.
//
// IMPORTANTE: polkit admite UN agente por sesión. Para que este se registre,
// hyprpolkitagent tiene que estar parado:
//     systemctl --user disable --now hyprpolkitagent.service
// Si el otro sigue vivo, 'agent.isRegistered' se queda en false y aquí no se
// muestra nada — no hay conflicto ni pantallas dobles, simplemente sigue
// saliendo el de siempre.
Scope {
    id: root

    PolkitAgent {
        id: agent
    }

    // La ventana solo existe mientras hay una petición viva.
    LazyLoader {
        active: agent.isActive && agent.flow !== null

        ModalWindow {
            id: dialog

            // No hace falta limpiarlas entre peticiones: el LazyLoader crea un
            // diálogo nuevo por cada una y lo destruye al terminar, así que
            // nacen vacías solas.
            property string password: ""
            // Tras el primer intento fallido, el campo se marca en rojo. Sin
            // esto el campo nacería "inválido" antes de haber escrito nada.
            property bool attempted: false

            readonly property var flow: agent.flow

            modelData: Globals.focusedScreen()
            visible: agent.isActive
            ns: "qs-polkit"
            cardWidth: 400
            cardMinWidth: 320
            cardMaxRatio: 0.9
            icon: "󰦝"
            heading: I18n.tr("Authentication required")
            // El mensaje de polkit dice QUÉ se va a autorizar ("Se requiere
            // autenticación para reiniciar el sistema"). Es la única pista que
            // tiene el usuario de por qué le piden la contraseña, así que va
            // arriba y completo, no recortado a una línea.
            subheading: ""

            ThemedText {
                Layout.fillWidth: true
                visible: text !== ""
                text: dialog.flow?.message ?? ""
                color: Theme.fgDim
                wrapMode: Text.WordWrap
            }

            // Campo de respuesta. 'responseVisible' lo decide polkit: casi
            // siempre es una contraseña (oculta), pero algunos módulos PAM
            // piden datos que sí deben verse.
            TextField {
                id: pwField
                Layout.fillWidth: true
                visible: dialog.flow?.isResponseRequired ?? false
                password: !(dialog.flow?.responseVisible ?? false)
                leftIcon: "󰌾"
                // El prompt viene de PAM y ya dice de quién es la contraseña
                // ("Password:", "Contraseña para root:"), así que se usa tal
                // cual en vez de inventar una etiqueta que podría mentir sobre
                // qué usuario está autenticando.
                // El flujo se anula al completarse la petición y este binding
                // se reevalúa ANTES de que el LazyLoader destruya la ventana:
                // hay que leerlo con red, no solo comprobarlo con red.
                placeholder: {
                    const p = dialog.flow ? dialog.flow.inputPrompt : ""
                    return p !== "" ? p : I18n.tr("Password")
                }
                value: dialog.password
                invalid: dialog.attempted && (dialog.flow?.supplementaryIsError ?? false)
                onEdited: (t) => dialog.password = t
                onAccepted: dialog.authenticate()
                onCanceled: dialog.cancel()
            }

            // Mensaje de PAM: error ("Authentication failure") o informativo.
            ThemedText {
                Layout.fillWidth: true
                visible: text !== ""
                text: dialog.flow?.supplementaryMessage ?? ""
                color: (dialog.flow?.supplementaryIsError ?? false) ? Theme.red : Theme.fgMuted
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSize - 2
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                spacing: Theme.space8

                Item { Layout.fillWidth: true }

                TextButton {
                    text: I18n.tr("Cancel")
                    onClicked: dialog.cancel()
                }
                TextButton {
                    text: I18n.tr("Authenticate")
                    primary: true
                    enabled: !(dialog.flow?.isResponseRequired ?? false) || dialog.password !== ""
                    onClicked: dialog.authenticate()
                }
            }

            function authenticate() {
                if (!dialog.flow)
                    return
                dialog.attempted = true
                dialog.flow.submit(dialog.password)
                // PAM vuelve a pedirla si falla; se limpia para no dejar la
                // anterior escrita en el campo.
                dialog.password = ""
            }

            function cancel() {
                if (dialog.flow)
                    dialog.flow.cancelAuthenticationRequest()
            }

            onDismissed: cancel()

            // El foco tiene que llegar cuando la ventana ya está mapeada; en el
            // mismo frame del onCompleted el compositor aún no la ha colocado.
            Component.onCompleted: focusTimer.restart()
            Timer {
                id: focusTimer
                interval: 60
                onTriggered: pwField.forceFocus()
            }
        }
    }
}
