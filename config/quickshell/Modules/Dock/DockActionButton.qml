import QtQuick
import qs.Components
import qs.Config

// Los botones del final del dock: lanzador y Spotlight.
//
// Van con el MISMO círculo y la misma caja que un icono de app, y eso no es
// pereza: si midieran distinto, la fila dejaría de leerse como una fila y
// pasaría a ser dos grupos con un salto en medio. Lo que los separa es el
// filete de DockSeparator, que es suficiente.
//
// Aquí el glifo se dibuja siempre en color de acento, así que no hace falta el
// MultiEffect de DockButton: un glifo de Nerd Font es texto, y el texto ya se
// pinta del color que le digas.
Item {
    id: root

    property string glifo: ""

    readonly property bool mono: Settings.dockIconStyle === "mono"
    readonly property int iconSize: Theme.dp(Settings.dockIconSize)
    readonly property int caja: root.iconSize + Theme.dp(16)

    // Las pone DockRow desde la posición del cursor sobre la fila entera.
    // 'empujeLupa' va como transform y NO como 'x': cambiar la x movería la
    // disposición del Row, que es justo de donde sale el centro de reposo con
    // el que se calcula esto — el bucle de vínculos que hay que evitar.
    property real escalaLupa: 1.0
    property real empujeLupa: 0
    transform: Translate {
        x: root.empujeLupa
        Behavior on x {
            enabled: Theme.animNormal > 0
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }
    }

    implicitWidth: root.caja
    implicitHeight: root.caja

    signal activada()

    // Estos dos botones también dicen cómo se llaman: media fila de iconos muda
    // frente a la otra media que se presenta sería peor que ninguna.
    property string nombre: ""
    signal hoverCambia(var boton, bool dentro)

    Item {
        id: lienzo
        anchors.fill: parent

        // La pulsación entra SIN animar y solo la vuelta se anima: la señal
        // que confirma tu gesto no puede tardar más que el gesto. Es la misma
        // asimetría que Components/RowHighlight usa para el hover.
        //
        // Aviso para quien venga a tocar esto: la escala NO era el problema del
        // "no se ve al pulsar". Se midió. Con OutCubic, un clic de 50 ms ya
        // recorre el 88 % del camino a 0,92 y a los 90 ms está al 100 % — la
        // curva va muy cargada al principio. Lo que no se veía era el COLOR del
        // disco (ver ahí abajo). Aquí la entrada instantánea se queda porque es
        // lo correcto, no porque arreglara nada.
        // La ampliación la calcula DockRow para toda la fila a la vez (ver la
        // nota de la ola allí): aquí solo se aplica. Crece desde el borde de
        // ABAJO, no desde el centro, para que el icono suba y asome por encima
        // de la píldora en vez de empujar también hacia el canto inferior.
        transformOrigin: Item.Bottom
        scale: zona.pressed ? 0.92 : root.escalaLupa
        Behavior on scale {
            enabled: Theme.animNormal > 0
            NumberAnimation {
                duration: zona.pressed ? 0 : Theme.animFast
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.centerIn: texto
            width: root.caja - Theme.dp(6)
            height: width
            radius: width / 2
            // En modo COLOR no hay disco de fondo... salvo al señalar o pulsar.
            // Sin esto, en color estos dos botones solo respondían con la
            // escala, que es casi nada: eran los que peor acusaban el clic de
            // todo el dock.
            visible: root.mono || zona.containsMouse || zona.pressed
            antialiasing: true
            color: zona.pressed ? Theme.withAlpha(Theme.accent, 0.52)
                 : zona.containsMouse ? Theme.withAlpha(Theme.accent, 0.26)
                                      : Theme.withAlpha(Theme.accent, 0.14)
            Behavior on color {
                enabled: Theme.animNormal > 0
                ColorAnimation { duration: zona.pressed ? 0 : Theme.animFast }
            }
        }

        ThemedText {
            id: texto
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(Theme.dp(3))
            text: root.glifo
            color: zona.containsMouse
                   ? Theme.accent : Theme.withAlpha(Theme.accent, 0.78)
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.iconSize * 0.72)
        }
    }

    Ripple { id: onda }

    MouseArea {
        id: zona
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (ev) => onda.press(ev.x, ev.y)
        onClicked: {
            root.hoverCambia(root, false)
            root.activada()
        }
        onEntered: root.hoverCambia(root, true)
        onExited: root.hoverCambia(root, false)
    }
}
