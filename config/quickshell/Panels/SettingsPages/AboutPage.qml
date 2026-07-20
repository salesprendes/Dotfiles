import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Services

// La misma marca que sale al arrancar, los datos del equipo en vivo y los
// créditos.
ColumnLayout {
    id: about
    spacing: Theme.space14

    readonly property bool isArch: ["arch", "archlinux", "arch32"].indexOf(SysMon.distroId) !== -1

    // El reloj de SysMon solo va cuando está la barra o el monitor, así que
    // aquí nos refrescamos por nuestra cuenta mientras la pestaña esté abierta.
    // Mismo intervalo que el tick del servicio (5 s) para no solapar dos
    // sondeos, y parado si la ventana de Ajustes no está a la vista.
    Component.onCompleted: SysMon.refreshStats(false)
    Timer {
        interval: 5000
        running: about.Window.window ? about.Window.window.visible : true
        repeat: true
        onTriggered: SysMon.refreshStats(false)
    }

    // ── Portada: la marca y el nombre, igual que en el arranque ──────────────
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.barRadius
        border.width: Theme.hairline
        border.color: SettingsPalette.settingsBorder
        implicitHeight: heroCol.implicitHeight + Theme.space18 * 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.13 : 0.16) }
            GradientStop { position: 0.55; color: SettingsPalette.settingsCard }
            GradientStop { position: 1.0; color: SettingsPalette.settingsCard }
        }

        ColumnLayout {
            id: heroCol
            anchors.centerIn: parent
            width: parent.width - Theme.space18 * 2
            spacing: Theme.space10

            AppLogo {
                Layout.alignment: Qt.AlignHCenter
                box: Theme.dp(92)
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.space4
                text: "ALVARO"
                color: Theme.fg
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.dp(34)
                font.bold: true
                font.letterSpacing: Theme.dp(2)
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: I18n.tr("Handcrafted Quickshell desktop.")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.dp(1.5)
            }
        }
    }

    // ── El equipo ────────────────────────────────────────────────────────────
    SettingsCard {
        title: I18n.tr("System information")
        glyph: "󰟀"

        InfoRow { glyph: "󰌽"; label: I18n.tr("Distribution"); value: SysMon.distroName }
        InfoRow { glyph: "󰒔"; label: I18n.tr("Kernel");       value: SysMon.kernel }
        InfoRow { glyph: "󰘚"; label: I18n.tr("Architecture"); value: SysMon.arch }
        InfoRow { glyph: "󰟀"; label: I18n.tr("Hostname");     value: SysMon.hostname }
        InfoRow {
            glyph: "󰻠"; label: I18n.tr("Processor")
            value: SysMon.cpuModel + (SysMon.cpuThreads > 1
                   ? "  ·  " + I18n.tr("%1 threads").arg(SysMon.cpuThreads) : "")
        }
        InfoRow {
            glyph: "󰍛"; label: I18n.tr("Memory")
            value: SysMon.memTotalGB > 0
                   ? SysMon.memUsedGB.toFixed(1) + " / " + SysMon.memTotalGB.toFixed(1) + " GB" : ""
        }
        InfoRow {
            glyph: "󰋊"; label: I18n.tr("Disk")
            value: SysMon.diskTotalGB > 0
                   ? SysMon.diskUsedGB.toFixed(0) + " / " + SysMon.diskTotalGB.toFixed(0) + " GB" : ""
        }
        InfoRow { glyph: "󱎫"; label: I18n.tr("Uptime");         value: SysMon.uptime }
        InfoRow { glyph: "󰖯"; label: I18n.tr("Window manager"); value: "Hyprland" }
        InfoRow { glyph: "󰆍"; label: I18n.tr("Shell");          value: "Quickshell" }
    }

    // ── Créditos: quién lo hizo, sobre qué corre y dónde encontrarlo ─────────
    SettingsCard {
        title: I18n.tr("Credits")
        glyph: "󰀄"

        // Dos columnas con un filete en medio.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space12

            // Quién.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.space10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Theme.tileM
                    implicitHeight: Theme.tileM
                    radius: width / 2
                    color: SettingsPalette.accentSoft
                    border.width: Theme.hairline
                    border.color: Theme.withAlpha(Theme.accent, 0.5)
                    Text {
                        anchors.centerIn: parent
                        text: "A"
                        color: Theme.accent
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.iconSize + 8
                        font.bold: true
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: "Álvaro Prendes"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Creator and developer")
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        elide: Text.ElideRight
                    }
                }
            }

            // El filete.
            Rectangle {
                Layout.fillHeight: true
                Layout.topMargin: Theme.space2
                Layout.bottomMargin: Theme.space2
                implicitWidth: Theme.hairline
                color: Theme.withAlpha(Theme.overlay, 0.22)
            }

            // Sobre qué.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.space10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Theme.tileM
                    implicitHeight: Theme.tileM
                    radius: Theme.pillRadius
                    color: SettingsPalette.accentSoft
                    border.width: Theme.hairline
                    border.color: Theme.withAlpha(Theme.accent, 0.4)
                    Text {
                        anchors.centerIn: parent
                        text: SysMon.distroGlyph
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize + 12
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: SysMon.distroName !== "" ? SysMon.distroName : "Linux"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: about.isArch ? "Keep It Simple · rolling release" : SysMon.distroId
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Enlaces.
        LinkRow {
            glyph: "󰊤"
            label: "github.com/salesprendes"
            url: "https://github.com/salesprendes"
        }
        LinkRow {
            visible: about.isArch
            glyph: "󰣇"
            label: "archlinux.org"
            url: "https://archlinux.org"
        }
    }

    // ── Piezas de esta página ────────────────────────────────────────────────

    // Etiqueta a la izquierda, valor a la derecha. Si no hay valor, no aparece.
    component InfoRow: RowLayout {
        property string glyph: ""
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Theme.space10
        visible: value !== ""
        Text {
            text: glyph; color: Theme.accent
            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
        }
        Text {
            text: label; color: Theme.fgDim
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
        }
        Text {
            Layout.fillWidth: true
            text: value; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1; font.bold: true
            horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
        }
    }

    // Fila que se pincha y abre el enlace en el navegador.
    component LinkRow: Rectangle {
        id: linkRoot
        property string glyph: ""
        property string label: ""
        property string url: ""
        Layout.fillWidth: true
        implicitHeight: Theme.rowM
        radius: Theme.pillRadius
        color: linkMa.containsMouse ? SettingsPalette.settingsHover : SettingsPalette.settingsControl
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            spacing: Theme.space10
            Text {
                text: linkRoot.glyph; color: Theme.accent
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                text: linkRoot.label; color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1; font.bold: true
                elide: Text.ElideRight
            }
            Text {
                text: "󰏋"; color: linkMa.containsMouse ? Theme.accent : Theme.fgMuted
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize - 2
            }
        }
        MouseArea {
            id: linkMa
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (linkRoot.url !== "") Quickshell.execDetached(["xdg-open", linkRoot.url])
        }
    }
}
