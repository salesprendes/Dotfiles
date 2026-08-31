import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Components
import qs.Config
import qs.Services

// Un icono del dock: la app, si está abierta, cuántas ventanas tiene y cuántos
// avisos pendientes.
//
// No sabe en qué estilo está el dock, y es a propósito: lo único que cambia entre
// las dos formas es la geometría de la ventana y del fondo, así que preguntarlo
// aquí convertiría las dos formas en el doble de trabajo.
//
// La ola de la lupa, la zona sensible y la onda de pulsación las pone la base
// DockMagnifiable, que comparte con DockActionButton. Todo lo que se declara
// aquí dentro cae en el item que se escala.
//
// En modo mono cada icono va dentro de un círculo de acento y teñido de ese mismo
// color. El precio es real y conviene saberlo: se pierde el color de marca de cada
// app, así que con pocas fijadas queda coherente y con muchas hay que
// distinguirlas por la silueta. De ahí que sea un ajuste y no una decisión.
DockMagnifiable {
    id: root

    required property var ranura
    readonly property string appId: root.ranura ? root.ranura.id : ""
    readonly property var ventanas: root.ranura ? (root.ranura.ventanas || []) : []
    readonly property bool activa: root.ranura ? root.ranura.activa === true : false
    readonly property bool abierta: root.ventanas.length > 0

    readonly property bool mono: Settings.dockIconStyle === "mono"
    readonly property int iconSize: Theme.dp(Settings.dockIconSize)

    // La caja del botón es bastante mayor que su icono: es lo que deja sitio al
    // círculo de detrás y a la lupa sin que el icono roce al vecino.
    readonly property int caja: root.iconSize + Theme.dp(16)
    implicitWidth: root.caja
    implicitHeight: root.caja

    botones: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

    // Alto reservado abajo para el indicador. Se descuenta del icono en vez de
    // dibujarse encima: superpuesto, el indicador se pierde sobre iconos de
    // fondo claro.
    readonly property int indicadorAlto: Settings.dockRunningIndicator === "none"
                                         ? 0 : Theme.dp(6)

    signal pideMenu(var ranura, real x, real y)
    // El hover lo gestiona DockPopovers y no este botón: la vista previa tiene
    // histéresis (tarda en salir y tarda en irse) y al pasar de un icono al
    // vecino debe RECOLOCARSE, no cerrarse y volver a abrirse. Eso solo se
    // puede decidir desde quien ve los dos botones a la vez.
    signal hoverCambia(var ranura, var boton, bool dentro)

    // Pulsar el icono de una app cerrada no tiene respuesta visible hasta que
    // la ventana aparece, y eso pueden ser varios segundos: sin nada en medio
    // se duda de si el clic ha entrado y se vuelve a pulsar, que es como se
    // acaban abriendo dos copias. El brinco ocupa exactamente ese hueco.
    //
    // Quién está arrancando lo lleva el SERVICIO, no este botón, y esa es la
    // corrección de fondo: el modelo del dock se reconstruye entero en cada
    // cambio —basta que otra app abra una ventana— y un Repeater con modelo de
    // array destruye y rehace TODOS los delegates cuando el contenido cambia.
    // Un rebote guardado aquí se perdía en ese cambio, y el 'abierta' que se
    // suponía que lo paraba llegaba a un objeto que ya no existía.
    //
    // Con el estado en el servicio, el brinco sobrevive a que el botón se
    // rehaga y para exactamente cuando esa app gana una ventana más de las que
    // tenía al pulsar — que es lo que hace que funcione igual para la primera
    // ventana que para el clic central, que pide otra de una app ya abierta.
    readonly property bool arrancando: Dock.estaArrancando(root.appId)

    SequentialAnimation {
        id: rebote
        // Sin tope propio: lo acota el servicio, que es quien sabe cuándo llegó
        // la ventana y quien se rinde si no llega nunca.
        loops: Animation.Infinite
        NumberAnimation {
            target: root; property: "brincoY"; to: -Theme.dp(10)
            duration: Theme.animNormal; easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root; property: "brincoY"; to: 0
            duration: Math.round(Theme.animNormal * 1.6); easing.type: Easing.OutBounce
        }
        PauseAnimation { duration: Theme.animNormal }
    }

    function pararRebote() {
        rebote.stop()
        root.brincoY = 0
    }

    onArrancandoChanged: {
        if (root.arrancando && Theme.animNormal > 0)
            rebote.restart()
        else
            root.pararRebote()
    }
    // Un delegate recién creado no recibe 'onArrancandoChanged' —el valor ya
    // viene puesto—, y es justo el caso que hay que cubrir: el botón se acaba
    // de rehacer con el brinco a medias.
    Component.onCompleted: if (root.arrancando && Theme.animNormal > 0) rebote.restart()

    onPulsada: (ev) => {
        // Pulsar retira el globo en el acto, sin esperar a que el dock se
        // esconda: has dejado de preguntar qué es este icono y has pasado a
        // usarlo. No vuelve hasta que salgas y entres otra vez.
        root.hoverCambia(root.ranura, root, false)
        if (ev.button === Qt.LeftButton) {
            Dock.activar(root.ranura)
        } else if (ev.button === Qt.MiddleButton) {
            // Ventana nueva, siempre. Es el gesto de "otra más" que ya
            // existe en GNOME y en Windows, y no colisiona con nada.
            Dock.lanzarNueva(root.appId)
        } else {
            const p = root.mapToItem(null, ev.x, ev.y)
            root.pideMenu(root.ranura, p.x, p.y)
        }
    }
    onEntrada: root.hoverCambia(root.ranura, root, true)
    onSalida: root.hoverCambia(root.ranura, root, false)

    // Solo en modo mono. Con los iconos a color, un círculo detrás de cada
    // uno los mete a todos en una caja y el dock pasa a ser una fila de
    // botones en vez de una fila de apps.
    Rectangle {
        id: disco
        anchors.centerIn: marco
        width: root.caja - Theme.dp(6)
        height: width
        radius: width / 2
        visible: root.mono
        antialiasing: true
        // AQUÍ estaba el "no se ve al pulsar", y es un problema de
        // CONTRASTE, no de tiempo. El salto de pulsado era de 0,26 a 0,34:
        // ocho centésimas de alfa. Y como ColorAnimation interpola LINEAL
        // —no como la curva de la escala, que va cargada al principio—, a
        // mitad de un clic corto solo habías recorrido la mitad: un cambio
        // real de 0,04. Medido.
        //
        // Ahora el pulsado se va a 0,52 y entra de golpe: 0,26 de salto
        // visible desde el hover, seis veces más. Lo que confirma un clic
        // tiene que despegarse del hover, no rozarlo.
        color: root.pulsando ? Theme.withAlpha(Theme.accent, 0.52)
             : root.senalado ? Theme.withAlpha(Theme.accent, 0.26)
                             : Theme.withAlpha(Theme.accent, 0.14)
        Behavior on color {
            enabled: Theme.animNormal > 0
            ColorAnimation { duration: root.pulsando ? 0 : Theme.animFast }
        }
    }

    // Marco del icono. Existe como Item aparte para que el disco, el globo y
    // el indicador tengan a qué anclarse sin depender del propio Image, que
    // en modo mono está oculto (lo pinta el MultiEffect).
    Item {
        id: marco
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round((parent.height - root.indicadorAlto
                                       - root.iconSize) / 2)
        width: root.iconSize
        height: root.iconSize

        Image {
            id: icono
            anchors.fill: parent
            source: Dock.iconoDe(root.appId)
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            fillMode: Image.PreserveAspectFit
            smooth: true
            // En mono NO se pinta: lo pinta el MultiEffect de abajo, que lo
            // usa como fuente. Dejarlo visible dibujaría el icono a color
            // debajo del teñido y asomaría un halo por los bordes.
            visible: !root.mono && status === Image.Ready
        }

        // Respaldo para una app fijada que se ha desinstalado: conserva su
        // ranura (ver DockCatalog.merge), así que necesita algo que enseñar.
        // Un hueco vacío parecería un fallo de pintado.
        Image {
            id: generico
            anchors.fill: parent
            visible: !root.mono && icono.status !== Image.Ready
            source: Quickshell.iconPath("application-x-executable", true)
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            fillMode: Image.PreserveAspectFit
        }

        MultiEffect {
            anchors.fill: parent
            visible: root.mono
            source: icono.status === Image.Ready ? icono : generico
            // colorization 1.0 lleva cada píxel al color indicado
            // CONSERVANDO su transparencia: la silueta del icono se
            // mantiene y el color se va. Es el ColorOverlay de Qt5Compat.
            colorization: 1.0
            colorizationColor: root.senalado || root.activa
                ? Theme.accent : Theme.withAlpha(Theme.accent, 0.78)
        }
    }

    // "auto": una rayita ancha cuando hay UNA ventana y
    // puntos cuando hay varias. Dice dos cosas con una sola forma —que está
    // abierta, y si tiene más de una— sin ocupar más sitio que cualquiera
    // de las dos por separado.
    readonly property string modo: {
        const m = Settings.dockRunningIndicator
        if (m !== "auto")
            return m
        return root.ventanas.length > 1 ? "dots" : "line"
    }

    readonly property color colorIndicador: root.activa
        ? Theme.accent : Theme.withAlpha(Theme.fg, 0.4)

    Loader {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.dp(3)
        active: root.abierta && root.modo !== "none"
        visible: active
        sourceComponent: root.modo === "count" ? cCuenta
                       : root.modo === "dots"  ? cPuntos
                                               : cRaya
    }

    Component {
        id: cRaya
        Rectangle {
            implicitWidth: Theme.dp(12)
            implicitHeight: Theme.dp(3)
            radius: height / 2
            color: root.colorIndicador
            antialiasing: true
        }
    }

    Component {
        id: cPuntos
        Row {
            spacing: Theme.dp(3)
            Repeater {
                // Tres es el tope a propósito: con cinco puntitos de 4 dp
                // ya no se cuenta de un vistazo, que es lo único que un
                // indicador tiene que conseguir.
                model: Math.min(root.ventanas.length, 3)
                delegate: Rectangle {
                    width: Theme.dp(4)
                    height: Theme.dp(3)
                    radius: height / 2
                    color: root.colorIndicador
                    antialiasing: true
                }
            }
        }
    }

    Component {
        id: cCuenta
        ThemedText {
            text: root.ventanas.length
            color: root.colorIndicador
            font.pixelSize: Theme.sp(9)
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    // Globo de avisos
    CountBadge {
        anchors.right: marco.right
        anchors.top: marco.top
        anchors.rightMargin: -Theme.dp(4)
        anchors.topMargin: -Theme.dp(4)
        count: Dock.avisosDe(root.appId)
        badgeColor: Theme.red
    }
}
