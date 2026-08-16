#!/usr/bin/env python3
# Lanzador de TRABAJOS del harness: comandos que duran más de lo que aguanta
# una tarjeta, y comandos INTERACTIVOS que piden algo por teclado.
#
# El `run_command` de siempre corta a los 20 s y no tiene forma de contestar a
# un "¿continuar? [s/N]": un `make`, un `npm install` o un `ssh` que pregunta se
# quedaban fuera del harness. Esto los cubre con dos modos y UN solo formato:
#
#   job-run.py [--pty] [--cwd DIR] -- <argv...>
#
#   · sin --pty: tuberías normales, stdout y stderr por separado.
#   · con --pty: un pseudoterminal de verdad (setsid + TIOCSCTTY + tamaño), que
#     es lo que hace que sudo pida contraseña, que ssh acepte una huella y que
#     los programas que miran isatty() se comporten como en un terminal.
#
# Protocolo NDJSON (una línea de JSON por mensaje), igual en los dos modos para
# que el lado QML tenga un solo camino que auditar:
#   sale  {"t":"up","pid":123}
#   sale  {"t":"out","d":"..."}   salida (en modo pty, todo va aquí)
#   sale  {"t":"err","d":"..."}   solo sin pty
#   sale  {"t":"exit","code":0}
#   entra {"t":"in","d":"texto\n"}  teclea en el proceso
#   entra {"t":"sig","s":"INT"}     señal al GRUPO (así muere la tubería entera)
#   entra {"t":"eof"}               cierra su entrada
import fcntl
import json
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import threading

OUT = sys.stdout
LOCK = threading.Lock()


def emitir(obj):
    with LOCK:
        OUT.write(json.dumps(obj, ensure_ascii=False) + "\n")
        OUT.flush()


SENALES = {"INT": signal.SIGINT, "TERM": signal.SIGTERM,
           "KILL": signal.SIGKILL, "HUP": signal.SIGHUP,
           "QUIT": signal.SIGQUIT}


def main():
    argv = sys.argv[1:]
    usa_pty = "--pty" in argv
    cwd = None
    if "--cwd" in argv:
        cwd = argv[argv.index("--cwd") + 1]
    if "--" not in argv:
        emitir({"t": "exit", "code": 2})
        return
    cmd = argv[argv.index("--") + 1:]
    if not cmd:
        emitir({"t": "exit", "code": 2})
        return

    if usa_pty:
        maestro, esclavo = pty.openpty()
        # 120x40: un tamaño de terminal creíble. Sin esto muchos programas
        # asumen 80 columnas o se vuelven locos formateando.
        try:
            fcntl.ioctl(esclavo, termios.TIOCSWINSZ,
                        struct.pack("HHHH", 40, 120, 0, 0))
        except OSError:
            pass

        def preparar():
            # Sesión propia + terminal de control: es lo que convierte el pty en
            # "el terminal" del proceso, y lo que permite matar el GRUPO entero.
            os.setsid()
            try:
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)
            except OSError:
                pass

        proc = subprocess.Popen(cmd, stdin=esclavo, stdout=esclavo,
                                stderr=esclavo, preexec_fn=preparar,
                                cwd=cwd, close_fds=True)
        os.close(esclavo)
        escritura = maestro
        lectores = [(maestro, "out")]
    else:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                                preexec_fn=os.setsid, cwd=cwd, close_fds=True)
        escritura = proc.stdin.fileno()
        lectores = [(proc.stdout.fileno(), "out"), (proc.stderr.fileno(), "err")]

    emitir({"t": "up", "pid": proc.pid})

    # Órdenes del harness: llegan por stdin en su propio hilo para no frenar la
    # lectura de la salida.
    def ordenes():
        for linea in sys.stdin:
            linea = linea.strip()
            if not linea:
                continue
            try:
                msg = json.loads(linea)
            except json.JSONDecodeError:
                continue
            t = msg.get("t")
            if t == "in":
                try:
                    os.write(escritura, str(msg.get("d", "")).encode("utf-8"))
                except OSError:
                    pass
            elif t == "sig":
                sig = SENALES.get(str(msg.get("s", "TERM")).upper(), signal.SIGTERM)
                try:
                    os.killpg(os.getpgid(proc.pid), sig)
                except OSError:
                    pass
            elif t == "eof":
                try:
                    if usa_pty:
                        os.write(escritura, b"\x04")     # Ctrl-D
                    else:
                        os.close(escritura)
                except OSError:
                    pass

    threading.Thread(target=ordenes, daemon=True).start()

    vivos = [fd for fd, _ in lectores]
    canal = dict(lectores)
    while vivos:
        try:
            listos, _, _ = select.select(vivos, [], [], 0.25)
        except OSError:
            break
        for fd in listos:
            try:
                datos = os.read(fd, 65536)
            except OSError:
                datos = b""          # el pty da EIO al morir el hijo: es su EOF
            if not datos:
                vivos.remove(fd)
                continue
            emitir({"t": canal[fd],
                    "d": datos.decode("utf-8", errors="replace")})

    proc.wait()
    emitir({"t": "exit", "code": proc.returncode})


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
