pragma Singleton
// Textos del greeter. Castellano por defecto; inglés si el sistema no está en
// castellano. Autocontenido: el greeter corre aislado en /etc/greetd, sin el
// I18n global.
import QtQuick
import Quickshell

Singleton {
    id: root

    // Código de idioma del sistema (2 letras). Se toma de LC_ALL/LC_MESSAGES/
    // LANG y, como respaldo, del locale por defecto de Qt. "es_ES.UTF-8" → "es".
    readonly property string lang: {
        const raw = (Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES")
                     || Quickshell.env("LANG") || Qt.locale().name || "").toString()
        return raw.slice(0, 2).toLowerCase()
    }
    // Solo castellano (no catalán/gallego/otros): estrictamente "es".
    readonly property bool spanish: lang === "es"

    // Devuelve el texto en el idioma activo: castellano o, si no, inglés.
    function tr(es, en) { return spanish ? es : en }

    // La fecha del reloj, en el idioma que toque. Estaba en Theme clavada a
    // es_ES; aquí al menos sigue al idioma que hemos detectado.
    readonly property var locale: Qt.locale(spanish ? "es_ES" : "en_US")
    function longDate(date) {
        return date.toLocaleDateString(locale, spanish ? "dddd, d 'de' MMMM"
                                                       : "dddd, MMMM d")
    }
}
