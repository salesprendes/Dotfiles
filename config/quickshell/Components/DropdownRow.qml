import QtQuick
import QtQuick.Layouts
import qs.Config

// Desplegable reutilizable (etiqueta + selector con panel animado). Antes era
// un componente inline de Ajustes; extraído a Components para compartirlo entre
// vistas. La animación usa altura + opacidad al abrir y hover por opacidad para
// evitar artefactos de fondo.
//
// Uso:
//   DropdownRow {
//       label: "..."; options: [{ text, value }, …]; current: value
//       onPicked: (v) => { ... }
//   }
ColumnLayout {
    id: root
    property string label: ""
    property var options: []
    property var current
    property bool open: false
    property int maxVisibleItems: 6
    property string detailText: ""
    property int keyboardIndex: -1
    signal picked(var v)

    // Grupo exclusivo opcional: si varios DropdownRow comparten el mismo objeto
    // en 'group' (con una propiedad 'openItem'), solo uno permanece abierto a la
    // vez — al abrir uno, los demás del grupo se cierran automáticamente.
    property QtObject group: null
    Connections {
        target: root.group
        enabled: root.group !== null
        function onOpenItemChanged() {
            if (root.open && root.group.openItem !== root)
                root.open = false
        }
    }

    // Colores derivados de Theme (sobreescribibles). Equivalen a los tokens
    // settings* que usaba el inline original.
    property color controlColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.86)
    property color borderColor:  Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
    property color cardColor:    Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
    property color hoverColor:   Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.74)

    Layout.fillWidth: true
    spacing: Theme.space6

    function currentOption() {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === current) return options[i]
        return options.length > 0 ? options[0] : ({ text: "", value: "" })
    }

    readonly property string currentText: {
        const opt = currentOption()
        return opt && opt.text !== undefined ? opt.text : ""
    }

    readonly property string currentFont: {
        const opt = currentOption()
        return opt && opt.font !== undefined ? opt.font : Theme.fontFamily
    }

    function currentOptionIndex() {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === current) return i
        return options.length > 0 ? 0 : -1
    }

    function syncKeyboardIndex() {
        keyboardIndex = currentOptionIndex()
        optionList.currentIndex = keyboardIndex
    }

    function openForKeyboard() {
        root.open = true
        syncKeyboardIndex()
        if (keyboardIndex >= 0)
            optionList.positionViewAtIndex(keyboardIndex, ListView.Contain)
    }

    function moveKeyboard(delta) {
        if (options.length <= 0)
            return
        if (!root.open) {
            openForKeyboard()
            return
        }

        const start = keyboardIndex >= 0 ? keyboardIndex : currentOptionIndex()
        keyboardIndex = Math.max(0, Math.min(options.length - 1, start + delta))
        optionList.currentIndex = keyboardIndex
        optionList.positionViewAtIndex(keyboardIndex, ListView.Contain)
    }

    function pickKeyboard() {
        if (!root.open) {
            openForKeyboard()
            return
        }

        const idx = keyboardIndex >= 0 ? keyboardIndex : currentOptionIndex()
        if (idx >= 0 && idx < options.length)
            optionList.choose(options[idx].value)
    }

    function closeKeyboard() {
        if (root.open)
            root.open = false
        else
            Globals.closeAll()
    }

    onOpenChanged: {
        if (open) {
            syncKeyboardIndex()
            if (group) group.openItem = root   // reclama el grupo → cierra los demás
        }
    }

    Text {
        text: root.label
        visible: root.label !== ""
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Rectangle {
        id: selector
        Layout.fillWidth: true
        implicitHeight: Theme.rowM
        activeFocusOnTab: enabled
        radius: Theme.pillRadius
        color: root.controlColor
        border.width: activeFocus ? Theme.focusWidth : Theme.hairline
        border.color: activeFocus ? Theme.focusRing : (root.open ? Theme.accent : root.borderColor)
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        Keys.onReturnPressed: root.pickKeyboard()
        Keys.onEnterPressed: root.pickKeyboard()
        Keys.onSpacePressed: root.pickKeyboard()
        Keys.onDownPressed: root.moveKeyboard(1)
        Keys.onRightPressed: root.moveKeyboard(1)
        Keys.onUpPressed: root.moveKeyboard(-1)
        Keys.onLeftPressed: root.moveKeyboard(-1)
        Keys.onEscapePressed: root.closeKeyboard()

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            spacing: Theme.space8

            Text {
                Layout.fillWidth: true
                text: root.currentText
                color: Theme.fg
                font.family: root.currentFont
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }
            Text {
                visible: root.detailText !== ""
                text: root.detailText
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
            }
            Text {
                text: "󰅀"
                rotation: root.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize - 1
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.open = !root.open
                selector.forceActiveFocus()
            }
        }
    }

    Item {
        id: dropdownClip
        Layout.fillWidth: true
        clip: true
        readonly property int optionHeight: Theme.rowM
        readonly property int panelHeight: Math.min(
            Math.max(1, root.maxVisibleItems) * optionHeight + Theme.space4 * 2,
            optionList.contentHeight + Theme.space4 * 2)
        // Solo altura + opacidad, sin scale/desplazamiento (que causaban "salto").
        implicitHeight: root.open ? panelHeight : 0
        Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        Rectangle {
            id: dropdownPanel
            anchors.fill: parent
            radius: Theme.pillRadius
            color: root.cardColor
            border.width: Theme.hairline
            border.color: root.borderColor

            ListView {
                id: optionList
                anchors.fill: parent
                anchors.margins: Theme.space4
                clip: true
                model: root.options
                boundsBehavior: Flickable.StopAtBounds

                function choose(value) {
                    root.picked(value)
                    root.open = false
                }

                delegate: Rectangle {
                    id: optionRow
                    required property var modelData
                    required property int index
                    readonly property bool sel: modelData.value === root.current
                    readonly property bool focused: ListView.isCurrentItem
                    width: ListView.view.width
                    height: dropdownClip.optionHeight
                    radius: Theme.pillRadius - Theme.space2
                    // El color base solo va entre acento-tinte y "transparent";
                    // el hover es una capa aparte que anima su OPACIDAD (así no
                    // se interpola hacia el negro de "transparent").
                    color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                               : focused ? Theme.focusBg : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                    border.width: focused ? Theme.focusWidth : 0
                    border.color: Theme.focusRing

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: root.hoverColor
                        opacity: rowMa.containsMouse && !optionRow.sel && !optionRow.focused ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space10
                        anchors.rightMargin: Theme.space10
                        spacing: Theme.space8

                        Text {
                            Layout.fillWidth: true
                            text: optionRow.modelData.text
                            color: optionRow.sel ? Theme.fg : Theme.fgDim
                            font.family: optionRow.modelData.font !== undefined ? optionRow.modelData.font : Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: optionRow.sel
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: optionRow.sel
                            text: "󰄬"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize - 1
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.keyboardIndex = optionRow.index
                            optionList.currentIndex = optionRow.index
                            optionList.choose(optionRow.modelData.value)
                        }
                    }
                }
            }
        }
    }
}
