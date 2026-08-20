import QtQuick
import qs.Config

// Text con la tipografía del tema ya puesta. Existe porque esas dos líneas se
// repetían en casi todos los bloques de texto del shell (355 de 401), y esa
// repetición no solo es ruido: es lo que permitía que un bloque se olvidara la
// familia y saliera con la fuente por defecto de Qt sin que nadie lo notara.
//
// Solo pone valores POR DEFECTO: cualquier propiedad se sobrescribe como en un
// Text normal, y los tamaños derivados (Theme.fontSize + 4, - 2…) siguen
// escribiéndose en el sitio de uso.
//
// El greeter NO lo usa: importa qs.Config, que allí no existe (ver
// GREETD_SHARED_QML en script.sh). Sus textos siguen siendo Text normales.
Text {
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
}
