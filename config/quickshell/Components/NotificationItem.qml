import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Config
import qs.Services

// Tarjeta de notificación. Se usa tanto en los popups como en el centro de
// notificaciones.
//
// Mapeo de roles Material a Theme: Surface→bg, SurfaceVariant→surface,
// OnSurface→fg, OnSurfaceVariant→fgDim, Outline→overlay, Primary→accent.
// Las medidas van en px lógicos pasadas por Theme.dp()/sp(), para que sigan
// respetando la escala de densidad y de fuente del shell.
//
// 'notif' = objeto Notification.
Rectangle {
    id: item
    property var notif
    property bool popupMode: false
    // Progreso del timeout (1 → 0). Lo mueve el popup; el centro no lo usa.
    property real progress: 0
    property bool showProgress: false
    // Modo compacto: solo título, sin el cuerpo del mensaje. Sirve para que
    // una tanda de avisos ocupe una franja fina en vez de media pantalla.
    // No afecta al centro de notificaciones, donde sí quieres leerlo entero.
    property bool compact: false
    // Modo DENSO: la misma tarjeta, apretada. Esta está medida para el popup,
    // que es ancho; la hoja de la isla mide 360 dp y ahí dentro un título a 16
    // en negrita junto a un icono de 38 se comen la fila entera — cada aviso
    // quedaba como una caja enorme que solo dice el nombre de la app.
    //
    // Se hace con una propiedad y no con un archivo aparte a propósito: el
    // aviso tiene que verse IGUAL en los dos sitios (misma anatomía, mismo
    // orden, mismos gestos), solo que más apretado. Dos archivos habrían sido
    // dos diseños que se separan al primer cambio.
    property bool dense: false

    // Primer plano (todo menos el fondo de la tarjeta). El barrido de entrada
    // descubre el fondo YA OPACO y sólo el contenido funde con retardo y se
    // contra-desplaza; por eso opacidad y desplazamiento van aquí y no en la
    // tarjeta entera.
    property real contentOpacity: 1
    property real contentOffsetX: 0

    readonly property bool closeHovered: closeButton.hovered

    readonly property string img: resolveImage()
    readonly property bool hasImagePayload: !!(notif && notif.image)
    readonly property string appName: NotifService.appNameFor(notif)
    readonly property string summary: notif && notif.summary ? notif.summary : ""
    readonly property string body: notif && notif.body ? notif.body : ""
    readonly property bool hasBody: body !== "" && !compact
    readonly property int actionCount: countActions()
    readonly property bool hasActions: actionCount > 0

    // Urgencia: tiñe la barra de progreso. Critical → rojo; Low → texto atenuado.
    readonly property int urgency: notif && notif.urgency !== undefined ? notif.urgency : 1
    readonly property color progressColor: urgency === 2 ? Theme.red
                                         : urgency === 0 ? Theme.withAlpha(Theme.fg, 0.9)
                                         : Theme.accent

    signal closeRequested()

    function countActions() {
        if (!notif || !notif.actions)
            return 0
        return notif.actions.length || 0
    }

    function actionAt(i) {
        if (!notif || !notif.actions || i < 0 || i >= actionCount)
            return null
        return notif.actions[i]
    }

    function resolveImage() {
        const im = notif && notif.image ? notif.image : ""
        if (im !== "") return im
        const ic = notif && notif.appIcon ? notif.appIcon : ""
        return ic !== "" ? Quickshell.iconPath(ic, true) : ""
    }

    function dismiss() {
        if (popupMode) {
            closeRequested()
        } else if (notif) {
            notif.dismiss()
        }
    }

    // Acción "default": la tarjeta entera es su area de clic.
    function defaultAction() {
        for (let i = 0; i < actionCount; i++) {
            const a = actionAt(i)
            if (a && a.identifier === "default")
                return a
        }
        return null
    }
    readonly property bool hasDefaultAction: defaultAction() !== null

    // --- geometria (px logicos) ---
    readonly property int pad: Theme.dp(dense ? 10 : 12)          // kCardInnerPad
    readonly property int iconSize: Theme.dp(dense ? 30 : (hasActions ? 45 : 38))
    readonly property int iconGap: Theme.dp(dense ? 10 : 8)       // kIconTextGap
    readonly property int closeSize: Theme.dp(dense ? 18 : 20)
    readonly property int progressH: Theme.dp(3)

    // Anchos de texto CALCULADOS a partir del ancho de tarjeta, en vez de
    // dejarlos en manos de Layout.fillWidth. No es cosmética: con fillWidth,
    // en la primera pasada de layout los anchos aún valen 0, el título
    // envuelve a 2 líneas y la tarjeta mide ~22 px de más. El ListView de
    // los popups mide JUSTO en ese instante y deja congelada la posición de
    // las tarjetas de abajo, con lo que la primera quedaba separada del
    // resto. Con el ancho derivado del de la tarjeta (que se conoce desde
    // el primer frame) la altura es correcta a la primera.
    readonly property int textColWidth: Math.max(1, width - pad * 2 - iconSize - iconGap)
    readonly property int titleWidth: Math.max(1, textColWidth - closeSize - Theme.dp(8))

    implicitHeight: layout.implicitHeight

    radius: Theme.dp(dense ? 10 : 12)                 // radiusXl
    // La tarjeta se pinta con bg a 0.97 (no con surface): es el mismo tono
    // del fondo del shell, apenas translucido. Flotando sobre el escritorio
    // eso basta para que se lea como una tarjeta.
    //
    // Apretada NO, y es la misma razón al revés: ahí va DENTRO de la hoja de
    // la isla, que ya es una superficie oscura. Una tarjeta del tono del fondo
    // sobre un fondo oscuro no se ve como una tarjeta, se ve como un recuadro
    // dibujado a lápiz. Sube un peldaño de la escalera de contenedores de M3,
    // que es exactamente para lo que existe.
    color: item.dense ? Theme.surfaceContainer : Theme.withAlpha(Theme.bg, 0.97)
    border.width: Theme.hairline
    border.color: item.dense ? Theme.outlineVariant : Theme.overlay
    clip: true
    antialiasing: true

    // Clic izquierdo en la tarjeta: invoca la accion "default" y cierra.
    // Clic derecho: descarta. (Va detras del contenido: los botones de accion y
    // el de cerrar quedan por encima y se lo comen primero.)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: item.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                item.dismiss()
                return
            }
            const a = item.defaultAction()
            if (a)
                a.invoke()
            item.dismiss()
        }
    }

    Item {
        id: fg
        anchors.fill: parent
        opacity: item.contentOpacity
        transform: Translate { x: item.contentOffsetX }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // Barra de timeout: pegada al borde superior, por encima del contenido.
        // El relleno es una pastilla CENTRADA que se encoge hacia el medio
        // desde ambos extremos, no un vaciado lateral.
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: item.pad
            Layout.rightMargin: item.pad
            implicitHeight: item.progressH
            visible: item.showProgress

            Rectangle {
                width: Math.max(0, parent.width * item.progress)
                height: parent.height
                x: (parent.width - width) / 2
                radius: height / 2
                color: item.progressColor
                antialiasing: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: item.pad
            spacing: item.iconGap

            // Icono / imagen de la notificación.
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: item.iconSize
                implicitHeight: item.iconSize
                radius: Math.min(height / 2, Math.round(item.iconSize / 6))
                color: item.img !== "" ? "transparent"
                                       : Theme.withAlpha(Theme.surface, 1.0)
                clip: true

                Image {
                    anchors.fill: parent
                    visible: item.img !== ""
                    source: item.img
                    sourceSize: Qt.size(item.iconSize * 2, item.iconSize * 2)
                    // Recorta a Cover: la imagen llena el hueco sin bandas.
                    fillMode: item.hasImagePayload ? Image.PreserveAspectCrop
                                                   : Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }

                // Sin icono: campana, como fallback.
                ThemedText {
                    anchors.centerIn: parent
                    visible: item.img === ""
                    text: "󰂚"
                    color: Theme.fgDim
                    font.pixelSize: Theme.sp(item.dense ? 16 : (item.hasActions ? 24 : 20))
                }
            }

            ColumnLayout {
                Layout.preferredWidth: item.textColWidth
                Layout.alignment: Qt.AlignTop
                spacing: Theme.dp(2)

                // Antetítulo (solo denso): quién avisa y cuándo, en pequeño y
                // ARRIBA. En la tarjeta ancha esto va en el pie, a la derecha;
                // apretada, ese pie quedaba como una palabra suelta colgando
                // en la esquina de una caja casi vacía. Puesto delante del
                // título hace de encabezado y la fila se lee de un vistazo:
                // quién, qué, y qué dice.
                ThemedText {
                    Layout.preferredWidth: item.titleWidth
                    visible: item.dense && text !== ""
                    text: {
                        const cuando = NotifService.timeText(item.notif)
                        if (item.appName === "")
                            return cuando
                        return cuando === "" ? item.appName
                                             : item.appName + " · " + cuando
                    }
                    color: Theme.fgMuted
                    font.pixelSize: Theme.sp(11)          // fontSizeMini
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                }

                // Título. Reserva a su derecha el hueco del botón de cerrar.
                ThemedText {
                    Layout.preferredWidth: item.titleWidth
                    text: item.summary
                    color: Theme.fg
                    font.pixelSize: Theme.sp(item.dense ? 13 : 16)   // fontSizeTitle
                    // Apretada baja a Medium: en negrita, a 13 y sobre un
                    // antetítulo gris, el título gritaba dos veces.
                    font.weight: item.dense ? Font.Medium : Font.Bold
                    wrapMode: Text.WordWrap
                    maximumLineCount: item.dense ? 1 : 2   // kMaxSummaryLines
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                ThemedText {
                    Layout.preferredWidth: item.textColWidth
                    visible: item.hasBody
                    text: item.body
                    color: Theme.fgDim
                    font.pixelSize: Theme.sp(item.dense ? 12 : 14)   // fontSizeBody
                    wrapMode: Text.WordWrap
                    maximumLineCount: item.dense ? 2 : 3   // kToastMaxBodyLines
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                // Acciones. Flow: se reparten en varias filas si no caben,
                // con hueco de 4.
                Flow {
                    Layout.preferredWidth: item.textColWidth
                    Layout.topMargin: Theme.dp(8)          // kActionRowGap
                    visible: item.hasActions
                    spacing: Theme.dp(4)                   // kActionGap

                    Repeater {
                        model: item.actionCount
                        delegate: Rectangle {
                            readonly property var action: item.actionAt(index)
                            // La accion "default" es la tarjeta entera, no un boton.
                            visible: action && action.identifier !== "default"
                            width: visible ? Math.min(Theme.dp(180), aTxt.implicitWidth + Theme.dp(16) * 2) : 0
                            height: visible ? Theme.dp(32) : 0   // controlHeightSm
                            radius: Theme.dp(6)                  // radiusMd
                            color: aMa.containsMouse ? Theme.surfaceHi : Theme.surface
                            border.width: aMa.containsMouse ? 0 : Theme.hairline
                            border.color: Theme.overlay
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.enterEasing } }

                            ThemedText {
                                id: aTxt
                                anchors.centerIn: parent
                                width: Math.min(parent.width - Theme.dp(16), implicitWidth)
                                text: parent.action && parent.action.text ? parent.action.text : ""
                                color: Theme.fg
                                font.pixelSize: Theme.sp(13)     // fontSizeCaption
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                            MouseArea {
                                id: aMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (parent.action)
                                        parent.action.invoke()
                                    item.dismiss()
                                }
                            }
                        }
                    }
                }

                // Pie: nombre de la app, alineado a la derecha. El toast no
                // lleva marca de tiempo (sólo la lista del historial).
                ThemedText {
                    Layout.preferredWidth: item.textColWidth
                    Layout.topMargin: Theme.dp(4)
                    visible: !item.dense
                    horizontalAlignment: Text.AlignRight
                    text: item.appName
                    color: Theme.fgDim
                    font.pixelSize: Theme.sp(11)          // fontSizeMini
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    // Botón de cerrar: fantasma, esquina superior derecha, posición absoluta.
    Rectangle {
        id: closeButton
        property bool dismissing: false
        property bool hovered: closeMa.containsMouse && !dismissing

        width: item.closeSize
        height: item.closeSize
        x: item.width - item.pad - width
        y: item.pad
        radius: Theme.dp(6)
        color: closeButton.hovered ? Theme.surfaceHi
                                   : Theme.withAlpha(Theme.surfaceHi, 0)
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.enterEasing } }

        ThemedText {
            anchors.centerIn: parent
            text: "󰅖"
            color: Theme.fg
            font.pixelSize: Theme.sp(12)
            opacity: closeButton.hovered ? 1.0 : 0.55
            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Theme.enterEasing } }
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { closeButton.dismissing = true; item.dismiss() }
        }
    }

    }   // fg
}
