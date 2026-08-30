pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Config

// El lado vivo del dock: qué hay abierto ahora mismo, con qué icono se dibuja,
// y qué pasa al pulsarlo.
//
// La lógica de listas —fusionar fijadas con abiertas, ordenar, sanear— NO está
// aquí: vive en Config/DockCatalog.qml, que es puro y se prueba entero en
// tests/logica.qml sin sesión gráfica. Este archivo es la mitad que no se
// puede probar así, y por eso se ha dejado lo más delgada posible.
Singleton {
    id: root

    // ── La clave de una app ──────────────────────────────────────────────────
    // El problema central del dock. Fijar guarda el id de un .desktop; una
    // ventana de Wayland solo trae su appId, que según la app es "firefox",
    // "Firefox", "org.mozilla.firefox" o cualquier otra cosa. Sin llevar ambos
    // a la MISMA clave, un Firefox fijado y su propia ventana abierta salen
    // como dos iconos distintos en el dock.
    //
    // heuristicLookup es el mismo emparejador que ya usa Bar/ActiveWindow.qml
    // para resolver el título de la ventana enfocada, así que el dock acierta
    // exactamente donde acierta la barra — ni un caso más ni uno menos.
    function claveDe(appId) {
        if (!appId || appId === "")
            return ""
        const e = DesktopEntries.heuristicLookup(appId)
        return DockCatalog.normalizeId(e ? e.id : appId)
    }

    function entradaDe(id) {
        if (!id || id === "")
            return null
        return DesktopEntries.heuristicLookup(id)
    }

    function nombreDe(id) {
        const e = root.entradaDe(id)
        if (e && e.name && e.name !== "")
            return e.name
        // Respaldo para una app sin .desktop: "org.kde.dolphin" → "Dolphin".
        const corto = String(id || "").split(".").pop().replace(/[-_]+/g, " ")
        return corto === "" ? "" : corto.charAt(0).toUpperCase() + corto.slice(1)
    }

    function iconoDe(id) {
        const e = root.entradaDe(id)
        const icono = (e && e.icon && e.icon !== "") ? e.icon : id
        return icono !== "" ? Quickshell.iconPath(icono, true) : ""
    }

    // ── Lo que está abierto ──────────────────────────────────────────────────
    // Se reagrupa entero en cada cambio en vez de mantener un índice
    // incremental. Es O(ventanas) sobre una lista que en la práctica tiene
    // decenas de elementos, y a cambio no hay estado que se pueda desincronizar
    // — que es justo el fallo que un índice incremental daría en silencio.
    readonly property var abiertas: {
        const porId = {}
        const orden = []
        const activo = ToplevelManager.activeToplevel
        const lista = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
        for (const tl of lista) {
            if (!tl)
                continue
            const id = root.claveDe(tl.appId)
            if (id === "")
                continue
            if (!porId[id]) {
                porId[id] = { id: id, ventanas: [], activa: false }
                orden.push(id)
            }
            porId[id].ventanas.push(tl)
            if (tl === activo)
                porId[id].activa = true
        }
        return orden.map(id => porId[id])
    }

    readonly property var ranuras: DockCatalog.merge(Settings.dockPinned,
                                                     root.abiertas,
                                                     Settings.dockShowRunning)

    // ── Monitores ────────────────────────────────────────────────────────────
    function enSuMonitor(nombre) {
        const solo = Settings.dockOnlyMonitors
        if (!Array.isArray(solo) || solo.length === 0)
            return true
        return solo.indexOf(nombre) !== -1
    }

    // ¿Tiene ventanas el espacio de trabajo activo DE ESTE MONITOR? Es lo que
    // decide el autoocultar inteligente, y que sea por monitor importa: con dos
    // pantallas, un navegador a pantalla completa en la principal no debe
    // esconder el dock de la secundaria, que está vacía.
    //
    // Sin Hyprland no hay forma de saber en qué monitor está cada ventana. Se
    // devuelve false, o sea "el escritorio está vacío", con lo que el modo
    // inteligente se comporta como "siempre visible". Es lo razonable cuando
    // falta el dato: esconder un dock que no se sabe si estorba sería peor.
    function hayVentanasEn(monitor) {
        if (!Settings.hyprlandAvailable)
            return false
        const mons = Hyprland.monitors ? Hyprland.monitors.values : []
        let wsId = -1
        for (const m of mons)
            if (m && m.name === monitor && m.activeWorkspace) {
                wsId = m.activeWorkspace.id
                break
            }
        if (wsId === -1)
            return false
        for (const tl of (Hyprland.toplevels ? Hyprland.toplevels.values : [])) {
            const ipc = tl ? tl.lastIpcObject : null
            if (!ipc || ipc.mapped === false || ipc.hidden === true)
                continue
            if (tl.workspace && tl.workspace.id === wsId)
                return true
        }
        return false
    }

    // ── Notificaciones por app ───────────────────────────────────────────────
    // NotifService agrupa por appName: EL NOMBRE QUE LA APP SE PONE A SÍ MISMA
    // al enviar el aviso. El dock indexa por id de .desktop. No son la misma
    // cosa y no hay conversión general entre ambas.
    //
    // Se comparan plegados (minúsculas, sin diacríticos) contra el nombre y el
    // id de la entrada. Acierta con Firefox, Signal o Thunderbird; falla con
    // apps que se anuncien con un nombre sin parecido con su .desktop.
    //
    // El recuento por nombre de app plegado, hecho UNA vez.
    //
    // Antes esto vivía dentro de avisosDe(), o sea que cada icono del dock
    // recorría la lista entera plegando el nombre de cada aviso. fold() hace un
    // toLowerCase, un normalize("NFD") y un replace con expresión regular: tres
    // objetos nuevos por aviso y por icono, cada vez que llega o se va una
    // notificación. Con veintiocho avisos y diez iconos eran 280 pliegues por
    // cambio, para responder diez preguntas.
    //
    // Ahora se pliega la lista una vez y cada icono hace dos búsquedas.
    readonly property var _avisosPorApp: {
        const cuenta = ({})
        if (!Settings.dockNotifBadges)
            return cuenta
        for (const notif of (NotifService.list ? NotifService.list.values : [])) {
            const app = SettingsFilter.fold(NotifService.appNameFor(notif))
            if (app !== "")
                cuenta[app] = (cuenta[app] || 0) + 1
        }
        return cuenta
    }

    function avisosDe(id) {
        if (!Settings.dockNotifBadges)
            return 0
        const e = root.entradaDe(id)
        if (!e)
            return 0
        const porNombre = SettingsFilter.fold(e.name || "")
        if (porNombre !== "" && root._avisosPorApp[porNombre] !== undefined)
            return root._avisosPorApp[porNombre]
        const porId = DockCatalog.normalizeId(e.id || "")
        if (porId !== "" && root._avisosPorApp[porId] !== undefined)
            return root._avisosPorApp[porId]
        // SIN COINCIDENCIA, CERO. Nunca un número adivinado sobre el icono
        // equivocado: un globo que falta es una función ausente, un globo mal
        // puesto es información falsa, y de las dos la segunda es peor.
        return 0
    }

    // ── Acciones ─────────────────────────────────────────────────────────────

    // Rotación por app: pulsar repetidamente el icono de una app con tres
    // ventanas las recorre en vez de traer siempre la misma. El índice se
    // guarda por clave (no por delegate) para que sobreviva a que el dock
    // reordene sus botones al abrirse o cerrarse otra app.
    property var _rotacion: ({})

    function activar(ranura) {
        if (!ranura)
            return
        const vs = ranura.ventanas || []
        if (vs.length === 0) {
            root.lanzarNueva(ranura.id)
            return
        }
        const prev = root._rotacion[ranura.id]
        const i = (typeof prev === "number" ? (prev + 1) : 0) % vs.length
        const copia = Object.assign({}, root._rotacion)
        copia[ranura.id] = i
        root._rotacion = copia
        root.enfocar(vs[i])
    }

    // Traer una ventana. Si está en otro espacio de trabajo se mueve al ACTUAL
    // y se enfoca, que es el mismo comportamiento que ya da la bandeja al
    // pulsar un icono (ver Bar/Tray.qml:openApplication) — y con la misma
    // trampa: en modo Lua la sintaxis clásica de dispatchers no vale.
    function enfocar(toplevel) {
        if (!toplevel)
            return
        if (!Settings.hyprlandAvailable) {
            // Sin Hyprland queda el camino del protocolo, que enfoca pero no
            // puede traer la ventana de otro escritorio.
            if (toplevel.activate)
                toplevel.activate()
            return
        }
        const hl = root._hyprDe(toplevel)
        const ws = Hyprland.focusedWorkspace
        if (!hl || !ws) {
            if (toplevel.activate)
                toplevel.activate()
            return
        }
        let addr = String(hl.address)
        if (addr.indexOf("0x") !== 0)
            addr = "0x" + addr
        if (hl.workspace && hl.workspace.id === ws.id) {
            if (Hyprland.usingLua)
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
            else
                Hyprland.dispatch("focuswindow address:" + addr)
            return
        }
        if (Hyprland.usingLua)
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws.id
                              + ', window = "address:' + addr + '" })')
        else
            Hyprland.dispatch("movetoworkspace " + ws.id + ",address:" + addr)
    }

    // El toplevel de Hyprland que corresponde a uno de Wayland. Quickshell ya
    // enlaza ambos: se busca por la referencia, no por título ni por clase.
    function _hyprDe(toplevel) {
        for (const hl of (Hyprland.toplevels ? Hyprland.toplevels.values : []))
            if (hl && hl.wayland === toplevel)
                return hl
        return null
    }

    function lanzarNueva(id) {
        const e = root.entradaDe(id)
        if (e && e.execute)
            e.execute()
    }

    function cerrarTodas(ranura) {
        for (const tl of (ranura ? (ranura.ventanas || []) : []))
            if (tl && tl.close)
                tl.close()
    }

    // ── Edición de las fijadas ───────────────────────────────────────────────
    // Los DOS sitios que editan la lista —arrastrar en el propio dock y el
    // editor de Ajustes— pasan por aquí, y esto pasa por DockCatalog. Es la
    // única forma de que no diverjan: dos sitios escribiendo el mismo array con
    // su propia idea de qué es válido acaban discrepando siempre.
    function fijar(id)   { Settings.dockPinned = DockCatalog.add(Settings.dockPinned, id) }
    function soltar(id)  { Settings.dockPinned = DockCatalog.remove(Settings.dockPinned, id) }
    function estaFijada(id) { return DockCatalog.has(Settings.dockPinned, id) }
    function reordenar(desde, hasta) {
        Settings.dockPinned = DockCatalog.move(Settings.dockPinned, desde, hasta)
    }
}
