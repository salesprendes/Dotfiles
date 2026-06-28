#!/usr/bin/env bash
set -Eeuo pipefail

BASE_PACKAGES=(
  quickshell qt6-declarative hyprland ttf-jetbrains-mono-nerd cliphist
  wl-clipboard hyprlock polkit hyprpolkitagent curl procps-ng nano
  networkmanager bluez bluez-utils pipewire wireplumber pipewire-pulse
  playerctl upower rtkit hypridle power-profiles-daemon xdg-user-dirs
  hyprshot net-tools
)

AMD_PACKAGES=(
  mesa vulkan-radeon linux-firmware mesa-utils vulkan-tools libva-utils
  libva-mesa-driver lib32-mesa lib32-vulkan-radeon lib32-libva-mesa-driver
)

YAY_BUILD=(base-devel git)
BRIGHTNESSCTL=(brightnessctl)
DDC=(ddcutil)

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/salesprendes/Dotfiles.git}"
PACMAN="${PACMAN:-pacman}"
SUDO="${SUDO:-sudo}"
INSTALL_USER="${SUDO_USER:-${USER:-}}"
[[ -z "${INSTALL_USER}" ]] && INSTALL_USER="$(id -un)"
[[ ${EUID} -eq 0 ]] && SUDO=""
INSTALL_HOME="$(getent passwd "${INSTALL_USER}" | cut -d: -f6)"
[[ -z "${INSTALL_HOME}" ]] && INSTALL_HOME="${HOME}"

C0=$'\033[0m' C2=$'\033[2m' C1=$'\033[31m' C3=$'\033[32m'
C4=$'\033[33m' C5=$'\033[34m' C6=$'\033[36m' CB=$'\033[1m'

spinner_pid=""
cleanup() { [[ -n "${spinner_pid}" ]] && kill "${spinner_pid}" 2>/dev/null || true; wait "${spinner_pid}" 2>/dev/null || true; printf "\033[?25h" || true; }
trap cleanup EXIT

on_error() { cleanup; printf "\n%sError en la linea %s.%s\n" "${C1}" "$1" "${C0}" >&2; }
trap 'on_error "$LINENO"' ERR

title() {
  clear
  printf "%s\n" "${C6}${CB}"
  printf "  %s%s%s%s%s%s%s%s%s%s%s%s\n" \
    "███████╗ " " ██████╗ " "██╗      " "███████╗ " "███████╗ " "██████╗  " "██████╗  " "███████╗ " "███╗  ██╗" "██████╗  " "███████╗ " "███████╗ "
  printf "  %s%s%s%s%s%s%s%s%s%s%s%s\n" \
    "██╔════╝ " "██╔═══██╗" "██║      " "██╔════╝ " "██╔════╝ " "██╔══██╗ " "██╔══██╗ " "██╔════╝ " "████╗ ██║" "██╔══██╗ " "██╔════╝ " "██╔════╝ "
  printf "  %s%s%s%s%s%s%s%s%s%s%s%s\n" \
    "███████╗ " "████████║" "██║      " "███████╗ " "███████╗ " "██████╔╝ " "██████╔╝ " "███████╗ " "██╔██╗██║" "██║  ██║ " "███████╗ " "███████╗ "
  printf "  %s%s%s%s%s%s%s%s%s%s%s%s\n" \
    "╚════██║ " "██╔═══██║" "██║      " "██╔════╝ " "╚════██║ " "██║      " "██╔══██╗ " "██╔════╝ " "██║╚████║" "██║  ██║ " "██╔════╝ " "╚════██║ "
  printf "  %s%s%s%s%s%s%s%s%s%s%s%s\n" \
    "███████║ " "██║   ██║" "███████╗ " "███████║ " "███████║ " "██║      " "██║  ██║ " "███████║ " "██║ ╚███║" "██████╔╝ " "███████║ " "███████║ "
  printf "  %s%s%s%s%s%s%s%s%s%s%s%s\n" \
    "╚══════╝ " "╚═╝   ╚═╝" "╚══════╝ " "╚══════╝ " "╚══════╝ " "╚═╝      " "╚═╝  ╚═╝ " "╚══════╝ " "╚═╝  ╚══╝" "╚═════╝  " "╚══════╝ " "╚══════╝ "
  printf "%s\n" "${C0}"
  printf "  Instalador de paquetes para Arch Linux\n\n"
}

msg() { local l="$1"; shift; case "$l" in
  n) printf "%s%s%s\n" "${C2}" "$*" "${C0}" ;;
  o) printf "  %s✓%s %s\n" "${C3}" "${C0}" "$*" ;;
  w) printf "  %s!%s %s\n" "${C4}" "${C0}" "$*" ;;
  f) printf "  %s✗%s %s\n" "${C1}" "${C0}" "$*" >&2; exit 1 ;;
esac; }

with_spinner() {
  local m="$1"; shift
  (
    local f=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") i=0
    trap 'exit 0' TERM INT; trap - ERR; set +e
    printf "\033[?25l"
    while true; do printf "\r  %s%s%s %s" "${C6}" "${f[$i]}" "${C0}" "${m}"; i=$(((i+1)%${#f[@]})); sleep 0.08; done
  ) &
  spinner_pid=$!
  if "$@" >/dev/null 2>&1; then
    kill "${spinner_pid}" 2>/dev/null || true; wait "${spinner_pid}" 2>/dev/null || true; spinner_pid=""
    printf "\r  %s✓%s %s\n" "${C3}" "${C0}" "${m}"
  else
    local st=$?
    kill "${spinner_pid}" 2>/dev/null || true; wait "${spinner_pid}" 2>/dev/null || true; spinner_pid=""
    printf "\r  %s✗%s %s\n" "${C1}" "${C0}" "${m}"; return "${st}"
  fi
}

install_group() {
  local label="$1"; shift; local missing=()
  mapfile -t missing < <(for pkg in "$@"; do "${PACMAN}" -Qq "$pkg" >/dev/null 2>&1 || echo "$pkg"; done)
  [[ ${#missing[@]} -eq 0 ]] && { msg o "${label}: todo instalado"; return; }
  msg n "${label}: ${#missing[@]} paquetes pendientes"
  for pkg in "${missing[@]}"; do printf "    %s•%s %s\n" "${C5}" "${C0}" "${pkg}"; done
  with_spinner "Descargando e instalando ${label}" ${SUDO} "${PACMAN}" -S --needed --noconfirm -- "${missing[@]}"
}

supports_brightnessctl() {
  shopt -s nullglob; local dev
  for dev in /sys/class/backlight/*; do
    [[ -r "${dev}/brightness" && -r "${dev}/max_brightness" ]] || continue
    [[ "$(cat "${dev}/max_brightness" 2>/dev/null || echo 0)" -gt 0 ]] || continue
    return 0
  done
  return 1
}

has_amd_graphics() {
  shopt -s nullglob; local vendor
  for vendor in /sys/class/drm/card*/device/vendor; do
    [[ -r "${vendor}" ]] || continue
    [[ "$(cat "${vendor}")" == "0x1002" ]] && return 0
  done
  command -v lspci >/dev/null 2>&1 && lspci -nn | grep -Eiq 'VGA|3D|Display' && lspci -nn | grep -Eiq 'AMD|ATI' && return 0
  return 1
}

install_yay() {
  command -v yay >/dev/null 2>&1 && { msg o "yay ya esta instalado"; return; }
  install_group "herramientas para compilar yay" "${YAY_BUILD[@]}"
  local dir="/tmp/storm-yay-build-${INSTALL_USER}-$$"
  local cmd='set -Eeuo pipefail; rm -rf "$1"; git clone https://aur.archlinux.org/yay.git "$1"; cd "$1"; makepkg -f --noconfirm'
  rm -rf "${dir}"
  if [[ ${EUID} -eq 0 ]]; then
    with_spinner "Compilando yay" runuser -u "${INSTALL_USER}" -- bash -lc "${cmd}" _ "${dir}"
  else
    with_spinner "Compilando yay" bash -lc "${cmd}" _ "${dir}"
  fi
  local pkg="$(find "${dir}" -maxdepth 1 -type f -name 'yay-*.pkg.tar.*' | head -n 1)"
  [[ -n "${pkg}" ]] || msg f "No se encontro el paquete compilado de yay."
  with_spinner "Instalando yay" ${SUDO} "${PACMAN}" -U --noconfirm -- "${pkg}"
}

install_dotfiles() {
  install_group "herramientas para descargar dotfiles" git
  local src="" d
  if d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd -P 2>/dev/null)"; then
    [[ -d "${d}/config" || -d "${d}/local" ]] && src="${d}"
  fi
  if [[ -z "${src}" ]]; then
    src="/tmp/storm-dotfiles-${INSTALL_USER}-$$"
    rm -rf "${src}"
    if [[ ${EUID} -eq 0 && "${INSTALL_USER}" != "root" ]]; then
      with_spinner "Descargando dotfiles" runuser -u "${INSTALL_USER}" -- git clone --depth 1 "${DOTFILES_REPO}" "${src}"
    else
      with_spinner "Descargando dotfiles" git clone --depth 1 "${DOTFILES_REPO}" "${src}"
    fi
  fi
  copy() { [[ -d "${src}/$1" ]] || return 0; mkdir -p "${INSTALL_HOME}/$2"; cp -a "${src}/$1/." "${INSTALL_HOME}/$2/"; [[ ${EUID} -eq 0 ]] && chown -R "${INSTALL_USER}:${INSTALL_USER}" "${INSTALL_HOME}/$2"; }
  copy config .config
  copy local .local
  [[ -d "${INSTALL_HOME}/.local/bin" ]] && chmod -R u+rx "${INSTALL_HOME}/.local/bin"
}

main() {
  title
  msg n "La salida de pacman/makepkg se oculta para mantener la animacion limpia."; echo
  [[ -f /etc/arch-release ]] || msg f "Este instalador esta pensado para Arch Linux."
  command -v "${PACMAN}" >/dev/null 2>&1 || msg f "No se encontro pacman."
  [[ -n "${SUDO}" ]] && { "${SUDO}" -k; "${SUDO}" -p "  Se requiere sudo. Contrasena: " true; msg o "Privilegios de administrador preparados"; }
  with_spinner "Actualizando sistema y bases de datos de paquetes" ${SUDO} "${PACMAN}" -Syu --noconfirm
  install_group "paquetes base" "${BASE_PACKAGES[@]}"
  install_yay
  if supports_brightnessctl; then
    install_group "control de brillo interno" "${BRIGHTNESSCTL[@]}"
  else
    install_group "control DDC/CI para monitores externos" "${DDC[@]}"
    if ! getent group i2c >/dev/null 2>&1; then
      with_spinner "Creando grupo i2c" ${SUDO} groupadd i2c
    fi
    if id -nG "${INSTALL_USER}" | tr ' ' '\n' | grep -qx i2c; then
      msg o "${INSTALL_USER} ya pertenece al grupo i2c"
    else
      with_spinner "Anadiendo ${INSTALL_USER} al grupo i2c" ${SUDO} usermod -aG i2c "${INSTALL_USER}"
      msg w "Cierra sesion y vuelve a entrar para activar el grupo i2c."
    fi
  fi
  has_amd_graphics && install_group "graficos AMD" "${AMD_PACKAGES[@]}" || msg o "Graficos AMD no detectados; se omite ese grupo"
  for s in NetworkManager.service bluetooth.service rtkit-daemon.service power-profiles-daemon.service; do
    systemctl list-unit-files "${s}" >/dev/null 2>&1 && with_spinner "Habilitando ${s}" ${SUDO} systemctl enable --now "${s}"
  done
  if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    if [[ ${EUID} -eq 0 && "${INSTALL_USER}" != "root" ]]; then
      with_spinner "Actualizando carpetas XDG" runuser -u "${INSTALL_USER}" -- xdg-user-dirs-update
    else
      with_spinner "Actualizando carpetas XDG" xdg-user-dirs-update
    fi
  fi
  install_dotfiles
  echo; msg o "Instalacion finalizada"
  msg n "Si se modificaron grupos de usuario, reinicia la sesion antes de probar DDC/CI."
}

main "$@"
