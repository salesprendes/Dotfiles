import QtQuick
import qs.Components
import qs.Config

// Lo que comparten un icono de app y un botón de acción del dock: la ola de la
// lupa, la respuesta a la pulsación y la zona sensible.
//
// Se saca a una base porque las dos implementaciones eran idénticas hasta la
// última constante —origen de transformación, escala, Translate, Behavior,
// asimetría de la pulsación, onda— y ese es el peor sitio para que dos copias
// se separen: la ola es una sola curva repartida por toda la fila, y basta que
// una de las dos use otra duración para que un botón vaya medio fotograma
// detrás de su vecino.
//
// Los hijos que se declaren aquí dentro caen en 'lienzo', que es lo que se
// escala. La zona sensible y la onda van FUERA de él, y eso es deliberado:
// están más abajo.
Item {
    id: mag

    // Las pone DockRow desde la posición del cursor sobre la fila entera.
    // 'empujeLupa' va como transform y NO como 'x': cambiar la x movería la
    // disposición del Row, que es justo de donde sale el centro de reposo con
    // el que se calcula esto — el bucle de vínculos que hay que evitar.
    property real escalaLupa: 1.0
    property real empujeLupa: 0
    // Desplazamiento vertical propio del botón. Va aquí y no como un segundo
    // transform del consumidor porque el consumidor ya no tiene dónde ponerlo:
    // dos Translate sobre el mismo item se pisan al escribir el segundo.
    property real brincoY: 0

    property int botones: Qt.LeftButton

    readonly property alias senalado: zona.containsMouse
    readonly property alias pulsando: zona.pressed

    signal pulsada(var ev)
    signal entrada()
    signal salida()

    default property alias contenido: lienzo.data

    transform: Translate {
        x: mag.empujeLupa
        Behavior on x {
            enabled: Theme.animNormal > 0
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }
    }

    // Contenedor de la escala: se escala ESTO y no el propio botón, porque
    // escalar un item que está dentro de un Row le cambia el sitio a los
    // vecinos.
    Item {
        id: lienzo
        anchors.fill: parent

        // Crece desde el borde de ABAJO, no desde el centro, para que el icono
        // suba y asome por encima de la píldora en vez de empujar también hacia
        // el canto inferior.
        transformOrigin: Item.Bottom
        scale: zona.pressed ? 0.92 : mag.escalaLupa
        transform: Translate { y: mag.brincoY }

        // La pulsación entra SIN animar y solo la vuelta se anima: la señal que
        // confirma tu gesto no puede tardar más que el gesto. Es la misma
        // asimetría que Components/RowHighlight usa para el hover.
        //
        // Aviso para quien venga a tocar esto: la escala NO era el problema del
        // "no se ve al pulsar". Se midió. Con OutCubic, un clic de 50 ms ya
        // recorre el 88 % del camino a 0,92 y a los 90 ms está al 100 % — la
        // curva va muy cargada al principio. Lo que no se veía era el COLOR del
        // disco. Aquí la entrada instantánea se queda porque es lo correcto, no
        // porque arreglara nada.
        Behavior on scale {
            enabled: Theme.animNormal > 0
            NumberAnimation {
                duration: zona.pressed ? 0 : Theme.animFast
                easing.type: Easing.OutCubic
            }
        }
    }

    Ripple { id: onda }

    // La zona sensible se ESCALA con la lupa, y ese es el arreglo que justifica
    // media clase: sin ella, el trozo de icono que asoma por encima de la
    // píldora se ve pero no se puede pulsar. Con la lupa al máximo son 24 px de
    // icono muerto en la parte de arriba, justo donde el ojo lo apunta.
    //
    // Escala con 'escalaLupa' y NO con la de 'lienzo', que además encoge a 0,92
    // al pulsar: una zona sensible que encoge bajo el dedo puede dejar el
    // puntero fuera al soltar y perder el clic. Lo que se ve responde; lo que
    // responde no se encoge.
    //
    // El empuje lateral no hace falta repetirlo: el Translate de arriba está en
    // el botón, así que la zona ya lo lleva.
    MouseArea {
        id: zona
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: mag.botones

        transformOrigin: Item.Bottom
        scale: mag.escalaLupa
        Behavior on scale {
            enabled: Theme.animNormal > 0
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }

        onPressed: (ev) => {
            if (ev.button === Qt.LeftButton)
                onda.press(ev.x, ev.y)
        }
        onClicked: (ev) => mag.pulsada(ev)
        onEntered: mag.entrada()
        onExited: mag.salida()
    }
}
