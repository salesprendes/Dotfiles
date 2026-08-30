import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.Components
import qs.Config
import qs.Services

// Hoja del reproductor: carátula, pista, barra de posición y transporte.
//
// POR QUÉ EXISTE ESTE ARCHIVO: la isla YA mandaba aquí. Con música sonando,
// pulsarla abre el destino "media" — pero el catálogo de hojas solo tenía
// "calendar" y "notifs", así que la búsqueda devolvía null, la ranura quedaba
// vacía y la isla se encogía a una píldora en blanco. El camino existía y no
// llevaba a ninguna parte.
ColumnLayout {
    id: root
    spacing: Theme.space12
    // Sin implicitWidth: un ColumnLayout se lo reescribe él solo en cada
    // pasada de medida, así que el que había puesto aquí a mano no valía
    // nada. El ancho de una hoja lo pone la ranura de Island.qml, que es
    // quien sabe cuánto mide la hoja.

    readonly property var player: Media.active
    readonly property bool playing: Media.playing

    // MPRIS no empuja la posición: 'position' solo se refresca cuando se pide.
    // Sin esto la barra se queda clavada donde estaba al abrir la hoja, que es
    // peor que no tenerla —parece que la reproducción se ha parado—. Solo corre
    // mientras la hoja está a la vista y algo suena.
    Timer {
        running: root.visible && root.playing && (root.player?.positionSupported ?? false)
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    function _mmss(segundos) {
        if (!isFinite(segundos) || segundos < 0)
            return "0:00"
        const s = Math.floor(segundos)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    // Cabecera: carátula + pista
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space12

        Rectangle {
            implicitWidth: Theme.dp(64)
            implicitHeight: Theme.dp(64)
            radius: Theme.shapeMd
            color: Theme.withAlpha(Theme.overlay, 0.5)
            clip: true

            // El glifo se queda DEBAJO de la imagen en vez de alternarse con
            // ella: así la carátula puede tardar en cargar (o no llegar nunca,
            // que con algunos reproductores pasa) sin dejar un hueco vacío.
            ThemedText {
                anchors.centerIn: parent
                text: "󰎈"
                color: Theme.fgMuted
                font.pixelSize: Theme.sp(26)
            }

            Image {
                anchors.fill: parent
                source: root.player?.trackArtUrl || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: status === Image.Ready
                // La carátula viene del reproductor y puede ser enorme (1000×1000
                // es corriente) para una caja de 64. Sin esto se guarda en
                // memoria a tamaño completo por cada cambio de canción.
                sourceSize.width: Theme.dp(64) * 2
                sourceSize.height: Theme.dp(64) * 2
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            ThemedText {
                Layout.fillWidth: true
                text: root.player?.trackTitle || I18n.tr("Untitled")
                color: Theme.fg
                font.pixelSize: Theme.sp(15)
                elide: Text.ElideRight
            }
            ThemedText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.player?.trackArtist || ""
                color: Theme.fgDim
                font.pixelSize: Theme.typeBodySmall
                elide: Text.ElideRight
            }
            ThemedText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.player?.trackAlbum || ""
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
                elide: Text.ElideRight
            }
        }
    }

    // Solo si el reproductor dice que sabe dónde está. Un navegador que informa
    // de longitud 0 dejaría una barra que no se mueve y no se puede arrastrar.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space2
        visible: (root.player?.lengthSupported ?? false)
                 && (root.player?.length ?? 0) > 0

        Slider {
            id: barra
            Layout.fillWidth: true
            enabled: root.player?.canSeek ?? false

            // El valor va atado al reproductor a secas. No hace falta soltarlo
            // durante el arrastre: Slider ya pinta el valor del dedo por su
            // cuenta (ver SliderDrag.shownValue), y escribir aquí
            // "dragging ? value : ..." sería un binding que se lee a sí mismo.
            value: Math.min(1, (root.player?.position ?? 0)
                               / Math.max(1, root.player?.length ?? 1))

            // Dónde caería el dedo si se soltara ahora. -1 = no hay nada
            // pendiente.
            property real pendiente: -1

            function _seek(v) {
                if (root.player?.canSeek)
                    root.player.position = v * (root.player.length || 0)
            }

            // Arrastrar emite 'moved' en CADA píxel, y cada uno sería una
            // llamada de D-Bus al reproductor pidiéndole que salte. Con el
            // ratón cruzando la barra son cientos, y los reproductores que las
            // atienden de verdad se atragantan. Se guarda la última y se salta
            // una sola vez al soltar. Teclado y rueda no arrastran, así que
            // esos van directos.
            onMoved: (v) => {
                if (barra.dragging)
                    barra.pendiente = v
                else
                    barra._seek(v)
            }
            onDraggingChanged: {
                if (dragging || barra.pendiente < 0)
                    return
                barra._seek(barra.pendiente)
                barra.pendiente = -1
            }
        }

        RowLayout {
            Layout.fillWidth: true
            ThemedText {
                // Mientras se arrastra, el número acompaña al dedo: leer el
                // tiempo viejo mientras se busca un punto concreto no sirve.
                text: root._mmss(barra.pendiente >= 0
                                 ? barra.pendiente * (root.player?.length ?? 0)
                                 : (root.player?.position ?? 0))
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
            }
            Item { Layout.fillWidth: true }
            ThemedText {
                text: root._mmss(root.player?.length ?? 0)
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
            }
        }
    }

    // Transporte
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        IconButton {
            icon: "󰒟"
            visible: root.player?.shuffleSupported ?? false
            diameter: Theme.controlS
            iconColor: (root.player?.shuffle ?? false) ? Theme.accent : Theme.fgMuted
            onClicked: root.player.shuffle = !root.player.shuffle
        }

        Item { Layout.fillWidth: true }

        IconButton {
            icon: "󰒮"
            enabled: root.player?.canGoPrevious ?? false
            opacity: enabled ? 1 : 0.4
            onClicked: root.player?.previous()
        }
        IconButton {
            icon: root.playing ? "󰏤" : "󰐊"
            diameter: Theme.controlL
            iconPixelSize: Theme.iconSize + 2
            baseColor: Theme.accent
            iconColor: Theme.bg
            hoverColor: Qt.lighter(Theme.accent, 1.12)
            hoverIconColor: Theme.bg
            enabled: root.player?.canTogglePlaying ?? false
            onClicked: root.player?.togglePlaying()
        }
        IconButton {
            icon: "󰒭"
            enabled: root.player?.canGoNext ?? false
            opacity: enabled ? 1 : 0.4
            onClicked: root.player?.next()
        }

        Item { Layout.fillWidth: true }

        // Ciclo de repetición: ninguna → lista → pista. El glifo dice en cuál
        // está, que es lo único que hace útil un botón de tres estados.
        IconButton {
            readonly property int estado: root.player?.loopState ?? MprisLoopState.None
            icon: estado === MprisLoopState.Track ? "󰑘" : "󰑖"
            visible: root.player?.loopSupported ?? false
            diameter: Theme.controlS
            iconColor: estado === MprisLoopState.None ? Theme.fgMuted : Theme.accent
            onClicked: {
                root.player.loopState = estado === MprisLoopState.None ? MprisLoopState.Playlist
                                      : estado === MprisLoopState.Playlist ? MprisLoopState.Track
                                      : MprisLoopState.None
            }
        }
    }
}
