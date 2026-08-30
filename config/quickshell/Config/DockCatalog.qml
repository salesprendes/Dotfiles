pragma Singleton

import QtQuick
import Quickshell

// Catálogo del dock: solo funciones puras sobre arrays. Entra un array, sale un
// array; ninguna lee estado global ni toca nada vivo.
//
// La partición con Services/Dock.qml sigue una pregunta: cuál de las dos mitades
// puede equivocarse sin que se vea. Es esta. Una app fijada que además está
// abierta saliendo dos veces, un orden que se pierde al cerrar una ventana, un
// settings.json editado a mano con basura dentro: nada de eso da error, solo un
// dock ligeramente mal que se tarda semanas en notar. Lo vivo —toplevels de
// Wayland, iconos, Hyprland— vive en Services/Dock.qml, que necesita sesión.
//
// Está en Config y no en Services porque Config no importa qs.Services, que es
// la regla que mantiene cortado el ciclo de importaciones, y Config/Settings.qml
// necesita sanitize() para limpiar 'dockPinned' al cargar el archivo.
Singleton {
    id: cat

    // Tope de apps fijadas: sin él, un settings.json con diez mil entradas
    // construye diez mil delegates al arrancar.
    readonly property int maxPinned: 32

    // Fijar guarda el id de un .desktop, pero una ventana de Wayland solo trae
    // su appId, con mayúsculas o sin ellas según la app. Sin plegar los dos a la
    // misma clave, una app fijada y su ventana son dos iconos en el dock.
    //
    // Quien traduce appId → entrada .desktop es Services/Dock.qml; esto es solo
    // el último plegado, y vive aquí porque tiene que ser idéntico a los dos
    // lados y comprobable sin sesión gráfica.
    function normalizeId(bruto) {
        if (typeof bruto !== "string")
            return ""
        return bruto.trim().toLowerCase().replace(/\.desktop$/, "")
    }

    // settings.json es del usuario y se puede editar a mano: lo que no sea una
    // cadena aprovechable se descarta en silencio y se conserva el resto, para
    // que un id corrupto no se lleve la lista entera.
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

    // Todas devuelven un array nuevo en vez de mutar el recibido: Settings
    // guarda la lista en una 'property var', y mutar el array in situ no emite
    // el cambio, así que ni el dock se entera ni se guarda nada en disco.

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

    // 'hasta' se interpreta sobre la lista ya sin el elemento movido, que es lo
    // que hace que arrastrar un icono caiga donde se ve el hueco.
    function move(fijadas, desde, hasta) {
        const next = cat.sanitize(fijadas)
        if (desde < 0 || desde >= next.length || hasta < 0 || hasta >= next.length)
            return next
        next.splice(hasta, 0, next.splice(desde, 1)[0])
        return next
    }

    // abiertas: [{ id, ventanas: [obj], activa: bool }]
    // devuelve: [{ id, fijada: bool, ventanas: [obj], activa: bool }]
    //
    // Las fijadas van primero en su orden, que es el que el usuario ha elegido
    // arrastrando y no puede cambiar solo porque abra una app; detrás, las
    // abiertas que no estén ya fijadas.
    //
    // Una fijada desinstalada no se descarta —quitarla sería perderle un ajuste
    // sin avisar— y se queda como ranura sin ventanas, con el icono de respaldo.
    function merge(fijadas, abiertas, verAbiertas) {
        const limpias = cat.sanitize(fijadas)
        const lista = Array.isArray(abiertas) ? abiertas : []

        // Índice id → abierta: buscar en línea por cada fijada son casi mil
        // comparaciones en un binding que se reevalúa con cada ventana que se
        // abre o se cierra.
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

    // Dónde va la rayita que separa fijadas de abiertas: justo tras las fijadas.
    // Devuelve -1 cuando no habría nada a un lado, para no dejarla suelta en la
    // punta del dock.
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
