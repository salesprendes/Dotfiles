import socket, sys, threading
def sirve(p):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", p)); s.listen(8)
    while True:
        c, _ = s.accept()          # acepta y no contesta jamás
        threading.Thread(target=lambda: None).start()
for p in [int(x) for x in sys.argv[1:]]:
    threading.Thread(target=sirve, args=(p,), daemon=True).start()
threading.Event().wait()
