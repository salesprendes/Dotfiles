import QtQuick

// Estado compartido de "vaciar la lista con animación": congela el alto del
// cuerpo, desliza y desvanece la lista, ejecuta el borrado real y devuelve el
// cuerpo al alto de vacío. Lo usan el portapapeles y el centro de
// notificaciones; cada panel aporta sus medidas, su recuento y su acción de
// borrado, y la animación es idéntica en ambos.
QtObject {
    id: state

    // --- Configuración (la aporta cada panel) ---
    // Devuelve el número de elementos visibles de la lista. Es función (no
    // binding) para leer siempre el valor fresco desde los handlers de cambio.
    property var itemCount: () => 0
    // Acción que borra de verdad los elementos del servicio.
    property var clearAll: () => {}
    // Cuerpo cuyo alto se congela durante la animación de vaciado.
    property Item body
    // Lista de la que se lee contentHeight para ajustar el alto del cuerpo.
    property Item list
    // Alto del cuerpo con la lista vacía.
    property real emptyBodyHeight: 120
    // Alto objetivo al quedar vacía (por defecto el normal; el centro de
    // notificaciones lo amplía cuando "No molestar" muestra el símbolo grande).
    property real emptyExtent: emptyBodyHeight
    // Tope de alto del cuerpo con contenido.
    property real maxContentHeight: 430
    // true si el borrado es asíncrono: la animación se queda en el estado
    // "vaciado" y el panel llama a finishClear() cuando el servicio confirma.
    property bool asyncClear: false

    // --- Estado de la animación (los paneles solo lo leen) ---
    property bool clearing: false
    property bool emptyMessageReady: true
    property bool showingClearedState: false
    property real listClearOpacity: 1
    property real listClearOffset: 0
    property bool freezeListHeight: false
    property real frozenListHeight: 0
    property real bodyHeight: emptyBodyHeight

    Behavior on bodyHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    function refreshBodyHeight() {
        if (freezeListHeight || showingClearedState)
            return

        bodyHeight = itemCount() > 0 ? Math.max(emptyBodyHeight, Math.min(maxContentHeight, list.contentHeight))
                                     : emptyExtent
    }

    function clearAnimated() {
        if (clearing)
            return
        if (itemCount() === 0) {
            clearAll()
            return
        }
        clearing = true
        showingClearedState = false
        refreshBodyHeight()
        frozenListHeight = body.height
        bodyHeight = frozenListHeight
        freezeListHeight = true
        clearAnim.restart()
    }

    // Remate del vaciado: pequeña pausa y reseteo del estado. Con borrado
    // síncrono se encadena solo; con asíncrono lo llama el panel cuando el
    // servicio confirma que ha terminado.
    function finishClear() {
        doneAnim.restart()
    }

    readonly property SequentialAnimation clearAnim: SequentialAnimation {
        ScriptAction {
            script: {
                state.emptyMessageReady = false
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: state
                property: "listClearOpacity"
                to: 0
                duration: 260
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: state
                property: "listClearOffset"
                to: 18
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: {
                state.emptyMessageReady = true
                state.showingClearedState = true
                state.clearAll()
                state.freezeListHeight = false
                state.bodyHeight = state.emptyExtent
                if (!state.asyncClear)
                    state.finishClear()
            }
        }
    }

    readonly property SequentialAnimation doneAnim: SequentialAnimation {
        PauseAnimation { duration: 80 }
        ScriptAction {
            script: {
                state.showingClearedState = false
                state.clearing = false
                state.listClearOpacity = 1
                state.listClearOffset = 0
                state.refreshBodyHeight()
            }
        }
    }
}
