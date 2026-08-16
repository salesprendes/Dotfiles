#!/usr/bin/env python3
# EDICIÓN ANCLADA POR HASH (la idea de hashline de oh-my-pi).
#
# El problema que resuelve: editar por número de línea es frágil (el archivo se
# mueve entre que el modelo lo lee y lo edita) y editar reproduciendo el texto
# viejo es caro (el modelo repite lo que ya vio, gastando contexto y colándose
# en un espacio). Anclar por CONTENIDO junta lo bueno de ambos: se dice "línea
# 42, que empezaba por este hash", y si el archivo se movió el motor lo detecta
# — y, cuando puede, lo ARREGLA solo.
#
# Cada línea tiene un ancla `N#hash` (lo que imprime read_file numbered:true).
# Un parche es una lista de hunks que se aplican TODOS o NINGUNO:
#
#   {"op":"replace",       "at":"42#nd", "to":"48#x1", "text":"..."}
#   {"op":"insert_before", "at":"42#nd", "text":"..."}
#   {"op":"insert_after",  "at":"42#nd", "text":"..."}
#   {"op":"delete",        "at":"42#nd", "to":"44#q0"}
#
# Lo que aporta sobre el edit_lines de antes:
#   · VARIOS hunks en UNA llamada, aplicados de abajo arriba (los números no se
#     desplazan bajo los pies) y de forma atómica.
#   · RECUPERACIÓN de anclas obsoletas: si el hash ya no casa en la línea N, se
#     busca a dónde se movió. En un rango se exige el MISMO desplazamiento en
#     los dos extremos, que es lo que desambigua cuando hay cien líneas "}" con
#     el mismo hash.
#   · Inserciones explícitas, sin el baile de "sustituye la línea por sí misma
#     más lo nuevo".
#   · Ensayo (dry_run) y diff de lo que cambió.
#
# Todo llega por ENTORNO, nada por argv:
#   QS_P     ruta del archivo          QS_HUNKS  JSON con la lista de hunks
#   QS_TAG   etiqueta esperada ("")    QS_DRY    "1" = solo ensayar
#   QS_BAK   copia previa              QS_BD     carpeta de copias
#   QS_WIN   ventana de recuperación (por defecto 40 líneas)
import difflib
import json
import os
import shutil
import sys


def h(s):
    """El hash de UNA línea. Idéntico al que imprime read_file: FNV-1a de 16
    bits en base36, ignorando los espacios finales (que cambian sin querer
    decir nada)."""
    v = 2166136261
    for c in s.rstrip().encode("utf-8", errors="replace"):
        v = ((v ^ c) * 16777619) & 0xFFFFFFFF
    v &= 0xFFFF
    d = "0123456789abcdefghijklmnopqrstuvwxyz"
    o = ""
    for _ in range(3):
        o = d[v % 36] + o
        v //= 36
    return o


def tag_de(texto):
    """Etiqueta de instantánea del archivo entero: 4 hex. Sirve para decir
    "esto ya no se parece a lo que leíste" de un vistazo."""
    v = 2166136261
    for c in texto.encode("utf-8", errors="replace"):
        v = ((v ^ c) * 16777619) & 0xFFFFFFFF
    return "%04x" % (v & 0xFFFF)


class Obsoleta(Exception):
    pass


def parse_ancla(a):
    """Acepta 42, "42", "42#nd" y hasta la línea entera tal cual la imprime
    read_file ("42#nd|  const x = 1"). Ser generoso aquí evita media docena de
    reintentos con modelos locales."""
    if a is None:
        return None, ""
    if isinstance(a, int):
        return a, ""
    s = str(a).strip()
    if s == "":
        return None, ""
    if "|" in s:
        s = s.split("|", 1)[0].strip()
    if "#" in s:
        n, _, hh = s.partition("#")
        try:
            return int(n.strip()), hh.strip().lower()
        except ValueError:
            raise Obsoleta("ancla ilegible: " + str(a))
    try:
        return int(s), ""
    except ValueError:
        raise Obsoleta("ancla ilegible: " + str(a))


def casa(lineas, idx, hh):
    return 0 <= idx < len(lineas) and (hh == "" or h(lineas[idx]) == hh)


def candidatos(lineas, hh, centro, win):
    """Líneas cuyo hash es hh, primero cerca del centro y luego en todo el
    archivo. Devuelve (lista_en_ventana, lista_global)."""
    lo, hi = max(0, centro - win), min(len(lineas), centro + win + 1)
    dentro = [i for i in range(lo, hi) if h(lineas[i]) == hh]
    fuera = [i for i in range(len(lineas)) if h(lineas[i]) == hh]
    return dentro, fuera


def resolver(lineas, a_ini, a_fin, win, avisos):
    """Un ancla (o un par) contra el archivo REAL. Devuelve (ini, fin) en base
    0. Lanza Obsoleta si no hay forma honesta de recuperarlo."""
    n0, h0 = parse_ancla(a_ini)
    if n0 is None:
        raise Obsoleta("falta el ancla 'at'")
    i0 = n0 - 1
    par = a_fin is not None and str(a_fin).strip() != ""
    n1, h1 = parse_ancla(a_fin) if par else (n0, h0)
    i1 = n1 - 1

    # Camino feliz: los dos extremos casan donde el modelo cree.
    if casa(lineas, i0, h0) and casa(lineas, i1, h1):
        return i0, i1

    # RANGO: se busca UN desplazamiento que valga para los DOS extremos. Es lo
    # que desambigua cuando el hash es de una línea repetidísima (un "}"): mil
    # candidatos, pero solo un desplazamiento hace casar los dos a la vez.
    if par and h0 != "" and h1 != "":
        for d in sorted(range(-win, win + 1), key=abs):
            if d == 0:
                continue
            if casa(lineas, i0 + d, h0) and casa(lineas, i1 + d, h1):
                avisos.append("anclas reajustadas %d líneas (%d-%d → %d-%d)"
                              % (d, n0, n1, n0 + d, n1 + d))
                return i0 + d, i1 + d

    # Un solo extremo (o el par no cuadró): se recupera cada uno por su cuenta,
    # pero SOLO si la respuesta es inequívoca.
    def uno(idx, hh, n, cual):
        if casa(lineas, idx, hh):
            return idx
        if hh == "":
            raise Obsoleta("la línea %d no existe (el archivo tiene %d)"
                           % (n, len(lineas)))
        dentro, fuera = candidatos(lineas, hh, idx, win)
        if len(dentro) == 1:
            avisos.append("%s reanclado: %d → %d" % (cual, n, dentro[0] + 1))
            return dentro[0]
        if len(dentro) > 1:
            raise Obsoleta(
                "el ancla %d#%s (%s) es AMBIGUA: ese hash aparece en las líneas %s. "
                "Vuelve a leer el archivo y usa un rango con los dos extremos."
                % (n, hh, cual, ", ".join(str(x + 1) for x in dentro[:8])))
        if len(fuera) == 1:
            avisos.append("%s reanclado lejos: %d → %d" % (cual, n, fuera[0] + 1))
            return fuera[0]
        if len(fuera) > 1:
            raise Obsoleta(
                "el ancla %d#%s (%s) no está donde dices y ese hash se repite en %d "
                "sitios. Vuelve a leer el archivo." % (n, hh, cual, len(fuera)))
        real = h(lineas[idx]) if 0 <= idx < len(lineas) else "(no existe)"
        raise Obsoleta(
            "el ancla %d#%s (%s) ya no existe: la línea %d es ahora '%s' (hash %s). "
            "El archivo cambió desde que lo leíste: vuelve a leerlo."
            % (n, hh, cual, n, (lineas[idx][:60] if 0 <= idx < len(lineas) else ""),
               real))

    j0 = uno(i0, h0, n0, "inicio")
    j1 = uno(i1, h1, n1, "fin") if par else j0
    return j0, j1


def main():
    ruta = os.environ["QS_P"]
    win = int(os.environ.get("QS_WIN") or 40)
    dry = os.environ.get("QS_DRY") == "1"
    esperada = (os.environ.get("QS_TAG") or "").strip().lower()

    try:
        crudo = open(ruta, "rb").read()
    except OSError as e:
        print("No se pudo leer:", e)
        return
    bom = crudo.startswith(b"\xef\xbb\xbf")
    if bom:
        crudo = crudo[3:]
    texto = crudo.decode("utf-8", errors="replace")
    # Se trabaja SIEMPRE en LF y se restaura el final original al escribir: un
    # archivo con CRLF no debe convertirse a LF por haberlo tocado.
    crlf = "\r\n" in texto
    if crlf:
        texto = texto.replace("\r\n", "\n")
    lineas = texto.split("\n")

    actual = tag_de(texto)
    avisos = []
    if esperada and esperada != actual:
        avisos.append("la etiqueta del archivo cambió (%s → %s): se comprueba "
                      "cada ancla" % (esperada, actual))

    try:
        hunks = json.loads(os.environ["QS_HUNKS"])
    except (KeyError, json.JSONDecodeError) as e:
        print("hunks ilegibles:", e)
        return
    if not isinstance(hunks, list) or not hunks:
        print("No hay hunks que aplicar.")
        return

    # ── Comprobación previa: TODO se resuelve antes de tocar el disco ────────
    plan = []
    for k, hk in enumerate(hunks):
        if not isinstance(hk, dict):
            print("El hunk %d no es un objeto." % (k + 1))
            return
        op = str(hk.get("op") or "replace").lower()
        if op not in ("replace", "insert_before", "insert_after", "delete"):
            print("Hunk %d: op debe ser replace, insert_before, insert_after o "
                  "delete (llegó '%s')." % (k + 1, op))
            return
        try:
            ini, fin = resolver(lineas, hk.get("at"),
                                hk.get("to") if op in ("replace", "delete") else None,
                                win, avisos)
        except Obsoleta as e:
            print("Hunk %d NO aplicado (y por tanto NINGUNO): %s" % (k + 1, e))
            return
        if fin < ini:
            print("Hunk %d: el final (%d) va antes que el inicio (%d)."
                  % (k + 1, fin + 1, ini + 1))
            return
        cuerpo = hk.get("text")
        if op in ("replace", "insert_before", "insert_after") and cuerpo is None:
            print("Hunk %d: falta 'text' (usa op=delete para borrar)." % (k + 1))
            return
        nuevo = str(cuerpo).split("\n") if cuerpo not in (None, "") else []
        if op == "insert_before":
            plan.append((ini, ini - 1, nuevo, k))       # rango vacío antes de ini
        elif op == "insert_after":
            plan.append((fin + 1, fin, nuevo, k))       # rango vacío tras fin
        elif op == "delete":
            plan.append((ini, fin, [], k))
        else:
            plan.append((ini, fin, nuevo, k))

    # Solapes: dos hunks que tocan las mismas líneas darían un resultado que
    # depende del orden, y eso no es una edición, es una lotería.
    ordenado = sorted(plan, key=lambda p: (p[0], p[1]))
    for a, b in zip(ordenado, ordenado[1:]):
        if a[1] >= b[0] and not (a[0] > a[1] or b[0] > b[1]):
            print("Los hunks %d y %d se solapan (líneas %d-%d y %d-%d): sepáralos."
                  % (a[3] + 1, b[3] + 1, a[0] + 1, a[1] + 1, b[0] + 1, b[1] + 1))
            return

    # ── Aplicación: de abajo arriba, para que los índices no se muevan ───────
    salida = list(lineas)
    for ini, fin, nuevo, _ in sorted(plan, key=lambda p: p[0], reverse=True):
        salida[ini:fin + 1] = nuevo

    texto_nuevo = "\n".join(salida)
    if texto_nuevo == texto:
        print("El parche no cambia nada: el archivo queda igual.")
        for a in avisos:
            print("  ·", a)
        return

    diff = list(difflib.unified_diff(lineas, salida,
                                     fromfile="antes", tofile="después",
                                     lineterm="", n=2))

    if dry:
        print("ENSAYO (no se ha escrito nada). %d hunks se aplicarían a %s:"
              % (len(plan), ruta))
    else:
        try:
            bak = os.environ.get("QS_BAK") or ""
            if bak:
                # 0700: dentro van copias enteras de archivos del usuario.
                os.makedirs(os.environ.get("QS_BD") or os.path.dirname(bak),
                            mode=0o700, exist_ok=True)
                shutil.copy2(ruta, bak)
            final = texto_nuevo.replace("\n", "\r\n") if crlf else texto_nuevo
            datos = final.encode("utf-8")
            if bom:
                datos = b"\xef\xbb\xbf" + datos
            open(ruta, "wb").write(datos)
        except OSError as e:
            print("No se pudo escribir:", e)
            return
        print("Aplicados %d hunks a %s (%d → %d líneas). Nueva etiqueta: %s"
              % (len(plan), ruta, len(lineas), len(salida), tag_de(texto_nuevo)))

    for a in avisos:
        print("  ·", a)
    print("--- cambios ---")
    print("\n".join(diff)[:8000])


if __name__ == "__main__":
    main()
