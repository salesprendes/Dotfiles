pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config

// El lado vivo del dock: qué hay abierto ahora mismo, con qué icono se dibuja y
// qué pasa al pulsarlo.
//
// La lógica de listas —fusionar fijadas con abiertas, ordenar, sanear— vive en
// Config/DockCatalog.qml, que es puro y comprobable sin sesión gráfica. Esta es
// la mitad que no lo es, y por eso se ha dejado lo más delgada posible.
//
// Hablar con el compositor tampoco es asunto suyo: enfocar una ventana, traerla
// al escritorio actual o preguntar si un monitor tiene ventanas vive en
// Services/WindowManager.qml, que es quien conoce a Hyprland. Este archivo ya no
// lo importa. Lo de aquí es qué apps hay, con qué icono se dibujan y qué pasa al
// pulsarlas.
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
        // El contador se RESINCRONIZA con la ventana enfocada de verdad antes de
        // avanzar. Sin esto, cualquier cambio de foco que no venga del dock
        // —Alt+Tab, un clic en la ventana, la vista previa— dejaba el índice
        // apuntando a otro sitio, y el primer clic siguiente saltaba a una
        // ventana que no era la que tocaba.
        //
        // Y se resincroniza en vez de sustituirse por completo por la ventana
        // enfocada, que sería menos estado: Hyprland enfoca de forma asíncrona,
        // así que dos clics seguidos leerían el mismo 'activeToplevel' de antes
        // y volverían a enfocar la misma ventana. El contador es lo que hace que
        // pulsar rápido siga avanzando.
        const enfocada = vs.indexOf(ToplevelManager.activeToplevel)
        const prev = root._rotacion[ranura.id]
        const base = enfocada >= 0 ? enfocada
                   : (typeof prev === "number" ? prev : -1)
        const i = (base + 1) % vs.length
        const copia = Object.assign({}, root._rotacion)
        copia[ranura.id] = i
        root._rotacion = copia
        WindowManager.enfocar(vs[i])
    }

    // Apps a las que se les acaba de dar la orden de arrancar, con el número de
    // ventanas que tenían al pulsar. Es lo que hace botar su icono mientras no
    // aparece nada.
    //
    // Vive AQUÍ y no en el botón, y esa es la parte importante: 'ranuras' se
    // reconstruye entera en cada cambio y el Repeater del dock, al tener un
    // array por modelo, destruye y rehace TODOS los delegates cuando el
    // contenido cambia — comprobado con Qt 6.11. Un rebote guardado en el
    // delegate se perdía en cuanto cualquier otra app abría una ventana, y el
    // 'abierta' que debía pararlo no llegaba a dispararse nunca porque el objeto
    // que lo escuchaba ya no existía.
    //
    // Se guarda la CUENTA y no un simple "estaba cerrada": el clic central pide
    // otra ventana de una app que ya tiene una, y ahí "¿tiene ventanas?" ya era
    // cierto antes de pulsar. Comparando cuentas, la primera ventana y la
    // enésima se detectan igual.
    property var _arrancando: ({})

    function estaArrancando(id) {
        return id !== "" && root._arrancando[id] !== undefined
    }

    function _ventanasDe(id) {
        for (const r of root.abiertas)
            if (r && r.id === id)
                return (r.ventanas || []).length
        return 0
    }

    function lanzarNueva(id) {
        const e = root.entradaDe(id)
        if (!e || !e.execute)
            return
        const copia = Object.assign({}, root._arrancando)
        copia[id] = root._ventanasDe(id)
        root._arrancando = copia
        e.execute()
        rendicion.restart()
    }

    // La app ha llegado: en cuanto tiene MÁS ventanas que al pulsar, deja de
    // estar arrancando. Se mira aquí y no con un temporizador porque el hueco
    // que hay que rellenar es exactamente ese, y dura lo que dure la app.
    onAbiertasChanged: {
        let copia = null
        for (const id in root._arrancando) {
            if (root._ventanasDe(id) > root._arrancando[id]) {
                if (!copia)
                    copia = Object.assign({}, root._arrancando)
                delete copia[id]
            }
        }
        if (copia)
            root._arrancando = copia
    }

    // Plan B para una app que no llega a abrir nunca —falta una dependencia, el
    // .desktop miente, la app arranca en bandeja— para no dejar un icono botando
    // solo hasta el fin de la sesión. Diez segundos es de sobra para lo más
    // lento que arranca en este equipo y poco para quedarse mirando.
    Timer {
        id: rendicion
        interval: 10000
        onTriggered: root._arrancando = ({})
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
