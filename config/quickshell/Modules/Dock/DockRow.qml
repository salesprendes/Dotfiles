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
// "pill" flota, va centrada y mide lo que mida su contenido. "hotseat" va
// pegada al borde, de lado a lado, con las esquinas de arriba redondeadas.
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
    signal hoverAccion(var boton, string nombre, bool dentro)

    readonly property var ranuras: Dock.ranuras
    readonly property int sepAt: DockCatalog.separatorIndex(root.ranuras)

    readonly property int relleno: Theme.dp(Settings.dockPadding)
    readonly property int hueco: Theme.dp(Settings.dockSpacing)

    // La lupa es una ONDA, no un interruptor: el icono bajo el cursor crece del
    // todo y los vecinos menos según se alejan, así que la fila se hincha en vez
    // de dar un salto. Sin el desplazamiento lateral el icono ampliado se comería
    // al de al lado; con él, los vecinos se apartan y la fila respira.
    //
    // La cuenta se hace SIEMPRE desde la posición en reposo de cada botón y desde
    // el cursor, nunca desde la geometría ya ampliada: el crecimiento se aplica
    // como 'scale' y 'transform', que no tocan la disposición del Row, así que el
    // centro de reposo no cambia nunca y no hay bucle de vínculos posible.
    readonly property real cajaBoton: Theme.dp(Settings.dockIconSize) + Theme.dp(16)
    // Dos botones y medio a cada lado: menos y la ola se ve dura, más y todo el
    // dock se mueve a la vez y deja de leerse de dónde viene.
    readonly property real alcance: (root.cajaBoton + root.hueco) * 2.5
    property real cursorX: 0
    property bool cursorDentro: false

    // Con la ola activa los iconos de los extremos se apartan y crecen. Sin
    // ensanchar la pastilla se saldrían de ella y el dock parecería roto.
    //
    // Ensancha una cantidad FIJA mientras hay cursor encima, no una que dependa
    // de dónde está: la posición en pantalla de los iconos no depende del ancho
    // de la pastilla —DockRow va centrada y 'fila' se centra dentro de 'carril',
    // y las dos mitades se cancelan—, así que ensanchar no mueve el contenido ni
    // altera la coordenada del cursor con la que se calcula la ola. Si dependiera
    // de la posición, sí habría bucle.
    //
    // Única propiedad del fichero que NO es readonly, y no por descuido: un
    // Behavior no puede animar una readonly. Nadie le asigna nada, que es lo
    // que la convención de arriba protege.
    property real ensanche: (root.cursorDentro && Settings.dockMagnify > 1.001)
        ? (Settings.dockMagnify - 1) * root.cajaBoton * 1.4
        : 0
    Behavior on ensanche {
        enabled: Theme.animNormal > 0
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    // 1 en el cursor, 0 en el borde del alcance, con transición suave.
    function factorLupa(centro) {
        if (!root.cursorDentro || Settings.dockMagnify <= 1.001)
            return 0
        const t = 1 - Math.min(1, Math.abs(centro - root.cursorX) / root.alcance)
        return t * t * (3 - 2 * t)
    }

    // Cuánto se aparta un botón del cursor. Cero justo debajo —ese no se mueve,
    // solo crece— y constante más allá del alcance, que es lo que hace que los
    // de los extremos acompañen el ensanchamiento en vez de quedarse pegados.
    function empujeLupa(centro) {
        if (!root.cursorDentro || Settings.dockMagnify <= 1.001)
            return 0
        const d = centro - root.cursorX
        const u = Math.min(1, Math.abs(d) / root.alcance)
        return Math.sign(d) * (Settings.dockMagnify - 1) * root.cajaBoton * 0.9
               * (u * u * (3 - 2 * u))
    }

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
        : Math.min(root.anchoMax,
                   fila.implicitWidth + root.relleno * 2 + root.ensanche * 2)

    // Radio: -1 en Ajustes significa "lo decide el estilo". Una pastilla
    // completa para "pill"; solo las esquinas de arriba para "hotseat", que
    // está pegado al borde de la pantalla y redondearle las de abajo dejaría
    // dos muescas de fondo de escritorio en el canto.
    readonly property int radioAuto: root.esHotseat ? Theme.shapeXl
                                                    : Math.round(root.altoDock / 2)
    readonly property int radio: Settings.dockRadius >= 0
                                 ? Theme.dp(Settings.dockRadius) : root.radioAuto

    // La sombra. Va antes del fondo en el árbol para quedar
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

        // Luz en el canto de arriba. Es lo que separa "rectángulo semitransparente"
        // de "cristal": una superficie translúcida se lee como material cuando el
        // borde superior recoge algo de luz.
        //
        // Va como degradado y no como filete de 1 px porque en una pastilla el
        // borde de arriba es un arco, y un rectángulo no lo sigue. El degradado sí,
        // y sirve igual para el radio que tenga.
        Rectangle {
            anchors.fill: parent
            topLeftRadius: fondo.topLeftRadius
            topRightRadius: fondo.topRightRadius
            bottomLeftRadius: fondo.bottomLeftRadius
            bottomRightRadius: fondo.bottomRightRadius
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Theme.withAlpha("#ffffff", Theme.isDark ? 0.07 : 0.30)
                }
                GradientStop { position: 0.45; color: "transparent" }
            }
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
        // Solo se recorta cuando hace falta: con la fila desplazable, para que
        // no se pinte fuera del carril. Cuando cabe entera —el caso normal— se
        // deja sin recortar para que los iconos ampliados asomen por encima de
        // la píldora en vez de quedar cortados por su borde.
        clip: carril.contentWidth > carril.width + 0.5
        contentWidth: fila.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: fila
            height: parent.height

            HoverHandler {
                id: raton
                onPointChanged: root.cursorX = raton.point.position.x
                onHoveredChanged: root.cursorDentro = raton.hovered
            }
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
                        id: boton
                        anchors.verticalCenter: parent.verticalCenter
                        // En coordenadas de 'fila'. 'x' es la posición que pone
                        // el Row y no la toca ni la escala ni el transform, así
                        // que este centro es estable aunque la ola esté activa.
                        readonly property real centro: celda.x + boton.x + boton.width / 2
                        escalaLupa: 1 + (Settings.dockMagnify - 1) * root.factorLupa(boton.centro)
                        empujeLupa: root.empujeLupa(boton.centro)
                        ranura: celda.modelData
                        onPideMenu: (r, x, y) => root.pideMenu(r, x, y)
                        onHoverCambia: (r, b, d) => root.hoverCambia(r, b, d)
                    }
                }
            }

            // Aquí van el lanzador y Spotlight, que es lo más parecido a una
            // vista general que tiene este shell: buscar y saltar a algo sin
            // levantar las manos del sitio.
            //
            // Van dentro del mismo Row, detrás de un filete, y no en una zona
            // aparte fuera del carril desplazable: fuera, con la fila desbordada,
            // quedarían clavados mientras las apps se mueven por debajo, y eso se
            // lee como dos docks pegados.
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
                id: btnLanzador
                anchors.verticalCenter: parent.verticalCenter
                visible: Settings.dockShowLauncher
                nombre: I18n.tr("Applications")
                onHoverCambia: (b, d) => root.hoverAccion(b, nombre, d)
                readonly property real centro: btnLanzador.x + btnLanzador.width / 2
                escalaLupa: 1 + (Settings.dockMagnify - 1) * root.factorLupa(btnLanzador.centro)
                empujeLupa: root.empujeLupa(btnLanzador.centro)
                glifo: "󰀻"
                onActivada: Globals.toggleLauncher()
            }

            DockActionButton {
                id: btnSpotlight
                anchors.verticalCenter: parent.verticalCenter
                visible: Settings.dockShowSpotlight
                nombre: I18n.tr("Spotlight")
                onHoverCambia: (b, d) => root.hoverAccion(b, nombre, d)
                readonly property real centro: btnSpotlight.x + btnSpotlight.width / 2
                escalaLupa: 1 + (Settings.dockMagnify - 1) * root.factorLupa(btnSpotlight.centro)
                empujeLupa: root.empujeLupa(btnSpotlight.centro)
                glifo: "󰍉"
                onActivada: Globals.toggleSpotlight()
            }
        }

        // Con la fila desbordada, cortar en seco contra el borde de la pastilla
        // se lee como un fallo de pintado. Un degradado hacia el color del
        // fondo dice «sigue habiendo cosas por aquí».
        //
        // Son dos degradados del color del propio fondo, que no montan una capa
        // de composición y solo existen cuando hacen falta.
        //
        // El color sale de 'fondo' y no se vuelve a componer aquí: escrito dos
        // veces, el día que cambie el fondo el degradado se quedaría con el color
        // viejo y aparecería una banda que no cuadra con nada.
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
