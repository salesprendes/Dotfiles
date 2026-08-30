#!/usr/bin/env python3
"""Regenera el catálogo de emojis del selector.

    python3 tests/emoji.py

Escribe Modules/Emoji/emoji.json a partir de la base de datos Unicode que trae
Python y de los códigos ISO 3166-1 del sistema. No descarga nada.

POR QUÉ UN GUION Y NO UN ARCHIVO A MANO: el catálogo son 2.500 entradas. Escrito
a mano se queda viejo en cuanto Unicode saca una versión, y nadie lo repasa.
Generado, actualizarlo es correr esto con un Python más nuevo.

FORMATO. Una lista de {c, n, g}: carácter, nombre en MINÚSCULAS (por el que
busca el selector) y grupo (el filtro de fichas). Las claves son de una letra a
propósito: con 2.500 entradas, "character"/"name"/"group" costarían ~60 kB de
más en un archivo que se lee entero de una vez.

BANDERAS. Se componen con dos indicadores regionales, y solo se generan las de
códigos ISO de VERDAD: las 676 combinaciones AA–ZZ llenaban el catálogo de
pares de letras en una caja, porque ninguna fuente dibuja como bandera algo que
no es un país.
"""
import json
import os
import sys
import unicodedata

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "Modules", "Emoji", "emoji.json")
ISO = "/usr/share/iso-codes/json/iso_3166-1.json"

# Bloques con pictogramas de uso corriente. No se filtra por propiedad Emoji
# porque unicodedata no la expone: se toman los bloques enteros y se deja fuera
# lo que no tenga nombre (los huecos sin asignar).
RANGOS = [
    (0x1F300, 0x1F5FF, "Símbolos"),
    (0x1F600, 0x1F64F, "Caras"),
    (0x1F680, 0x1F6FF, "Viajes"),
    (0x1F900, 0x1F9FF, "Suplemento"),
    (0x1FA70, 0x1FAFF, "Objetos"),
    (0x2600, 0x26FF, "Misceláneos"),
    (0x2700, 0x27BF, "Dingbats"),
    (0x1F004, 0x1F0FF, "Juegos"),
    (0x2B00, 0x2BFF, "Formas"),
]

INDICADOR_REGIONAL = 0x1F1E6


# ── ALIAS EN CASTELLANO ─────────────────────────────────────────────────────
# unicodedata solo da nombres en inglés, así que ":fuego" no encontraba 🔥 y
# ":corazon" no encontraba ningún corazón. En un shell que habla castellano eso
# convierte el selector en un diccionario de inglés.
#
# La traducción va por PALABRAS, no por emoji, y esa es la idea: hay cientos de
# emojis pero los nombres se construyen con un vocabulario corto y repetido
# ("face", "heart", "hand", "with", "smiling"). Traduciendo ~130 palabras se
# cubren miles de entradas, y además ":cara" pasa a encontrar TODAS las caras,
# que es como busca la gente de verdad.
#
# Los alias se AÑADEN al nombre inglés, no lo sustituyen: quien busque "fire"
# sigue encontrándolo.
PALABRAS = {
    "face": "cara", "faces": "caras", "smiling": "sonriente", "smile": "sonrisa",
    "grinning": "sonriente", "laughing": "riendo", "tears": "lagrimas",
    "joy": "alegria", "crying": "llorando", "cry": "llanto", "sad": "triste",
    "angry": "enfadado", "rage": "furia", "heart": "corazon", "hearts": "corazones",
    "kiss": "beso", "love": "amor", "eyes": "ojos", "eye": "ojo",
    "hand": "mano", "hands": "manos", "finger": "dedo", "thumbs": "pulgar",
    "up": "arriba", "down": "abajo", "left": "izquierda", "right": "derecha",
    "fire": "fuego", "water": "agua", "droplet": "gota", "star": "estrella",
    "sun": "sol", "moon": "luna", "cloud": "nube", "rain": "lluvia",
    "snow": "nieve", "snowflake": "copo nieve", "lightning": "rayo",
    "thunder": "trueno", "rainbow": "arcoiris", "wind": "viento",
    "tree": "arbol", "flower": "flor", "leaf": "hoja", "plant": "planta",
    "cat": "gato", "dog": "perro", "bird": "pajaro", "fish": "pez",
    "horse": "caballo", "cow": "vaca", "pig": "cerdo", "mouse": "raton",
    "bear": "oso", "lion": "leon", "monkey": "mono", "rabbit": "conejo",
    "food": "comida", "pizza": "pizza", "bread": "pan", "cheese": "queso",
    "coffee": "cafe", "beer": "cerveza", "wine": "vino", "cake": "tarta",
    "apple": "manzana", "banana": "platano", "meat": "carne", "egg": "huevo",
    "car": "coche", "bus": "autobus", "train": "tren", "plane": "avion",
    "airplane": "avion", "bicycle": "bicicleta", "boat": "barco", "ship": "barco",
    "rocket": "cohete", "house": "casa", "home": "casa", "building": "edificio",
    "book": "libro", "books": "libros", "pencil": "lapiz", "pen": "boligrafo",
    "computer": "ordenador", "laptop": "portatil", "phone": "telefono",
    "telephone": "telefono", "mobile": "movil", "camera": "camara",
    "clock": "reloj", "watch": "reloj", "calendar": "calendario",
    "beverage": "bebida", "mug": "taza", "hot": "caliente",
    "money": "dinero", "bag": "bolsa", "box": "caja", "gift": "regalo",
    "key": "llave", "lock": "candado", "locked": "cerrado", "unlocked": "abierto",
    "light": "luz", "bulb": "bombilla", "battery": "bateria",
    "music": "musica", "musical": "musical", "note": "nota", "notes": "notas",
    "guitar": "guitarra", "drum": "tambor", "bell": "campana",
    "game": "juego", "ball": "pelota", "football": "futbol", "soccer": "futbol",
    "trophy": "trofeo", "medal": "medalla", "flag": "bandera", "flags": "banderas",
    "check": "marca", "cross": "cruz", "warning": "aviso", "question": "pregunta",
    "exclamation": "exclamacion", "mark": "signo", "arrow": "flecha",
    "circle": "circulo", "square": "cuadrado", "triangle": "triangulo",
    "red": "rojo", "green": "verde", "blue": "azul", "yellow": "amarillo",
    "black": "negro", "white": "blanco", "orange": "naranja", "purple": "morado",
    "man": "hombre", "woman": "mujer", "person": "persona", "people": "gente",
    "baby": "bebe", "child": "nino", "family": "familia",
    "sleeping": "durmiendo", "sleep": "sueno", "tired": "cansado",
    "thinking": "pensando", "party": "fiesta", "popper": "matasuegras",
    "skull": "calavera", "ghost": "fantasma", "alien": "alienigena",
    "robot": "robot", "poop": "caca", "trash": "basura",
    "hospital": "hospital", "pill": "pastilla", "syringe": "jeringa",
    "mail": "correo", "envelope": "sobre", "package": "paquete",
    "scissors": "tijeras", "hammer": "martillo", "wrench": "llave inglesa",
    "gear": "engranaje", "shield": "escudo", "sword": "espada",
}


# Casos en los que el nombre Unicode NO es la palabra que usa la gente. ☕ se
# llama "hot beverage", no "coffee"; 🙏 es "person with folded hands", no
# "pray". Traducir por palabras no puede arreglar eso, así que van a mano —
# son pocos y son justo los que más se buscan.
DIRECTOS = {
    "☕": "cafe bebida taza",
    "🍺": "cerveza",
    "🍻": "cervezas brindis",
    "🎉": "fiesta celebracion",
    "👍": "bien ok vale aprobado",
    "👎": "mal no",
    "🙏": "gracias rezar porfavor",
    "💯": "cien perfecto",
    "😂": "risa lol",
    "😍": "enamorado",
    "🤔": "duda",
    "👌": "perfecto vale",
    "✅": "correcto hecho si",
    "❌": "error no mal",
    "⚠": "cuidado peligro",
    "🚀": "lanzar rapido",
    "💡": "idea",
    "🎂": "cumpleanos",
    "🍕": "pizza",
    "🐶": "perrito cachorro",
    "❤": "corazon amor rojo",
    "⭐": "estrella favorito",
    "🔒": "bloqueado seguro",
    "🔑": "clave contrasena",
    "📌": "chincheta fijar",
    "🕐": "hora",
    "💻": "ordenador portatil",
    "📱": "movil telefono",
    "🎵": "musica cancion",
    "🌙": "luna noche",
}


def alias_es(nombre):
    """Palabras en castellano para un nombre inglés, sin repetir."""
    fuera = []
    for palabra in nombre.split():
        traducida = PALABRAS.get(palabra)
        if traducida and traducida not in fuera:
            fuera.append(traducida)
    return " ".join(fuera)


def catalogo():
    fuera = []
    vistos = set()
    for inicio, fin, grupo in RANGOS:
        for cp in range(inicio, fin + 1):
            ch = chr(cp)
            try:
                nombre = unicodedata.name(ch)
            except ValueError:
                continue          # hueco sin asignar en este bloque
            if ch in vistos:
                continue
            vistos.add(ch)
            base = nombre.lower()
            es = alias_es(base)
            directo = DIRECTOS.get(ch, "")
            extras = " ".join(x for x in (es, directo) if x)
            fuera.append({"c": ch, "n": base + (" " + extras if extras else ""), "g": grupo})

    if os.path.exists(ISO):
        paises = json.load(open(ISO))["3166-1"]
        for pais in paises:
            cod = pais.get("alpha_2", "")
            if len(cod) != 2:
                continue
            ch = (chr(INDICADOR_REGIONAL + ord(cod[0]) - 65)
                  + chr(INDICADOR_REGIONAL + ord(cod[1]) - 65))
            nombre = (pais.get("common_name") or pais.get("name") or cod).lower()
            # El código va en el nombre: buscar "es" encuentra España sin tener
            # que saber cómo se llama el país en el idioma del archivo ISO.
            fuera.append({"c": ch, "n": "flag bandera " + nombre + " " + cod.lower(),
                          "g": "Banderas"})
    else:
        print("aviso: no está %s, el catálogo va sin banderas" % ISO, file=sys.stderr)

    return fuera


def main():
    datos = catalogo()
    os.makedirs(os.path.dirname(DESTINO), exist_ok=True)
    with open(DESTINO, "w") as f:
        json.dump(datos, f, ensure_ascii=False, separators=(",", ":"))
    grupos = {}
    for e in datos:
        grupos[e["g"]] = grupos.get(e["g"], 0) + 1
    print("%d entradas en %s" % (len(datos), os.path.relpath(DESTINO, RAIZ)))
    for g in sorted(grupos, key=lambda k: -grupos[k]):
        print("  %-24s %d" % (g, grupos[g]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
