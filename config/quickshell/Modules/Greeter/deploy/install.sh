#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Instalador del greeter Quickshell "Solitude" para greetd.     ║
# ║  Uso:  sudo bash install.sh                                    ║
# ╚══════════════════════════════════════════════════════════════╝
# El código del greeter vive en tu config principal, junto a la barra:
#     ~/.config/quickshell/Modules/Greeter/
# greetd corre como el usuario 'greeter', que NO puede leer tu home, así
# que este script copia una instantánea a /etc/greetd/quickshell/.
# NO habilita el servicio automáticamente (pruébalo antes en una TTY).

set -euo pipefail

DEPLOY_SRC="$(cd "$(dirname "$0")" && pwd)"      # …/Modules/Greeter/deploy
MOD_SRC="$(cd "$DEPLOY_SRC/.." && pwd)"          # …/Modules/Greeter
USER_NAME="${SUDO_USER:-salesprendes}"
WALLPAPER_SRC="/home/$USER_NAME/Imágenes/Wallpapers/black.jpg"

if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta con sudo: sudo bash install.sh" >&2
    exit 1
fi

echo "==> ¿greetd instalado?"
command -v greetd >/dev/null 2>&1 || { echo "    Falta greetd:  sudo pacman -S greetd"; exit 1; }

echo "==> Usuario de sistema 'greeter' (sysusers del paquete)"
systemd-sysusers >/dev/null 2>&1 || true
if ! getent passwd greeter >/dev/null 2>&1; then
    useradd --system --user-group --shell /usr/bin/nologin \
            --home-dir /var/lib/greeter --create-home greeter || true
fi

echo "==> Directorio de estado escribible por 'greeter' (memoria del último login)"
install -d -o greeter -g greeter -m 0700 /var/lib/greeter 2>/dev/null \
    || install -d -m 0755 /var/lib/greeter

echo "==> Desplegando el módulo del greeter en /etc/greetd/quickshell"
install -d -m 0755 /etc/greetd/quickshell/Modules
rm -rf /etc/greetd/quickshell/Modules/Greeter
cp -r "$MOD_SRC" /etc/greetd/quickshell/Modules/Greeter
rm -rf /etc/greetd/quickshell/Modules/Greeter/deploy   # los configs no van dentro del módulo

echo "==> Punto de entrada + configs de greetd"
install -m 0644 "$DEPLOY_SRC/shell.qml"              /etc/greetd/quickshell/shell.qml
install -m 0644 "$DEPLOY_SRC/greetd-config.toml"     /etc/greetd/config.toml
install -m 0644 "$DEPLOY_SRC/hyprland-greeter.conf"  /etc/greetd/hyprland-greeter.conf

echo "==> Fondo legible por 'greeter'"
if [ -f "$WALLPAPER_SRC" ]; then
    install -m 0644 "$WALLPAPER_SRC" /etc/greetd/wall.jpg
else
    echo "    AVISO: no encuentro $WALLPAPER_SRC — copia tú un fondo a /etc/greetd/wall.jpg"
fi

echo "==> Permisos de lectura en /etc/greetd"
chmod -R a+rX /etc/greetd

echo "==> Grupos video/input/seat para 'greeter'"
for grp in video input seat; do
    getent group "$grp" >/dev/null 2>&1 && usermod -aG "$grp" greeter || true
done

cat <<'NEXT'

==> Hecho. PRUEBA ANTES DE HABILITARLO (no te dejes fuera):

  1) TTY libre:  Ctrl+Alt+F3  y entra con tu usuario.
  2) Prueba el compositor del greeter:
       Hyprland --config /etc/greetd/hyprland-greeter.conf
     Comprueba que sale la tarjeta y que el login arranca tu sesión.

  Si todo va bien, habilita greetd como gestor de sesión:
       sudo systemctl disable <tu-dm-actual>   # sddm/gdm/lightdm (NO lo borres)
       sudo systemctl enable greetd

  Reinicia. Si algo falla, vuelve a una TTY y reactiva tu DM anterior.

  Para re-desplegar tras editar el módulo:  sudo bash install.sh
NEXT
