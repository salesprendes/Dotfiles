import QtQuick
import qs.Config
import qs.Services

// Quién de los tres globos del dock está abierto, por qué, y dónde se pone.
//
// Vivía dentro de DockWindow, que además hace layer-shell, máscara de entrada,
// autoocultar, reserva de espacio y animación de aparición. Son dos preguntas
// distintas —"¿dónde está la superficie y cuándo existe?" y "¿qué globo hay
// abierto?"— y tenerlas en el mismo archivo obligaba a leer las dos para tocar
// cualquiera.
//
// La coordinación vive AQUÍ y no en cada botón porque las dos reglas que hacen
// usable la vista previa necesitan ver los dos botones a la vez:
//
//   · Al pasar del icono al globo, el globo NO debe cerrarse. De ahí el retardo
//     de salida: sin él, el hueco entre el icono y el globo lo mata en el camino
//     y la función es inservible.
//   · Al pasar de un icono al vecino, el globo debe RECOLOCARSE, no cerrarse y
//     volver a abrirse con su medio segundo de espera.
Item {
    id: pop

    // El DockRow del que cuelgan los globos.
    property Item fila: null

    // El borde de ARRIBA de la pastilla, que no es la 'y' del DockRow: ese item
    // reserva por encima el aire donde crecen los iconos con la lupa. Los globos
    // se apoyan en la pastilla, no en el aire.
    readonly property real tope: pop.fila ? pop.fila.y + pop.fila.aireLupa : 0

    // Las claves son CADENAS, no los objetos del modelo, y eso es un arreglo, no
    // una preferencia de estilo. 'Dock.ranuras' se reconstruye entera en cada
    // cambio y un Repeater con modelo de array destruye y rehace todos sus
    // delegates cuando el contenido cambia (comprobado con Qt 6.11). Comparando
    // objetos, bastaba que otra ventana ganara el foco mientras señalabas un
    // icono para que la ranura pasara a ser otro objeto: el 'salir' del botón ya
    // no casaba con la clave guardada y la etiqueta se quedaba puesta. Una
    // cadena vale lo mismo antes y después de rehacerse el modelo.
    property string claveEtiqueta: ""
    property string textoEtiqueta: ""
    property var botonEtiqueta: null
    property real centroEtiqueta: 0
    property bool etiquetaLista: false

    property string clavePendiente: ""
    property var ranuraVista: null
    property var ranuraPendiente: null
    property var botonVista: null
    property real centroVista: 0
    property bool ratonEnGlobo: false

    property var ranuraMenu: null
    property real centroMenu: 0

    // La máscara de entrada de la ventana tiene que sumar la vista previa, y por
    // eso el Loader se asoma hacia fuera (ver DockWindow.mask).
    readonly property alias itemVista: cargaVista

    readonly property bool vistaAbierta: pop.ranuraVista !== null && Settings.dockPreviews
    readonly property bool menuAbierto: pop.ranuraMenu !== null

    // Cede el sitio a los otros dos: la vista previa ya lleva el nombre en su
    // primera línea, y el menú tapa el icono del que hablaría.
    readonly property bool etiquetaAbierta: pop.etiquetaLista
                                            && pop.claveEtiqueta !== ""
                                            && !pop.vistaAbierta
                                            && !pop.menuAbierto
    readonly property bool abiertos: pop.vistaAbierta || pop.menuAbierto

    // Todo lo efímero se va de una vez. Lo llama DockWindow cuando la superficie
    // desaparece: si la ventana deja de existir, nada que solo tenía sentido
    // sobre ella puede sobrevivir para reaparecer luego con estado viejo.
    function cerrarTodo() {
        pop.cerrarMenu()
        pop.cerrarVista()
        pop.cerrarEtiqueta()
    }

    function hover(ranura, boton, dentro) {
        const clave = (ranura && ranura.id) ? "app:" + ranura.id : ""
        pop.hoverEtiqueta(clave, Dock.nombreDe(ranura ? ranura.id : ""), boton, dentro)
        if (!Settings.dockPreviews)
            return
        if (dentro) {
            pop.botonVista = boton
            pop.ranuraPendiente = ranura
            pop.clavePendiente = clave
            salir.stop()
            // Con un globo ya abierto se salta la espera de entrada: ya estás
            // mirando globos, hacerte esperar medio segundo por cada icono del
            // dock sería absurdo.
            if (pop.vistaAbierta)
                pop.mostrar(ranura, boton)
            else
                entrar.restart()
            return
        }
        entrar.stop()
        if (pop.clavePendiente === clave)
            salir.restart()
    }

    function mostrar(ranura, boton) {
        if (!boton)
            return
        pop.centroVista = boton.mapToItem(pop, boton.width / 2, 0).x
        pop.ranuraVista = ranura
    }

    // Espera corta y no medio segundo: saber cómo se llama un icono no puede
    // costar lo mismo que abrir un globo con miniaturas. Pero alguna hay, o
    // cruzar el dock de lado a lado encendería una etiqueta por icono en el
    // camino.
    function hoverEtiqueta(clave, texto, boton, dentro) {
        if (dentro) {
            pop.botonEtiqueta = boton
            pop.claveEtiqueta = clave
            pop.textoEtiqueta = texto
            // Con una etiqueta ya puesta, pasar al vecino es inmediato.
            if (pop.etiquetaLista)
                pop.colocarEtiqueta()
            else
                etiquetaEntra.restart()
            return
        }
        etiquetaEntra.stop()
        if (pop.claveEtiqueta === clave)
            pop.cerrarEtiqueta()
    }

    function cerrarEtiqueta() {
        etiquetaEntra.stop()
        pop.claveEtiqueta = ""
        pop.botonEtiqueta = null
        pop.etiquetaLista = false
    }

    function colocarEtiqueta() {
        if (!pop.botonEtiqueta)
            return
        const b = pop.botonEtiqueta
        pop.centroEtiqueta = b.mapToItem(pop, b.width / 2, 0).x
        pop.etiquetaLista = true
    }

    function cerrarVista() {
        entrar.stop()
        salir.stop()
        pop.ranuraVista = null
        pop.ranuraPendiente = null
        pop.botonVista = null
        pop.clavePendiente = ""
    }

    function abrirMenu(ranura, xVentana) {
        pop.cerrarVista()
        pop.cerrarEtiqueta()
        pop.centroMenu = xVentana
        pop.ranuraMenu = ranura
    }

    function cerrarMenu() { pop.ranuraMenu = null }

    function _ranuraDe(id) {
        for (const r of Dock.ranuras)
            if (r && r.id === id)
                return r
        return null
    }

    // El modelo del dock se rehace ENTERO —objetos nuevos, delegates nuevos— en
    // cuanto cambia cualquier cosa: una ventana que abre, una que cierra, o solo
    // el foco pasando de una app a otra. Un globo abierto se quedaba entonces
    // enseñando la lista de ventanas de hace un momento, porque su 'ranura' era
    // el objeto viejo, que ya no lo actualiza nadie.
    //
    // Se vuelve a apuntar por id en vez de cerrar: con la vista previa abierta,
    // abrir o cerrar una ventana de esa app ahora se ve en la lista en el acto,
    // que es lo que uno espera de un globo que está mirando.
    //
    // Y se paran las esperas pendientes: son las únicas que llamarían a
    // mapToItem() sobre un botón que puede haberse destruido hace un instante.
    // Lo ya colocado no se toca —el icono sigue en el mismo sitio— y si el cursor
    // no se ha movido, el 'entrar' del delegate nuevo lo vuelve a pedir.
    Connections {
        target: Dock
        function onRanurasChanged() {
            entrar.stop()
            etiquetaEntra.stop()
            pop.botonVista = null
            pop.botonEtiqueta = null

            if (pop.claveEtiqueta.indexOf("app:") === 0
                    && !pop._ranuraDe(pop.claveEtiqueta.substring(4)))
                pop.cerrarEtiqueta()

            if (pop.ranuraPendiente)
                pop.ranuraPendiente = pop._ranuraDe(pop.ranuraPendiente.id)

            if (pop.ranuraVista) {
                const v = pop._ranuraDe(pop.ranuraVista.id)
                if (v)
                    pop.ranuraVista = v
                else
                    pop.cerrarVista()
            }

            if (pop.ranuraMenu) {
                const m = pop._ranuraDe(pop.ranuraMenu.id)
                if (m)
                    pop.ranuraMenu = m
                else
                    pop.cerrarMenu()
            }
        }
    }

    Timer {
        id: entrar
        interval: 500
        onTriggered: pop.mostrar(pop.ranuraPendiente, pop.botonVista)
    }
    Timer {
        id: etiquetaEntra
        interval: 150
        onTriggered: pop.colocarEtiqueta()
    }
    Timer {
        id: salir
        interval: 250
        onTriggered: if (!pop.ratonEnGlobo) pop.cerrarVista()
    }

    // Captador de clics de fondo: solo existe con el menú abierto, y solo
    // entonces la máscara cubre la ventana entera. Con la vista previa NO se
    // pone: la vista previa se cierra sola al retirar el ratón, y un captador a
    // pantalla completa por pasar el ratón por encima de un icono se comería el
    // primer clic de cualquier cosa que hicieras.
    MouseArea {
        anchors.fill: parent
        visible: pop.menuAbierto
        enabled: pop.menuAbierto
        onClicked: pop.cerrarMenu()
    }

    Loader {
        id: cargaVista
        active: pop.vistaAbierta
        visible: active
        sourceComponent: DockPreview {
            ranura: pop.ranuraVista
            // Lo que hay libre entre el borde de arriba de la ventana y la
            // pastilla, con su hueco a los dos lados.
            altoMax: Math.max(Theme.dp(60), pop.tope - Theme.space8 * 2)
            onPideCerrar: pop.cerrarVista()
        }
        // Centrado sobre el icono y acotado a la pantalla: un globo de la app más
        // a la derecha se saldría por el borde y quedaría cortado.
        x: Math.max(Theme.space8,
                    Math.min(pop.width - width - Theme.space8,
                             pop.centroVista - width / 2))
        y: pop.tope - height - Theme.space8

        // Con el ratón DENTRO del globo, el temporizador de salida no debe
        // cerrarlo: es la otra mitad de la histéresis. HoverHandler y no un
        // MouseArea porque un captador encima se comería los clics de las filas,
        // que son justo para lo que está el globo.
        HoverHandler {
            onHoveredChanged: {
                pop.ratonEnGlobo = hovered
                if (hovered) salir.stop()
                else salir.restart()
            }
        }
    }

    Loader {
        active: pop.etiquetaAbierta
        visible: active
        sourceComponent: DockLabel { texto: pop.textoEtiqueta }
        // Mismo estante que la vista previa y misma sujeción a los bordes: la
        // etiqueta de la app más a la derecha se saldría de la pantalla.
        x: Math.max(Theme.space8,
                    Math.min(pop.width - width - Theme.space8,
                             pop.centroEtiqueta - width / 2))
        y: pop.tope - height - Theme.space8
    }

    Loader {
        active: pop.menuAbierto
        visible: active
        sourceComponent: DockMenu {
            ranura: pop.ranuraMenu
            onPideCerrar: pop.cerrarMenu()
        }
        x: Math.max(Theme.space8,
                    Math.min(pop.width - width - Theme.space8,
                             pop.centroMenu - width / 2))
        y: pop.tope - height - Theme.space8
    }
}
