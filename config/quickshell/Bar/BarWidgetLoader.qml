import QtQuick

// Instancia un widget de barra a partir de su id. Es el único sitio donde un id
// del catálogo se convierte en un componente de verdad.
//
// El mapa vive aquí y no en Config/BarCatalog.qml a propósito: el catálogo son
// datos que el editor de Ajustes lista sin instanciar nada, y un singleton que
// declarase estos Component arrastraría Hyprland, PipeWire, MPRIS y el resto de
// servicios solo por abrir una página de ajustes.
//
// Para añadir un widget hacen falta dos cosas: una entrada en BarCatalog.widgets,
// con su nombre, y un par id → Component aquí abajo.
//
// Es un Item con un Loader dentro, y no un Loader a secas, por un detalle de Qt:
// QQuickLoader escribe su implicitWidth e implicitHeight desde C++ cada vez que
// carga o descarga, y eso destruye cualquier binding declarado sobre ellas. Como
// la ranura tiene que medir cero cuando su widget no se muestra —si no deja un
// hueco en la fila—, el tamaño tiene que vivir en un item que Qt no vaya a pisar.
Item {
    id: root

    property string widgetId: ""
    // Monitor de esta barra. Solo lo necesita Workspaces (filtra por pantalla),
    // pero se pasa a la ranura entera para no tener que saber desde fuera quién
    // lo usa y quién no.
    property var barScreen: null

    // 'shown' es la condición PROPIA del widget (hay batería, suena algo, la
    // bandeja tiene iconos). No se lee 'visible': en QML 'visible' es la
    // visibilidad EFECTIVA e incluye la del padre, así que ocultar la ranura
    // leyendo item.visible haría que el hijo reportara false para siempre y la
    // ranura no podría volver a mostrarlo nunca — un enganche que se cierra
    // sobre sí mismo. Ver Components/Pill.qml.
    visible: loader.item ? loader.item.shown === true : false

    implicitWidth: root.visible && loader.item ? loader.item.implicitWidth : 0
    implicitHeight: root.visible && loader.item ? loader.item.implicitHeight : 0

    Loader {
        id: loader
        anchors.fill: parent
        // La barra la construye Variants una vez por monitor y el layout no
        // cambia de sitio en caliente, así que 'asynchronous' no compra nada y
        // en cambio deja la barra montándose a trozos delante del usuario.
        asynchronous: false
        sourceComponent: root._map[root.widgetId] ?? null
    }

    readonly property var _map: ({
        "launcher":      cLauncher,
        "workspaces":    cWorkspaces,
        "activeWindow":  cActiveWindow,
        "media":         cMedia,
        "weather":       cWeather,
        "clock":         cClock,
        "tray":          cTray,
        "sysmon":        cSysmon,
        "keyboard":      cKeyboard,
        "updates":       cUpdates,
        "connectivity":  cConnectivity,
        "nightlight":    cNightLight,
        "power":         cPower,
        "caffeine":      cCaffeine,
        "ai":            cAi,
        "battery":       cBattery,
        "clipboard":     cClipboard,
        "emoji":         cEmoji,
        "notifications": cNotifications,
        "spacer":        cSpacer
    })

    Component { id: cLauncher;      LauncherWidget {} }
    Component { id: cWorkspaces;    Workspaces { screen: root.barScreen } }
    Component { id: cActiveWindow;  ActiveWindow {} }
    Component { id: cMedia;         MediaWidget {} }
    Component { id: cWeather;       WeatherWidget {} }
    Component { id: cClock;         ClockWidget {} }
    Component { id: cTray;          Tray {} }
    Component { id: cSysmon;        SysMonWidget {} }
    Component { id: cKeyboard;      KeyboardWidget {} }
    Component { id: cUpdates;       UpdatesWidget {} }
    Component { id: cConnectivity;  ConnectivityAudioWidget {} }
    Component { id: cNightLight;    NightLightWidget {} }
    Component { id: cPower;         PowerWidget {} }
    Component { id: cCaffeine;      CaffeineWidget {} }
    Component { id: cAi;            AiWidget {} }
    Component { id: cBattery;       BatteryWidget {} }
    Component { id: cClipboard;     ClipboardWidget {} }
    Component { id: cEmoji;         EmojiWidget {} }
    Component { id: cNotifications; NotificationsWidget {} }
    Component { id: cSpacer;        SpacerWidget {} }
}
