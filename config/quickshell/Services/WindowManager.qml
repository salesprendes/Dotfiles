pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Config

// Todo lo que este shell le pide al compositor sobre VENTANAS, en un solo sitio.
//
// Existe porque "traer una ventana al escritorio actual" estaba escrito tres
// veces —el dock, la bandeja y la ventana de Ajustes— y las tres no decían lo
// mismo. Con Hyprland en modo clásico, Ajustes hacía 'movetoworkspace' y
// además 'focuswindow'; el dock solo 'movetoworkspace'; la bandeja
// 'movetoworkspacesilent'. La normalización de la dirección estaba copiada
// cuatro veces y la bifurcación Lua/clásico, tres. Alguna de las tres estaba
// mal y no había forma de saber cuál sin comparar los tres ficheros.
//
// Y hay una razón concreta, no de estilo, para que esto sea un archivo: esa
// bifurcación YA se rompió una vez. Hyprland pasó a configuración en Lua, la
// sintaxis clásica de dispatchers dejó de valer y hubo que tocarlo en todos los
// sitios donde estaba. El día que vuelva a cambiar, ahora es un sitio.
//
// Lo que NO entra aquí: leer el estado del compositor para PINTARLO. Bar/
// Workspaces.qml sigue leyendo Hyprland.workspaces directamente, porque es un
// widget de escritorios virtuales y envolver esa lista tras una abstracción es
// un pasamanos que no compra nada. Aquí viven las ACCIONES y las consultas que
// alguien más repetía.
Singleton {
    id: root

    // Sin compositor, las acciones que necesitan moverse entre escritorios no
    // se pueden hacer; las que solo enfocan tienen el camino del protocolo de
    // Wayland. Cada función dice cuál toma.
    readonly property bool disponible: Settings.hyprlandAvailable

    readonly property var ventanas: Hyprland.toplevels ? Hyprland.toplevels.values : []

    // Hyprland devuelve la dirección unas veces con "0x" y otras sin él, y los
    // dispatchers la quieren siempre con él.
    function _dir(v) {
        const a = v ? String(v.address || "") : ""
        if (a === "")
            return ""
        return a.indexOf("0x") === 0 ? a : "0x" + a
    }

    // Acepta indistintamente un toplevel de Hyprland o uno de Wayland: los dos
    // llegan aquí desde sitios distintos —el dock tiene los de Wayland, la
    // bandeja los de Hyprland— y obligar a cada quien a convertirlo antes es
    // devolverle el problema al que llama. Se distinguen por 'address', que
    // solo tienen los de Hyprland.
    function _hypr(ventana) {
        if (!ventana)
            return null
        if (ventana.address !== undefined)
            return ventana
        for (const hl of root.ventanas)
            if (hl && hl.wayland === ventana)
                return hl
        return null
    }

    // Camino sin Hyprland: enfoca, pero no puede traer la ventana de otro
    // escritorio. Es mejor que no hacer nada, que es lo que hacían la bandeja y
    // Ajustes —ninguna de las dos comprobaba si había compositor, así que en
    // cualquier otro el clic se perdía en silencio—.
    function _activarProtocolo(ventana) {
        if (ventana && ventana.activate) {
            ventana.activate()
            return true
        }
        if (ventana && ventana.wayland && ventana.wayland.activate) {
            ventana.wayland.activate()
            return true
        }
        return false
    }

    // ¿Está esta ventana en el escritorio que se está mirando?
    function estaAqui(ventana) {
        const hl = root._hypr(ventana)
        const ws = Hyprland.focusedWorkspace
        return !!(hl && ws && hl.workspace && hl.workspace.id === ws.id)
    }

    // Enfoca la ventana, trayéndola al escritorio actual si estaba en otro.
    //
    // Las dos ramas garantizan el foco de forma EXPLÍCITA, y eso es la decisión
    // que había que tomar una vez: en Lua, 'window.move' ya enfoca a la ventana
    // movida (por eso la bandeja tiene que devolver el foco a mano, ver abajo);
    // en clásico se añade 'focuswindow' detrás, que es lo que hacía Ajustes y no
    // hacía el dock. Redundante en el peor caso, y en el peor caso el dock se
    // quedaba sin enfocar lo que acababa de traer.
    function enfocar(ventana) {
        if (!ventana)
            return false
        const hl = root._hypr(ventana)
        const ws = Hyprland.focusedWorkspace
        const addr = root._dir(hl)
        if (!root.disponible || !hl || !ws || addr === "")
            return root._activarProtocolo(ventana)

        if (hl.workspace && hl.workspace.id === ws.id) {
            Hyprland.dispatch(Hyprland.usingLua
                ? 'hl.dsp.focus({ window = "address:' + addr + '" })'
                : "focuswindow address:" + addr)
            return true
        }
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws.id
                              + ', window = "address:' + addr + '" })')
        } else {
            Hyprland.dispatch("movetoworkspace " + ws.id + ",address:" + addr)
            Hyprland.dispatch("focuswindow address:" + addr)
        }
        return true
    }

    // Trae la ventana al escritorio actual SIN robarle el foco a la que estabas
    // usando. Es lo que quiere la bandeja: pulsar un icono pone la ventana a la
    // vista, no interrumpe lo que estás escribiendo.
    //
    // En Lua no hay variante silenciosa documentada, así que se mueve y se
    // devuelve el foco a mano; en clásico existe 'movetoworkspacesilent'.
    //
    // Devuelve false si no se pudo: sin compositor no hay forma de mover nada
    // entre escritorios, y quien llama decide qué hacer entonces (la bandeja
    // lanza la app).
    function traerSinFoco(ventana) {
        if (!root.disponible)
            return false
        const hl = root._hypr(ventana)
        const ws = Hyprland.focusedWorkspace
        const addr = root._dir(hl)
        if (!hl || !ws || addr === "")
            return false
        if (hl.workspace && hl.workspace.id === ws.id)
            return true

        if (Hyprland.usingLua) {
            const prevAddr = root._dir(Hyprland.activeToplevel)
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws.id
                              + ', window = "address:' + addr + '" })')
            if (prevAddr !== "" && prevAddr !== addr)
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + prevAddr + '" })')
        } else {
            Hyprland.dispatch("movetoworkspacesilent " + ws.id + ",address:" + addr)
        }
        return true
    }

    function enfocarEscritorio(id) {
        if (!root.disponible)
            return false
        Hyprland.dispatch(Hyprland.usingLua
            ? "hl.dsp.focus({ workspace = " + id + " })"
            : "workspace " + id)
        return true
    }

    // Búsquedas

    function porTitulo(titulo) {
        if (!titulo || titulo === "")
            return null
        for (const hl of root.ventanas)
            if (hl && hl.title === titulo)
                return hl
        return null
    }

    // La ventana que mejor case con una lista de pistas sueltas: se comparan
    // contra la clase, la clase inicial y el título, en los dos sentidos —una
    // pista puede ser más larga o más corta que la clase—. Lo usa la bandeja,
    // que solo sabe el id, el título y el tooltip del icono y tiene que
    // adivinar a qué ventana corresponden.
    function porPistas(pistas) {
        const claves = (pistas || [])
            .map(k => String(k || "").toLowerCase().replace(/\.desktop$/, "").trim())
            .filter(k => k !== "")
        if (claves.length === 0)
            return null
        for (const tl of root.ventanas) {
            if (!tl)
                continue
            const ipc = tl.lastIpcObject
            const cls = String(ipc?.class || "").toLowerCase()
            const icls = String(ipc?.initialClass || "").toLowerCase()
            const titulo = String(tl.title || "").toLowerCase()
            for (const k of claves) {
                if ((cls !== "" && (cls.indexOf(k) !== -1 || k.indexOf(cls) !== -1))
                        || (icls !== "" && (icls.indexOf(k) !== -1 || k.indexOf(icls) !== -1))
                        || (titulo !== "" && titulo.indexOf(k) !== -1))
                    return tl
            }
        }
        return null
    }

    // ¿Tiene ventanas el escritorio activo de este monitor? Es lo que decide el
    // autoocultar inteligente del dock, y que sea por monitor importa: una
    // ventana a pantalla completa en la principal no debe esconder el dock de la
    // secundaria, que está vacía.
    //
    // Sin Hyprland no se sabe en qué monitor está cada ventana, y se devuelve
    // false —"escritorio vacío"—, con lo que el modo inteligente se comporta
    // como "siempre visible": esconder un dock sin saber si estorba sería peor.
    function hayVentanasEn(monitor) {
        if (!root.disponible)
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
        for (const tl of root.ventanas) {
            const ipc = tl ? tl.lastIpcObject : null
            if (!ipc || ipc.mapped === false || ipc.hidden === true)
                continue
            if (tl.workspace && tl.workspace.id === wsId)
                return true
        }
        return false
    }
}
