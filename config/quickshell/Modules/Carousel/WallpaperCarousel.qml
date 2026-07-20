pragma ComponentBehavior: Bound
// Carrusel coverflow para elegir el fondo. Plugin autocontenido: se instancia
// con una línea en shell.qml y registra su propio IPC. Aplica el fondo con
// Wallpaper.apply (cambio en vivo vía Backdrop). Se abre/cierra con
// `qs ipc call carousel toggle` (Super+W en Hyprland).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Config
import qs.Services

Scope {
    id: plugin

    property bool open: false
    property int  selectedIndex: 0
    property string _originalPath: ""     // fondo previo, para restaurar al cancelar
    property bool _awaitingRefreshSync: false
    property bool _userNavigated: false
    property bool _suppressPreview: false
    property bool _syncingView: false
    property int _lastMoveAt: 0
    property int _lastKeyboardMoveAt: 0
    property bool _fastNavigation: false
    property bool _instantSync: false     // recolocar la vista SIN animación (evita el "gran salto")

    readonly property var    items:   Wallpaper.list
    readonly property int    count:   items.length
    readonly property string curPath: (count > 0 && selectedIndex >= 0 && selectedIndex < count) ? items[selectedIndex] : ""
    readonly property string curName: curPath === "" ? "" : String(curPath).split("/").pop()
    readonly property bool   loading: open && count === 0 && (_awaitingRefreshSync || Wallpaper.scanning)
    readonly property int    previewDelay: _fastNavigation ? 55 : 150
    readonly property int    carouselMoveMs: _fastNavigation ? 85 : 240
    readonly property int    cardAnimMs: _fastNavigation ? 90 : 230

    signal forceViewSync()

    function _normalizedPath(path) {
        let s = String(path || "")
        if (s.indexOf("file://") === 0) {
            s = s.slice(7)
            try { s = decodeURIComponent(s) } catch (e) {}
        }
        while (s.length > 1 && s.endsWith("/"))
            s = s.slice(0, -1)
        return s
    }

    function _fileName(path) {
        const parts = _normalizedPath(path).split("/")
        return parts.length > 0 ? parts[parts.length - 1] : ""
    }

    function _imageUrl(path) {
        const s = String(path || "")
        return s.indexOf("file://") === 0 ? s : "file://" + s
    }

    function _findIndexForPath(path) {
        const target = _normalizedPath(path)
        if (target === "" || count === 0)
            return -1

        for (let i = 0; i < count; i++) {
            if (_normalizedPath(items[i]) === target)
                return i
        }

        const name = _fileName(target)
        if (name === "")
            return -1
        for (let i = 0; i < count; i++) {
            if (_fileName(items[i]) === name)
                return i
        }
        return -1
    }

    function _selectIndex(index, preview) {
        if (count === 0)
            return

        const next = (index + count) % count
        previewTimer.stop()
        _suppressPreview = !preview
        _instantSync = !preview        // programático (sin preview) → recoloca instantáneo
        selectedIndex = next
        _suppressPreview = false
        forceViewSync()
    }

    function _moveFromKeyboard(d) {
        const now = Date.now()
        if (now - _lastKeyboardMoveAt < 70)
            return
        _lastKeyboardMoveAt = now
        move(d)
    }

    function _syncToCurrentWallpaper(allowFallback) {
        const target = _originalPath !== "" ? _originalPath : Wallpaper.current
        const i = _findIndexForPath(target)
        if (i >= 0) {
            _selectIndex(i, false)
            return true
        }
        if (allowFallback && count > 0) {
            _selectIndex(0, false)
            return true
        }
        return false
    }

    // API interna
    function setOpen(v) {
        if (v === open) return
        if (v) {
            Globals.closeAll()          // cierra otros popups del shell
            _originalPath = Wallpaper.current
            _awaitingRefreshSync = true
            _userNavigated = false
            _lastMoveAt = 0
            _lastKeyboardMoveAt = 0
            _fastNavigation = false
            previewTimer.stop()
            _syncToCurrentWallpaper(true)
            Wallpaper.refresh()         // reescanea por si hay fondos nuevos
            open = true
            forceViewSync()
        } else {
            // Cerrar sin confirmar = cancelar → restaura el fondo previo.
            previewTimer.stop()
            if (_originalPath !== "" && Wallpaper.current !== _originalPath)
                Wallpaper.current = _originalPath
            _originalPath = ""
            _awaitingRefreshSync = false
            _userNavigated = false
            _lastMoveAt = 0
            _lastKeyboardMoveAt = 0
            _fastNavigation = false
            open = false
        }
    }
    function move(d) {
        if (count === 0) return
        const now = Date.now()
        const elapsed = _lastMoveAt === 0 ? 9999 : now - _lastMoveAt
        if (elapsed < 65)
            return
        _fastNavigation = elapsed < 260
        fastNavigationReset.restart()
        _lastMoveAt = now
        _userNavigated = true
        _selectIndex(selectedIndex + d, true)
    }
    function jumpTo(index) {
        if (count === 0) return
        _userNavigated = true
        _selectIndex(index, true)
    }
    function applySelected() {
        if (curPath !== "") Wallpaper.apply(curPath)   // persiste el elegido
        previewTimer.stop()
        _originalPath = ""                              // confirmado: no restaurar
        _awaitingRefreshSync = false
        _userNavigated = false
        _fastNavigation = false
        open = false
    }

    // Vista previa en vivo: al navegar muestra el fondo resaltado sin persistir
    // (solo Wallpaper.current, Backdrop hace la transición). Con un pequeño
    // retardo para no encadenar transiciones al desplazarse rápido. Se confirma
    // con Enter/clic; Esc restaura el fondo previo.
    onSelectedIndexChanged: if (open && !_suppressPreview) previewTimer.restart()
    Timer {
        id: previewTimer
        interval: plugin.previewDelay
        onTriggered: if (plugin.open && plugin.curPath !== "") Wallpaper.current = plugin.curPath
    }

    Timer {
        id: fastNavigationReset
        interval: 320
        repeat: false
        onTriggered: plugin._fastNavigation = false
    }

    Connections {
        target: Wallpaper
        function onListChanged() {
            if (!plugin.open)
                return
            if (!plugin._userNavigated)
                plugin._syncToCurrentWallpaper(true)
            plugin.forceViewSync()
        }
        function onScanningChanged() {
            if (!plugin.open || Wallpaper.scanning)
                return
            plugin._awaitingRefreshSync = false
            if (!plugin._userNavigated)
                plugin._syncToCurrentWallpaper(true)
            plugin.forceViewSync()
        }
    }

    // IPC propio del plugin (no toca el IpcHandler del shell)
    IpcHandler {
        target: "carousel"
        function toggle(): void { plugin.setOpen(!plugin.open) }
        function show():   void { plugin.setOpen(true) }
        function hide():   void { plugin.setOpen(false) }
        function next():   void { plugin.move(1) }
        function prev():   void { plugin.move(-1) }
    }

    // Si se abre cualquier panel del shell, cierra el carrusel.
    Connections {
        target: Globals
        function onOpenPanelChanged() { if (Globals.openPanel !== "") plugin.setOpen(false) }
    }

    // Ventana overlay (pantalla principal)
    PanelWindow {
        id: win
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: plugin.open || root.opacity > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-wallpaper-carousel"
        WlrLayershell.keyboardFocus: plugin.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        Connections {
            target: plugin
            function onOpenChanged() { if (plugin.open) Qt.callLater(root.forceActiveFocus) }
        }

        Item {
            id: root
            anchors.fill: parent
            focus: true
            opacity: plugin.open ? 1 : 0
            scale: plugin.open ? 1 : 0.985
            Behavior on opacity { NumberAnimation { duration: Math.max(1, Theme.animNormal); easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: Math.max(1, Theme.animNormal); easing.type: Easing.OutCubic } }

            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { plugin.setOpen(false); e.accepted = true }
                else if (e.key === Qt.Key_Left  || e.key === Qt.Key_H) { plugin._moveFromKeyboard(-1); e.accepted = true }
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) { plugin._moveFromKeyboard(1);  e.accepted = true }
                else if (e.key === Qt.Key_Home) { plugin.jumpTo(0); e.accepted = true }
                else if (e.key === Qt.Key_End)  { plugin.jumpTo(plugin.count - 1); e.accepted = true }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                    plugin.applySelected(); e.accepted = true
                }
            }

            // Fondo oscurecido; clic fuera de una tarjeta cierra.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.86)
                MouseArea { anchors.fill: parent; onClicked: plugin.setOpen(false) }
            }

            // Rueda del ratón en cualquier punto → navegar.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (e) => plugin.move(e.angleDelta.y < 0 ? 1 : -1)
            }

            // Título.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Math.round(parent.height * 0.09)
                text: I18n.tr("Wallpaper")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(22)
                font.bold: true
            }

            // Carrusel coverflow
            PathView {
                id: view
                anchors.fill: parent
                anchors.topMargin: parent.height * 0.16
                anchors.bottomMargin: parent.height * 0.18
                visible: plugin.count > 0

                model: plugin.items
                pathItemCount: Math.max(1, Math.min(plugin.count, Math.ceil(width / Math.max(1, cardW)) + 4))
                cacheItemCount: plugin._fastNavigation ? 12 : 8
                interactive: false
                snapMode: PathView.SnapToItem
                highlightRangeMode: PathView.StrictlyEnforceRange
                preferredHighlightBegin: 0.5
                preferredHighlightEnd: 0.5
                highlightMoveDuration: plugin._instantSync ? 0 : plugin.carouselMoveMs
                movementDirection: PathView.Shortest

                readonly property real cardW: Math.max(Theme.dp(220), Math.min(Theme.dp(300), width * 0.24))
                readonly property real cardH: cardW * 1.4
                // Escala del monitor: las texturas se decodifican a píxeles
                // FÍSICOS; con el tamaño lógico se veían borrosas en escala >1.
                readonly property real dpr: (win.screen && win.screen.devicePixelRatio) ? win.screen.devicePixelRatio : 1
                readonly property real skewFactor: -0.26

                function syncToPluginIndex() {
                    if (view.currentIndex === plugin.selectedIndex)
                        return
                    plugin._syncingView = true
                    view.currentIndex = plugin.selectedIndex
                    Qt.callLater(() => { plugin._syncingView = false })
                }

                Component.onCompleted: currentIndex = plugin.selectedIndex
                onCurrentIndexChanged: {
                    if (!plugin._syncingView && currentIndex >= 0 && plugin.selectedIndex !== currentIndex) {
                        plugin._userNavigated = true
                        plugin._selectIndex(currentIndex, true)
                    }
                }
                onCountChanged: {
                    // El modelo se pobló/reordenó: recoloca la vista en el índice
                    // seleccionado sin animación (evita el "gran salto" al abrir).
                    if (count > 0 && currentIndex !== plugin.selectedIndex) {
                        plugin._instantSync = true
                        view.syncToPluginIndex()
                    }
                }
                Connections {
                    target: plugin
                    function onSelectedIndexChanged() { view.syncToPluginIndex() }
                    function onForceViewSync() { view.syncToPluginIndex() }
                    // Al abrir, la ventana pasa a visible y la vista se dispone:
                    // recoloca en el índice actual SIN animación una vez lista
                    // (aplazado a que el layout tenga geometría real).
                    function onOpenChanged() {
                        if (plugin.open) {
                            plugin._instantSync = true
                            Qt.callLater(view.syncToPluginIndex)
                        }
                    }
                }

                // Camino horizontal con tarjetas compactas.
                path: Path {
                    startX: 0
                    startY: view.height / 2
                    PathAttribute { name: "iScale"; value: 0.75 }
                    PathAttribute { name: "iZ";     value: 0 }
                    PathAttribute { name: "iOpac";  value: 0.18 }
                    PathLine { x: view.width * 0.5; y: view.height / 2 }
                    PathAttribute { name: "iScale"; value: 1.08 }
                    PathAttribute { name: "iZ";     value: 100 }
                    PathAttribute { name: "iOpac";  value: 1.0 }
                    PathLine { x: view.width; y: view.height / 2 }
                    PathAttribute { name: "iScale"; value: 0.75 }
                    PathAttribute { name: "iZ";     value: 0 }
                    PathAttribute { name: "iOpac";  value: 0.18 }
                }

                delegate: Item {
                    id: card
                    required property int index
                    required property string modelData

                    readonly property real aScale: PathView.iScale ?? 0.55
                    readonly property real aZ:     PathView.iZ ?? 0
                    readonly property real aOpac:  PathView.iOpac ?? 0.28
                    readonly property bool isCurrent: index === view.currentIndex

                    width: view.cardW
                    height: view.cardH
                    z: aZ
                    scale: aScale
                    opacity: aOpac
                    // Al moverse rápido, easing sin rebote (OutQuad) para que sea
                    // fluido; en reposo, un OutBack con un puntito de vida.
                    Behavior on scale   { NumberAnimation { duration: plugin.cardAnimMs; easing.type: plugin._fastNavigation ? Easing.OutQuad : Easing.OutBack } }
                    Behavior on opacity { NumberAnimation { duration: plugin.cardAnimMs; easing.type: Easing.OutQuad } }

                    Item {
                        id: skewedCard
                        anchors.fill: parent

                        transform: Matrix4x4 {
                            property real s: view.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1)
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: card.isCurrent ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
                            opacity: innerImage.status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        }

                        Rectangle {
                            id: cardSkeleton
                            anchors.fill: parent
                            color: Qt.rgba(1, 1, 1, 0.08)
                            visible: innerImage.status !== Image.Ready
                            opacity: visible ? 1 : 0
                            clip: true

                            Rectangle {
                                id: shimmer
                                width: parent.width * 0.4
                                height: parent.height
                                color: Qt.rgba(1, 1, 1, 0.13)
                                opacity: 0.8
                                x: -width
                            }

                            SequentialAnimation {
                                // plugin.open además de visible: ocultar la
                                // ventana no detiene animaciones de items, y
                                // una imagen que nunca cargue dejaría este
                                // bucle latiendo con el carrusel cerrado.
                                running: cardSkeleton.visible && plugin.open
                                loops: Animation.Infinite
                                NumberAnimation {
                                    target: shimmer
                                    property: "x"
                                    from: -shimmer.width
                                    to: cardSkeleton.width
                                    duration: 950
                                    easing.type: Easing.InOutSine
                                }
                                PauseAnimation { duration: Theme.animFast }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: card.isCurrent ? Math.max(3, Theme.dp(3)) : Math.max(2, Theme.dp(2))
                            visible: innerImage.status === Image.Ready
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                color: "black"
                            }

                            Image {
                                id: innerImage
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -Theme.dp(50)
                                width: parent.width + (parent.height * Math.abs(view.skewFactor)) + Theme.dp(50)
                                height: parent.height
                                source: plugin._imageUrl(card.modelData)
                                sourceSize: Qt.size(Math.ceil(view.cardW * view.dpr), Math.ceil(view.cardH * view.dpr))
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true

                                transform: Matrix4x4 {
                                    property real s: -view.skewFactor
                                    matrix: Qt.matrix4x4(1, s, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1)
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (card.isCurrent) plugin.applySelected()
                            else plugin.jumpTo(card.index)
                        }
                    }
                }
            }

            // Carga inicial
            Column {
                anchors.centerIn: parent
                spacing: Theme.space10
                visible: plugin.loading
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.dp(54)
                    height: Theme.dp(54)

                    Rectangle {
                        anchors.centerIn: parent
                        width: Theme.dp(42)
                        height: width
                        radius: width / 2
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: Math.max(1, Theme.dp(1))
                        border.color: Qt.rgba(1, 1, 1, 0.14)
                    }

                    Rectangle {
                        width: Theme.dp(9)
                        height: width
                        radius: width / 2
                        color: Theme.accent
                        x: parent.width / 2 - width / 2
                        y: Theme.dp(3)
                    }

                    RotationAnimation on rotation {
                        running: plugin.loading
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                        easing.type: Easing.Linear
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Loading...")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(12)
                }
            }

            // Estado vacío
            Column {
                anchors.centerIn: parent
                spacing: Theme.space8
                visible: plugin.count === 0 && !plugin.loading
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰋫"
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(48)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("No results")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(14)
                }
            }

            // Pie: nombre + contador + ayuda
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(parent.height * 0.07)
                spacing: Theme.space6
                visible: plugin.count > 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: plugin.curName
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(15)
                    font.bold: true
                    elide: Text.ElideMiddle
                    width: Math.min(implicitWidth, root.width * 0.6)
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (plugin.selectedIndex + 1) + " / " + plugin.count
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(12)
                    font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "←  →   ·   Enter   ·   Esc"
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(11)
                }
            }
        }
    }
}
