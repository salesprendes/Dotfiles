import QtQuick
import QtQuick.Effects
import qs.Config
import qs.Services

// La pastilla —o la barra— con los iconos dentro.
//
// Se llama DockRow y no Dock porque 'Dock' ya es el singleton de
// Services/Dock.qml: dos tipos con el mismo nombre en el mismo alcance y QML
// resuelve al singleton, con el error de que no es instanciable.
//
// ── LO ÚNICO QUE CAMBIA ENTRE LAS DOS FORMAS ────────────────────────────────
// "pill" es la barra de tareas de tableta Android: flota, va centrada y mide
// lo que mida su contenido. "hotseat" es la del Pixel Launcher: pegada al
// borde, de lado a lado, con las esquinas de arriba redondeadas.
//
// La diferencia entre ambas vive ENTERA en este archivo y en los márgenes de
// DockWindow: el ancho, el radio y poco más. Ni DockButton, ni DockPreview, ni
// DockMenu saben en qué estilo están. Por eso ofrecer las dos formas cuesta un
// puñado de líneas en vez del doble de superficie que probar.
Item {
    id: root

    // readonly, como todo lo que tiene un binding: una propiedad CON binding a
    // la que alguien asigne pierde el binding para siempre, sin aviso. Es el
    // fallo que se comió a Globals.spotlightOpen; no vale la pena dejar la
    // trampa puesta por ahorrar una palabra.
    readonly property bool esHotseat: Settings.dockStyle === "hotseat"
    // Ancho disponible de la pantalla. Lo pone DockWindow.
    property real anchoPantalla: 0

    signal pideMenu(var ranura, real x, real y)
    signal hoverCambia(var ranura, var boton, bool dentro)

    readonly property var ranuras: Dock.ranuras
    readonly property int sepAt: DockCatalog.separatorIndex(root.ranuras)

    readonly property int relleno: Theme.dp(Settings.dockPadding)
    readonly property int hueco: Theme.dp(Settings.dockSpacing)

    // El alto lo marca el botón más el relleno de arriba y abajo. Es la única
    // medida que las dos formas comparten tal cual.
    readonly property int altoDock: Theme.dp(Settings.dockIconSize)
                                    + Theme.dp(16) + root.relleno * 2

    // Tope del 90 %: un dock con treinta apps abiertas no puede salirse de la
    // pantalla, y a partir de ahí la fila se desplaza con la rueda.
    readonly property real anchoMax: root.anchoPantalla * 0.9

    implicitHeight: root.altoDock
    implicitWidth: root.esHotseat
        ? root.anchoPantalla
        : Math.min(root.anchoMax, fila.implicitWidth + root.relleno * 2)

    // Radio: -1 en Ajustes significa "lo decide el estilo". Una pastilla
    // completa para "pill"; solo las esquinas de arriba para "hotseat", que
    // está pegado al borde de la pantalla y redondearle las de abajo dejaría
    // dos muescas de fondo de escritorio en el canto.
    readonly property int radioAuto: root.esHotseat ? Theme.shapeXl
                                                    : Math.round(root.altoDock / 2)
    readonly property int radio: Settings.dockRadius >= 0
                                 ? Theme.dp(Settings.dockRadius) : root.radioAuto

    // La sombra de nandoroid. Va ANTES del fondo en el árbol para quedar
    // debajo, y no dentro de él: un hijo de 'fondo' se recortaría con sus
    // esquinas redondeadas y la sombra es justo lo que tiene que desbordarlas.
    RectangularShadow {
        anchors.fill: fondo
        visible: Settings.dockShadow
        radius: root.radio
        blur: Theme.dp(18)
        spread: Theme.dp(1)
        offset: Qt.vector2d(0, Theme.dp(2))
        color: Theme.withAlpha("#000000", Theme.isDark ? 0.45 : 0.22)
        cached: true
    }

    Rectangle {
        id: fondo
        anchors.fill: parent
        color: Theme.withAlpha(Theme.bg, Settings.dockOpacity)
        // El mismo tratamiento que la isla, que es la otra superficie flotante
        // del shell: sin este filete, sobre un fondo de pantalla oscuro el dock
        // no tiene borde y parece un recorte.
        border.width: 1
        border.color: Theme.withAlpha(Theme.overlay, 0.35)
        antialiasing: true

        topLeftRadius: root.radio
        topRightRadius: root.radio
        bottomLeftRadius: root.esHotseat ? 0 : root.radio
        bottomRightRadius: root.esHotseat ? 0 : root.radio

        Behavior on color {
            enabled: Theme.animNormal > 0
            ColorAnimation { duration: Theme.animFast }
        }
    }

    // Fila desplazable. Flickable y no ListView porque el separador va
    // INTERCALADO entre dos elementos del modelo, y un ListView obligaría a
    // inventarse una fila falsa en el modelo para representarlo — una entrada
    // que no es una app dentro de la lista de apps, con todo lo que eso ensucia
    // aguas abajo. Con decenas de iconos, un Repeater no cuesta nada.
    Flickable {
        id: carril
        anchors.fill: parent
        anchors.leftMargin: root.relleno
        anchors.rightMargin: root.relleno
        clip: true
        contentWidth: fila.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: fila
            height: parent.height
            // En hotseat la fila va centrada dentro de una barra que ocupa toda
            // la pantalla; en pastilla, la pastilla ya mide lo que la fila.
            x: Math.max(0, Math.round((carril.width - implicitWidth) / 2))
            spacing: root.hueco

            Repeater {
                model: root.ranuras
                delegate: Row {
                    id: celda
                    required property var modelData
                    required property int index
                    height: fila.height
                    spacing: root.hueco

                    // Row ignora por completo a los hijos invisibles —ni su
                    // ancho ni el espaciado de sus lados—, así que con
                    // 'visible' basta: no hace falta forzarle el ancho a cero.
                    DockSeparator {
                        height: Math.round(fila.height * 0.55)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: celda.index === root.sepAt
                    }

                    DockButton {
                        anchors.verticalCenter: parent.verticalCenter
                        ranura: celda.modelData
                        onPideMenu: (r, x, y) => root.pideMenu(r, x, y)
                        onHoverCambia: (r, b, d) => root.hoverCambia(r, b, d)
                    }
                }
            }

            // ── Los botones del final ────────────────────────────────────────
            // Nandoroid pone aquí «vista general» y «lanzador». Este shell no
            // tiene vista general, así que el segundo es Spotlight, que es lo
            // más parecido que hay: buscar y saltar a algo sin levantar las
            // manos del sitio.
            //
            // Van DENTRO del mismo Row, detrás de un filete, y no en una zona
            // aparte fuera del carril desplazable: fuera, con la fila
            // desbordada, quedarían clavados mientras las apps se mueven por
            // debajo, y eso se lee como dos docks pegados.
            DockSeparator {
                height: Math.round(fila.height * 0.55)
                anchors.verticalCenter: parent.verticalCenter
                visible: (Settings.dockShowLauncher || Settings.dockShowSpotlight)
                         && root.ranuras.length > 0
            }

            // Llaman a toggle y no a open, aunque desde aquí SOLO pueden abrir:
            // el dock se esconde con cualquier panel abierto (ver DockWindow),
            // así que la mitad de "cerrar" de un toggle no se puede alcanzar
            // desde este botón. Se deja toggle porque es lo que hacen la barra
            // y los atajos, y así los tres sitios dicen lo mismo.
            //
            // Por lo mismo NO llevan estado 'activo': mientras el panel está
            // abierto, este dock no se ve. Un resaltado que no puede llegar a
            // verse es una comprobación por fotograma que no dice nada.
            DockActionButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: Settings.dockShowLauncher
                glifo: "󰀻"
                onActivada: Globals.toggleLauncher()
            }

            DockActionButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: Settings.dockShowSpotlight
                glifo: "󰍉"
                onActivada: Globals.toggleSpotlight()
            }
        }

        // ── Desvanecido en los bordes ────────────────────────────────────────
        // Con la fila desbordada, cortar en seco contra el borde de la pastilla
        // se lee como un fallo de pintado. Un degradado hacia el color del
        // fondo dice «sigue habiendo cosas por aquí».
        //
        // Nandoroid lo hace con un OpacityMask de Qt5Compat, que en este equipo
        // no está instalado. Dos degradados del color del propio fondo hacen lo
        // mismo, no montan una capa de composición y solo existen cuando hace
        // falta.
        // El color sale de 'fondo', no se vuelve a componer aquí: escrito dos
        // veces, el día que cambie el fondo el degradado se queda con el color
        // viejo y aparece una banda que no cuadra con nada.
        component Velo: Rectangle {
            width: Theme.dp(24)
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: fondo.color }
                GradientStop { position: 1.0
                    color: Theme.withAlpha(fondo.color, 0) }
            }
        }

        Velo {
            x: carril.contentX
            visible: carril.interactive && carril.contentX > 1
        }
        Velo {
            x: carril.contentX + carril.width - width
            rotation: 180
            visible: carril.interactive
                     && carril.contentX < carril.contentWidth - carril.width - 1
        }

        // La rueda desplaza en horizontal. Sin esto, con la fila desbordada, la
        // rueda sobre el dock no haría nada: el usuario ve iconos cortados por
        // el borde y no tiene forma de llegar a ellos con el ratón.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: carril.interactive
            onWheel: (ev) => {
                const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
                carril.contentX = Math.max(0, Math.min(carril.contentX - d,
                                           carril.contentWidth - carril.width))
            }
        }
    }
}
