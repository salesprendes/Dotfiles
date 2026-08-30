pragma Singleton

import QtQuick
import Quickshell

// Catálogo del dock: SOLO funciones puras sobre arrays. Entra un array, sale
// un array; ninguna lee estado global ni toca nada vivo.
//
// ── POR QUÉ ESTO EXISTE SEPARADO DE Services/Dock.qml ───────────────────────
// La pregunta que decide la partición es cuál de las dos mitades se puede
// equivocar SIN QUE SE VEA. La respuesta es esta: fusionar la lista de apps
// fijadas con la de apps abiertas. Una fijada que además está abierta saliendo
// dos veces, un orden que se pierde al cerrar una ventana, un settings.json
// editado a mano con basura dentro — nada de eso da un error, solo un dock
// ligeramente mal que se tarda semanas en notar.
//
// Aquí no hace falta ni pantalla ni compositor para probarlo, así que
// tests/logica.qml lo cubre entero. Lo vivo —toplevels de Wayland, iconos,
// Hyprland— vive en Services/Dock.qml, que sí necesita sesión gráfica.
//
// Es el mismo reparto que BarCatalog hace para los tres carriles de la barra.
//
// ── Y POR QUÉ ESTÁ EN Config/ Y NO EN Services/ ─────────────────────────────
// Config NO IMPORTA qs.Services: es la regla que mantiene cortado el ciclo de
// importaciones (ver la cabecera de Config/Globals.qml). Config/Settings.qml
// necesita sanitize() para limpiar 'dockPinned' al cargar el archivo, así que
// el catálogo tiene que estar de este lado. De ahí que aquí no se mencione ni
// a Services/Dock ni a NotifService.
Singleton {
    id: cat

    // Tope de apps fijadas. No es una cifra mágica de adorno: sin tope, un
    // settings.json con diez mil entradas construye diez mil delegates al
    // arrancar el shell.
    readonly property int maxPinned: 32

    // ── La clave de una app ──────────────────────────────────────────────────
    // LA función de este archivo. Fijar guarda el id de un .desktop
    // ("firefox.desktop"), pero una ventana de Wayland solo trae su appId
    // ("Firefox", "firefox", según la app). Sin llevar ambos a la misma clave,
    // un Firefox fijado y una ventana de Firefox son DOS iconos en el dock.
    //
    // Quien traduce appId → entrada .desktop es Services/Dock.qml con
    // heuristicLookup; esto es solo el último plegado, y va aquí porque tiene
    // que ser idéntico a los dos lados y probable sin sesión gráfica.
    function normalizeId(bruto) {
        if (typeof bruto !== "string")
            return ""
        return bruto.trim().toLowerCase().replace(/\.desktop$/, "")
    }

    // ── Saneado de lo que venga de settings.json ─────────────────────────────
    // Es un archivo del usuario y se puede editar a mano. Lo que no sea una
    // cadena aprovechable se descarta en silencio y se conserva el resto: un
    // id corrupto no debe llevarse por delante la lista entera.
    function sanitize(fijadas) {
        if (!Array.isArray(fijadas))
            return []
        const out = []
        const vistas = {}
        for (const bruto of fijadas) {
            const id = cat.normalizeId(bruto)
            if (id === "" || vistas[id])
                continue
            vistas[id] = true
            out.push(id)
            if (out.length >= cat.maxPinned)
                break
        }
        return out
    }

    // ── Edición de la lista ──────────────────────────────────────────────────
    // Todas devuelven un array NUEVO en vez de mutar el recibido, por lo mismo
    // que BarCatalog: Settings guarda la lista en una 'property var', y mutar
    // el array in situ no emite el cambio — ni el dock se enteraría ni se
    // guardaría nada en disco.

    function has(fijadas, id) {
        if (!Array.isArray(fijadas))
            return false
        return fijadas.indexOf(cat.normalizeId(id)) !== -1
    }

    function add(fijadas, id) {
        const next = cat.sanitize(fijadas)
        const clave = cat.normalizeId(id)
        if (clave === "" || next.indexOf(clave) !== -1
            || next.length >= cat.maxPinned)
            return next
        next.push(clave)
        return next
    }

    function remove(fijadas, id) {
        const clave = cat.normalizeId(id)
        return cat.sanitize(fijadas).filter(x => x !== clave)
    }

    // 'hasta' se interpreta sobre la lista YA sin el elemento movido, que es lo
    // que hace que arrastrar un icono dos puestos a la derecha caiga donde el
    // usuario ve el hueco.
    function move(fijadas, desde, hasta) {
        const next = cat.sanitize(fijadas)
        if (desde < 0 || desde >= next.length || hasta < 0 || hasta >= next.length)
            return next
        next.splice(hasta, 0, next.splice(desde, 1)[0])
        return next
    }

    // ── La fusión ────────────────────────────────────────────────────────────
    // abiertas: [{ id, ventanas: [obj], activa: bool }]
    // devuelve: [{ id, fijada: bool, ventanas: [obj], activa: bool }]
    //
    // Las fijadas van primero EN SU ORDEN (es el orden que el usuario ha
    // elegido arrastrando, y no puede reordenarse solo porque abra una app), y
    // detrás las abiertas que no estén ya fijadas.
    //
    // Una app fijada que se ha desinstalado NO se descarta: la puso el usuario
    // a propósito, y quitársela sola sería perderle un ajuste sin avisar. Se
    // queda como ranura sin ventanas, con el icono de respaldo.
    function merge(fijadas, abiertas, verAbiertas) {
        const limpias = cat.sanitize(fijadas)
        const lista = Array.isArray(abiertas) ? abiertas : []

        // Índice id → abierta. Con 32 fijadas y 30 ventanas, buscar en línea
        // por cada fijada son casi mil comparaciones en un binding que se
        // reevalúa CADA VEZ que se abre o se cierra una ventana.
        const porId = {}
        for (const a of lista) {
            const id = cat.normalizeId(a ? a.id : "")
            if (id !== "")
                porId[id] = a
        }

        const out = []
        for (const id of limpias) {
            const a = porId[id]
            out.push({
                id: id,
                fijada: true,
                ventanas: (a && Array.isArray(a.ventanas)) ? a.ventanas : [],
                activa: a ? (a.activa === true) : false
            })
        }
        if (!verAbiertas)
            return out

        for (const a of lista) {
            const id = cat.normalizeId(a ? a.id : "")
            if (id === "" || limpias.indexOf(id) !== -1)
                continue
            out.push({
                id: id,
                fijada: false,
                ventanas: Array.isArray(a.ventanas) ? a.ventanas : [],
                activa: a.activa === true
            })
        }
        return out
    }

    // Dónde va la rayita que separa las fijadas de las abiertas: justo tras las
    // fijadas. Devuelve -1 cuando no habría nada detrás (o nada delante), para
    // que no quede una rayita suelta en la punta del dock.
    function separatorIndex(ranuras) {
        if (!Array.isArray(ranuras))
            return -1
        let fijadas = 0
        for (const r of ranuras)
            if (r && r.fijada)
                fijadas++
        if (fijadas === 0 || fijadas >= ranuras.length)
            return -1
        return fijadas
    }
}
