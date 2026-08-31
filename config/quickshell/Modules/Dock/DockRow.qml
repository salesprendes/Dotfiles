import QtQuick
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

    // Los cuatro números de la ola, con nombre. Sueltos dentro de las fórmulas
    // había que reconstruir mentalmente qué significaba cada factor cada vez que
    // se leía, y son justo los que uno quiere retocar para ajustar el tacto.
    //
    // No van a Theme: son parámetros de ESTE algoritmo, no del aspecto del shell.
    // En Theme invitarían a que otro módulo los reutilizara para otra cosa, y a
    // partir de ahí ya no se pueden tocar sin mirar quién más los usa.
    //
    // Dos botones y medio de alcance: menos y la ola se ve dura, más y todo el
    // dock se mueve a la vez y deja de leerse de dónde viene.
    readonly property real lupaAlcanceBotones: 2.5
    readonly property real lupaFactorEnsanche: 1.4
    readonly property real lupaFactorEmpuje: 0.9
    // Por debajo de esto la lupa se considera apagada. No es 1.0 exacto porque
    // el ajuste es un real que pasa por JSON y por un deslizador.
    readonly property real lupaMinima: 1.001
    readonly property bool lupaActiva: Settings.dockMagnify > root.lupaMinima

    readonly property real alcance: (root.cajaBoton + root.hueco) * root.lupaAlcanceBotones
    property real cursorX: 0
    property bool cursorDentro: false

    // El aire que hay que reservar POR ENCIMA de la pastilla para que quepa el
    // icono ampliado. Esta es la medida que faltaba y de la que salían tres
    // fallos distintos:
    //
    //   · el icono se dibujaba fuera de la máscara de entrada de layer-shell, o
    //     sea que la mitad de arriba se veía pero el clic se iba a la ventana de
    //     detrás (ver DockWindow, que ata su máscara a implicitHeight);
    //   · con la fila desbordada, 'clip' lo cortaba por el canto de la pastilla;
    //   · al subir el cursor hacia esa mitad se salía de la zona de hover y la
    //     ola se desplomaba justo cuando la estabas apuntando.
    //
    // El botón crece (m-1)·caja desde su borde de abajo, y ya tiene 'relleno' de
    // aire dentro de la pastilla; lo que sobresale es la diferencia. Con la lupa
    // por defecto (1,12) sale 0 —no sobresale— y con el máximo del ajuste (1,6)
    // salen unos 24 px. Es decir: hasta 1,164 esto no reserva nada y el dock
    // mide exactamente lo que medía.
    readonly property real aireLupa: root.lupaActiva
        ? Math.max(0, (Settings.dockMagnify - 1) * root.cajaBoton - root.relleno)
        : 0

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
    property real ensanche: (root.cursorDentro && root.lupaActiva)
        ? (Settings.dockMagnify - 1) * root.cajaBoton * root.lupaFactorEnsanche
        : 0
    Behavior on ensanche {
        enabled: Theme.animNormal > 0
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    // 1 en el cursor, 0 en el borde del alcance, con transición suave.
    function factorLupa(centro) {
        if (!root.cursorDentro || !root.lupaActiva)
            return 0
        const t = 1 - Math.min(1, Math.abs(centro - root.cursorX) / root.alcance)
        return t * t * (3 - 2 * t)
    }

    // Cuánto se aparta un botón del cursor. Cero justo debajo —ese no se mueve,
    // solo crece— y constante más allá del alcance, que es lo que hace que los
    // de los extremos acompañen el ensanchamiento en vez de quedarse pegados.
    function empujeLupa(centro) {
        if (!root.cursorDentro || !root.lupaActiva)
            return 0
        const d = centro - root.cursorX
        const u = Math.min(1, Math.abs(d) / root.alcance)
        return Math.sign(d) * (Settings.dockMagnify - 1) * root.cajaBoton
               * root.lupaFactorEmpuje * (u * u * (3 - 2 * u))
    }

    // El alto de la PASTILLA: el botón más el relleno de arriba y abajo. Es la
    // única medida que las dos formas comparten tal cual, y la que sigue
    // marcando la zona exclusiva y el sitio del fondo.
    readonly property int altoDock: Theme.dp(Settings.dockIconSize)
                                    + Theme.dp(16) + root.relleno * 2

    // Tope del 90 %: un dock con treinta apps abiertas no puede salirse de la
    // pantalla, y a partir de ahí la fila se desplaza con la rueda.
    readonly property real anchoMax: root.anchoPantalla * 0.9

    // El item mide MÁS que la pastilla: la pastilla abajo y el aire de la lupa
    // encima. Todo lo que quiera hablar de "dónde está el dock" tiene que sumar
    // 'aireLupa' a la 'y' de este item (ver DockWindow.topePastilla).
    implicitHeight: root.altoDock + root.aireLupa
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

    // El fondo ocupa solo la parte de abajo: el aire de la lupa es transparente
    // y está ahí para que quepan los iconos ampliados, no para agrandar la
    // pastilla. Sombra y luz de canto las trae DockSurface.
    DockSurface {
        id: fondo
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.altoDock

        color: Theme.withAlpha(Theme.bg, Settings.dockOpacity)
        // Filete de 'overlay' y no el de los globos: esta superficie es
        // translúcida sobre el fondo de escritorio, y sin él, sobre un fondo
        // oscuro, el dock no tiene borde y parece un recorte.
        border.color: Theme.withAlpha(Theme.overlay, 0.35)

        radius: root.radio
        radioBL: root.esHotseat ? 0 : root.radio
        radioBR: root.esHotseat ? 0 : root.radio

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
        // Ocupa TAMBIÉN el aire de la lupa, no solo la pastilla, y de ahí salen
        // las dos mitades del arreglo: el recorte cae por encima de los iconos
        // ampliados en vez de por su cintura, y el hover sigue vivo cuando el
        // cursor sube hacia el icono que acaba de crecer.
        //
        // Solo se recorta cuando hace falta: con la fila desplazable, para que
        // no se pinte fuera del carril.
        clip: carril.contentWidth > carril.width + 0.5
        contentWidth: fila.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds

        // El hover va aquí y no en 'fila' justo por lo de arriba: en 'fila',
        // que mide solo la pastilla, subir el cursor al icono ampliado contaba
        // como salir del dock y la ola se caía sola.
        //
        // La x se corrige con fila.x porque los centros de los botones están en
        // coordenadas de 'fila', que va centrada dentro del carril.
        HoverHandler {
            id: raton
            onPointChanged: root.cursorX = raton.point.position.x - fila.x
            onHoveredChanged: root.cursorDentro = raton.hovered
        }

        Row {
            id: fila
            height: root.altoDock
            // Pegada abajo: el aire de la lupa queda por encima.
            y: root.aireLupa
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
        //
        // Cubren solo el alto de la PASTILLA: extendidos al aire de la lupa
        // pintarían una banda de color flotando por encima del dock, sobre el
        // fondo de escritorio.
        component Velo: Rectangle {
            width: Theme.dp(24)
            y: root.aireLupa
            height: root.altoDock
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
