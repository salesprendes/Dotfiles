import QtQuick

// Filtro de "hover fantasma" para listas que se mueven bajo un ratón quieto.
//
// EL PROBLEMA. Una fila de lista hace `onEntered: selectedIndex = index`, que
// es lo correcto mientras el ratón se mueve. Pero `entered` no significa "el
// ratón ha llegado aquí": significa "esta fila y el ratón ahora se tocan", y
// eso también pasa cuando la que se mueve es la FILA. Al escribir en el
// buscador del portapapeles o del lanzador, la lista se refiltra y las filas
// pasan por debajo del cursor parado: cada una emite 'entered' al cruzarlo y
// la selección salta a la que quedó encima, pisando la que el usuario estaba
// eligiendo con las flechas. Se ve como "escribo y el resaltado se me va solo".
//
// LA CURA. No fiarse de 'entered' y mirar la POSICIÓN: solo se acepta un
// cambio de selección si el puntero se ha movido de verdad desde la última vez
// que se le hizo caso. Se mide en coordenadas de un item de referencia (la
// lista), no de la fila, porque la fila se mueve y sus coordenadas locales
// cambian aunque el ratón esté clavado.
//
// USO, en la fila:
//
//     MouseArea {
//         hoverEnabled: true
//         onPositionChanged: (m) => { if (gate.moved(this, m)) panel.selectedIndex = index }
//     }
//
// y en el panel, `PointerMoveGate { id: gate; referenceItem: lista }` más un
// `gate.reset()` cada vez que la lista cambie por teclado o por filtro.
QtObject {
    id: root

    // Item en cuyas coordenadas se mide. Debe ser algo que NO se mueva con la
    // lista (la propia ListView, el panel). Sin él se usa el item que llama,
    // que es justo el que se mueve.
    property Item referenceItem: null
    // Píxeles que hay que recorrer para considerarlo movimiento del usuario.
    property real threshold: 1

    property bool primed: false
    property real lastX: 0
    property real lastY: 0
    // Permite que la PRIMERA muestra cuente, para transiciones que sí vienen
    // del ratón (abrir el panel con el puntero ya dentro de una fila).
    property bool initialSampleAllowed: false

    function reset() {
        root.primed = false
        root.initialSampleAllowed = false
        root.lastX = 0
        root.lastY = 0
    }

    function allowInitialSample() {
        root.reset()
        root.initialSampleAllowed = true
    }

    function moved(item, mouse) {
        if (!item || !mouse) {
            root.reset()
            return false
        }
        const target = root.referenceItem || item
        const point = item.mapToItem(target, mouse.x, mouse.y)
        const firstSample = !root.primed
        const didMove = firstSample
            ? root.initialSampleAllowed
            : (Math.abs(point.x - root.lastX) > root.threshold
               || Math.abs(point.y - root.lastY) > root.threshold)

        // La posición aceptada solo se actualiza cuando se acepta el
        // movimiento. Si se guardara siempre, una serie de pasos por debajo del
        // umbral —un ratón con la mano encima, un trackpad— no llegaría nunca a
        // sumar: cada uno se compararía con el anterior y todos serían
        // "quieto". Guardando solo los aceptados, los pasos pequeños se acumulan
        // hasta cruzar el umbral una vez.
        if (firstSample || didMove) {
            root.lastX = point.x
            root.lastY = point.y
        }
        root.primed = true
        root.initialSampleAllowed = false
        return didMove
    }
}
