import QtQuick
import qs.Config
import qs.Services

// Vigila la grabación de pantalla y se lo cuenta a la isla.
//
// Con la isla encendida, Panels/RecordingPill.qml no se construye (ver
// shell.qml) y el aviso de "se está grabando" lo da ella. Esto es el enganche.
//
// No basta con isRecording:
//
//   · showRecordingPill es un ajuste que YA EXISTE y dice "no quiero ver el
//     aviso de grabación". Habría sido muy fácil ignorarlo aquí y dejar a quien
//     lo apagó con un punto rojo que no puede quitar de ninguna manera.
//
//   · pillSuppressed lo enciende el propio servicio durante ocho segundos
//     cuando haces una captura SIN cortar el vídeo, para no salir en la foto.
//     La isla está en la misma pantalla y le pasa lo mismo, así que se esconde
//     con él. Si no, la captura sale con el punto rojo dentro.
QtObject {
    id: root

    readonly property bool visible: Settings.islandEnabled
                                    && ScreenCapture.isRecording
                                    && ScreenCapture.showRecordingPill
                                    && !ScreenCapture.pillSuppressed

    // Las cuatro condiciones se juntan en UNA propiedad atada, y de ahí sale un
    // solo sitio que escribe en la isla. Encadenar un Connections por cada una
    // habrían sido cuatro sitios donde olvidarse de la cuarta.
    //
    // El onCompleted no es adorno: un handler solo avisa de los CAMBIOS, y si
    // el shell se recarga con la grabación ya en marcha no habría ninguno.
    onVisibleChanged: IslandState.recordingActive = root.visible
    Component.onCompleted: IslandState.recordingActive = root.visible
}
