pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Config

// El lado vivo del dock: qué hay abierto ahora mismo, con qué icono se dibuja y
// qué pasa al pulsarlo.
//
// La lógica de listas —fusionar fijadas con abiertas, ordenar, sanear— vive en
// Config/DockCatalog.qml, que es puro y comprobable sin sesión gráfica. Esta es
// la mitad que no lo es, y por eso se ha dejado lo más delgada posible.
Singleton {
    id: root

    // Fijar guarda el id de un .desktop; una ventana de Wayland solo trae su
    // appId, que según la app es "firefox", "Firefox" o "org.mozilla.firefox".
    // Sin llevar ambos a la misma clave, una app fijada y su ventana abierta
    // salen como dos iconos distintos.
    //
    // heuristicLookup es el mismo emparejador que usa Bar/ActiveWindow.qml para
    // resolver el título de la ventana enfocada, así que el dock acierta
    // exactamente donde acierta la barra.
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

    // Se reagrupa entero en cada cambio en vez de mantener un índice
    // incremental: es O(ventanas) sobre una lista de decenas de elementos, y a
    // cambio no hay estado que pueda desincronizarse en silencio.
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

    // Monitores
    function enSuMonitor(nombre) {
        const solo = Settings.dockOnlyMonitors
        if (!Array.isArray(solo) || solo.length === 0)
            return true
        return solo.indexOf(nombre) !== -1
    }

    // ¿Tiene ventanas el espacio de trabajo activo de este monitor? Es lo que
    // decide el autoocultar inteligente, y que sea por monitor importa: una
    // ventana a pantalla completa en la principal no debe esconder el dock de
    // la secundaria, que está vacía.
    //
    // Sin Hyprland no se sabe en qué monitor está cada ventana, y se devuelve
    // false —"escritorio vacío"—, con lo que el modo inteligente se comporta
    // como "siempre visible": esconder un dock sin saber si estorba sería peor.
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

    // NotifService agrupa por el nombre que la app se pone a sí misma al enviar
    // el aviso, y el dock indexa por id de .desktop. No son la misma cosa ni hay
    // conversión general, así que se comparan plegados contra el nombre y el id
    // de la entrada: acierta con la mayoría y falla con apps que se anuncien con
    // un nombre sin parecido con su .desktop.
    //
    // El recuento por nombre plegado se hace una vez para toda la lista, y cada
    // icono hace dos búsquedas: plegar dentro de la consulta por icono son tres
    // objetos nuevos por aviso y por icono en cada cambio de la lista.
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
        // Sin coincidencia, cero: nunca un número adivinado sobre el icono
        // equivocado. Un globo que falta es una función ausente; uno mal puesto
        // es información falsa, y eso es peor.
        return 0
    }

    // Acciones

    // Rotación por app: pulsar repetidamente el icono de una app con varias
    // ventanas las recorre. El índice se guarda por clave y no por delegate,
    // para que sobreviva a que el dock reordene sus botones.
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

    // Trae una ventana, moviéndola al espacio de trabajo actual si estaba en
    // otro. En modo Lua la sintaxis clásica de dispatchers no vale.
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
    // enlaza ambos, así que se busca por la referencia y no por título o clase.
    function _hyprDe(toplevel) {
        for (const hl of (Hyprland.toplevels ? Hyprland.toplevels.values : []))
            if (hl && hl.wayland === toplevel)
                return hl
        return null
    }

    // Se avisa de que ARRANCA, no de que ha arrancado: es justo el hueco entre
    // pulsar y ver la ventana lo que el icono tiene que rellenar diciendo "voy".
    // Quien escuche decide cuándo parar; aquí no se sabe si la app tardará
    // medio segundo o diez.
    signal lanzada(string id)

    function lanzarNueva(id) {
        const e = root.entradaDe(id)
        if (e && e.execute) {
            e.execute()
            root.lanzada(id)
        }
    }

    function cerrarTodas(ranura) {
        for (const tl of (ranura ? (ranura.ventanas || []) : []))
            if (tl && tl.close)
                tl.close()
    }

    // Los dos sitios que editan la lista —arrastrar en el dock y el editor de
    // Ajustes— pasan por aquí, y esto pasa por DockCatalog. Es la única forma de
    // que no diverjan: dos sitios escribiendo el mismo array con su propia idea
    // de qué es válido acaban discrepando.
    function fijar(id)   { Settings.dockPinned = DockCatalog.add(Settings.dockPinned, id) }
    function soltar(id)  { Settings.dockPinned = DockCatalog.remove(Settings.dockPinned, id) }
    function estaFijada(id) { return DockCatalog.has(Settings.dockPinned, id) }
    function reordenar(desde, hasta) {
        Settings.dockPinned = DockCatalog.move(Settings.dockPinned, desde, hasta)
    }
}
