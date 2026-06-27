import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Config
import qs.Services

// ─────────────────────────────────────────────────────────────
//  Ajustes IP de la conexión activa (wifi o ethernet). Clona la
//  estética de WifiPasswordModal. Al abrirse resuelve la conexión
//  activa con nmcli, lee su configuración IPv4 y la precarga. Permite
//  elegir método Automático (DHCP) o Manual (IP estática) y editar
//  IP / máscara / puerta de enlace / DNS; "Aplicar" lo escribe en
//  NetworkManager con `nmcli connection modify … && nmcli connection up`.
// ─────────────────────────────────────────────────────────────
PanelWindow {
    id: modal

    property var modelData
    screen: modelData
    visible: Net.ipConfigOpen

    // ── Estado ───────────────────────────────────────────────
    property string connName: ""
    property string connType: ""     // "802-11-wireless" | "802-3-ethernet"
    property bool   manual: false    // false=auto(DHCP) · true=estático
    property string ip: ""
    property string mask: ""
    property string gateway: ""
    property string dns: ""
    property string err: ""
    property bool   loading: false
    property bool   applying: false

    readonly property bool isWifi: connType === "802-11-wireless"

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-ipconfig"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    onVisibleChanged: {
        if (visible) {
            modal.connName = ""; modal.connType = ""; modal.manual = false
            modal.ip = ""; modal.mask = ""; modal.gateway = ""; modal.dns = ""
            modal.err = ""; modal.applying = false; modal.loading = true
            resolveProc.running = true
        }
    }

    // ── Helpers ──────────────────────────────────────────────
    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function maskToPrefix(m) {
        const parts = String(m).split(".")
        if (parts.length !== 4) return -1
        let bits = 0
        for (let i = 0; i < 4; i++) {
            const n = parseInt(parts[i])
            if (isNaN(n) || n < 0 || n > 255) return -1
            bits += (n.toString(2).match(/1/g) || []).length
        }
        return bits
    }
    function prefixToMask(p) {
        p = parseInt(p)
        if (isNaN(p) || p < 0 || p > 32) return ""
        const m = []
        for (let i = 0; i < 4; i++) {
            const n = Math.max(0, Math.min(8, p - 8 * i))
            m.push(n === 0 ? 0 : 256 - Math.pow(2, 8 - n))
        }
        return m.join(".")
    }
    function validIp(s) {
        const parts = String(s).split(".")
        if (parts.length !== 4) return false
        for (let i = 0; i < 4; i++) {
            if (!/^\d{1,3}$/.test(parts[i])) return false
            const n = parseInt(parts[i])
            if (n < 0 || n > 255) return false
        }
        return true
    }
    // ¿Listo para aplicar? En auto siempre; en manual exige IP+máscara válidas.
    readonly property bool ready: !modal.manual
        || (validIp(modal.ip) && modal.maskToPrefix(modal.mask) >= 0
            && (modal.gateway === "" || validIp(modal.gateway)))

    function apply() {
        if (modal.applying || !modal.ready || modal.connName === "") return
        modal.applying = true
        modal.err = ""
        const q = modal.shellQuote
        let cmd
        if (modal.manual) {
            const prefix = modal.maskToPrefix(modal.mask)
            const dnsCsv = modal.dns.trim().replace(/[\s,]+/g, ",")
            cmd = "nmcli connection modify " + q(modal.connName)
                + " ipv4.method manual"
                + " ipv4.addresses " + q(modal.ip + "/" + prefix)
                + " ipv4.gateway " + q(modal.gateway)
                + " ipv4.dns " + q(dnsCsv)
                + " && nmcli connection up " + q(modal.connName)
        } else {
            // Automático (DHCP): limpia los valores manuales.
            cmd = "nmcli connection modify " + q(modal.connName)
                + " ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns ''"
                + " && nmcli connection up " + q(modal.connName)
        }
        applyProc.command = ["sh", "-c", cmd]
        applyProc.running = true
    }

    // ── 1) Resolver la conexión activa (wifi o ethernet) ─────
    Process {
        id: resolveProc
        command: ["sh", "-c",
            "line=$(nmcli -t -f NAME,TYPE connection show --active | "
            + "grep -E ':(802-11-wireless|802-3-ethernet)$' | head -1); "
            + "type=${line##*:}; name=${line%:*}; printf '%s\\n%s\\n' \"$name\" \"$type\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n")
                modal.connName = (lines[0] || "").trim()
                modal.connType = (lines[1] || "").trim()
                if (modal.connName === "") {
                    modal.loading = false
                    modal.err = I18n.tr("No active connection found.")
                    return
                }
                readProc.command = ["sh", "-c",
                    "nmcli -t -f ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns "
                    + "connection show " + modal.shellQuote(modal.connName)]
                readProc.running = true
            }
        }
    }

    // ── 2) Leer la configuración IPv4 actual ─────────────────
    Process {
        id: readProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n")
                for (const ln of lines) {
                    const idx = ln.indexOf(":")
                    if (idx < 0) continue
                    const key = ln.slice(0, idx)
                    const val = ln.slice(idx + 1)
                    if (key === "ipv4.method")
                        modal.manual = (val.trim() === "manual")
                    else if (key === "ipv4.addresses") {
                        const first = val.split(",")[0].trim()   // ej "192.168.1.50/24"
                        if (first.indexOf("/") >= 0) {
                            modal.ip = first.split("/")[0]
                            modal.mask = modal.prefixToMask(first.split("/")[1])
                        }
                    } else if (key === "ipv4.gateway")
                        modal.gateway = val.trim()
                    else if (key === "ipv4.dns")
                        modal.dns = val.trim().replace(/,/g, ", ")
                }
                modal.loading = false
            }
        }
    }

    // ── 3) Aplicar en NetworkManager ─────────────────────────
    Process {
        id: applyProc
        stdout: StdioCollector { }
        stderr: StdioCollector { id: applyErr }
        onExited: (code, status) => {
            modal.applying = false
            if (code === 0) {
                Net.closeIpConfig()
            } else {
                const e = (applyErr.text || "").trim()
                modal.err = e !== "" ? e : I18n.tr("Could not apply the network settings.")
            }
        }
    }

    // ── Fondo oscuro: click cancela ──────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: modal.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea { anchors.fill: parent; onClicked: Net.closeIpConfig() }
    }

    // ── Tarjeta ──────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: Theme.panelWidth(screen, 380, 320, 0.88)
        height: content.implicitHeight + Theme.space18 * 2
        radius: Theme.barRadius + Theme.space2
        color: Theme.bgAlt
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)

        opacity: modal.visible ? 1 : 0
        scale: modal.visible ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // absorbe clicks

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space18 }
            spacing: Theme.space12

            // Cabecera.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10
                Text {
                    text: "󰒓"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.tr("Network settings")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modal.loading ? I18n.tr("Loading...")
                            : (modal.isWifi ? "󰤨  " : "󰈁  ") + modal.connName
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
                }
            }

            // Selector de método: Automático / Manual.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                spacing: Theme.space8
                MethodBtn { label: I18n.tr("Automatic (DHCP)"); on: !modal.manual; onPicked: modal.manual = false }
                MethodBtn { label: I18n.tr("Manual (static)");  on: modal.manual;  onPicked: modal.manual = true }
            }

            // Campos manuales (modo estático): se despliegan/colapsan con
            // animación fluida de ALTURA + OPACIDAD, usando la duración
            // configurada en Ajustes (Theme.animNormal). El alto de la tarjeta
            // sigue al de la columna, así que crece/encoge suavemente.
            Item {
                Layout.fillWidth: true
                clip: true
                enabled: modal.manual
                implicitHeight: modal.manual ? manualCol.implicitHeight : 0
                opacity: modal.manual ? 1 : 0
                Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: manualCol
                    width: parent.width
                    spacing: Theme.space8

                    Field {
                        label: I18n.tr("IP address"); placeholder: "192.168.1.50"
                        value: modal.ip; invalid: modal.ip !== "" && !modal.validIp(modal.ip)
                        onEdited: (t) => modal.ip = t
                    }
                    Field {
                        label: I18n.tr("Subnet mask"); placeholder: "255.255.255.0"
                        value: modal.mask; invalid: modal.mask !== "" && modal.maskToPrefix(modal.mask) < 0
                        onEdited: (t) => modal.mask = t
                    }
                    Field {
                        label: I18n.tr("Gateway"); placeholder: "192.168.1.1"
                        value: modal.gateway; invalid: modal.gateway !== "" && !modal.validIp(modal.gateway)
                        onEdited: (t) => modal.gateway = t
                    }
                    Field {
                        label: I18n.tr("DNS"); placeholder: "1.1.1.1, 8.8.8.8"
                        value: modal.dns; invalid: false
                        onEdited: (t) => modal.dns = t
                    }
                }
            }

            // Error.
            Text {
                Layout.fillWidth: true
                visible: modal.err !== ""
                text: modal.err
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                wrapMode: Text.WordWrap
            }

            // Botones.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                spacing: Theme.space8
                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: cancelTxt.implicitWidth + Theme.controlS
                    implicitHeight: Theme.dp(32)
                    radius: Theme.pillRadius
                    color: cancelMa.containsMouse ? Theme.surfaceHi : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { id: cancelTxt; anchors.centerIn: parent; text: I18n.tr("Cancel"); color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                    MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Net.closeIpConfig() }
                }

                Rectangle {
                    implicitWidth: applyTxt.implicitWidth + Theme.controlS
                    implicitHeight: Theme.dp(32)
                    radius: Theme.pillRadius
                    enabled: modal.ready && !modal.loading
                    opacity: (modal.ready && !modal.loading) ? 1 : 0.5
                    color: applyMa.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        id: applyTxt
                        anchors.centerIn: parent
                        text: modal.applying ? I18n.tr("Applying...") : I18n.tr("Apply")
                        color: Theme.bg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    MouseArea {
                        id: applyMa
                        anchors.fill: parent
                        enabled: modal.ready && !modal.loading
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modal.apply()
                    }
                }
            }
        }
    }

    // ── Componente: botón de método (Auto/Manual) ────────────
    component MethodBtn: Rectangle {
        property string label: ""
        property bool on: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: Theme.dp(32)
        radius: Theme.pillRadius
        color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                  : mbMa.containsMouse ? Theme.surfaceHi : Theme.surface
        border.width: on ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: on ? Theme.accent : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.on ? Theme.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.bold: parent.on
        }
        MouseArea { id: mbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.picked() }
    }

    // ── Componente: campo etiquetado con entrada de texto ────
    component Field: ColumnLayout {
        id: field
        property string label: ""
        property string placeholder: ""
        property string value: ""
        property bool invalid: false
        signal edited(string text)
        Layout.fillWidth: true
        spacing: Theme.space2

        Text {
            text: field.label
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.rowM
            radius: Theme.pillRadius
            color: Theme.surface
            border.width: Theme.hairline
            border.color: field.invalid ? Theme.red
                         : fInput.activeFocus ? Theme.accent
                         : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            TextInput {
                id: fInput
                anchors.fill: parent
                anchors.leftMargin: Theme.space12
                anchors.rightMargin: Theme.space10
                clip: true
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                selectionColor: Theme.accent
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhNoPredictiveText
                // Sincroniza desde el estado (precarga nmcli) sin romper la edición.
                text: field.value
                onTextChanged: if (text !== field.value) field.edited(text)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fInput.text === ""
                    text: field.placeholder
                    color: Theme.fgMuted
                    font: fInput.font
                }
            }
        }
    }
}
