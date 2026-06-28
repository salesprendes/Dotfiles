#!/usr/bin/env bash
set -Eeuo pipefail

BASE_PACKAGES=(
  quickshell
  qt6-declarative
  hyprland
  ttf-jetbrains-mono-nerd
  cliphist
  wl-clipboard
  hyprlock
  polkit
  hyprpolkitagent
  curl
  procps-ng
  nano
  networkmanager
  bluez
  bluez-utils
  pipewire
  wireplumber
  pipewire-pulse
  playerctl
  upower
  rtkit
  hypridle
  power-profiles-daemon
  xdg-user-dirs
  hyprshot
  net-tools
)

AMD_PACKAGES=(
  mesa
  vulkan-radeon
  linux-firmware
  mesa-utils
  vulkan-tools
  libva-utils
  libva-mesa-driver
  lib32-mesa
  lib32-vulkan-radeon
  lib32-libva-mesa-driver
)

YAY_BUILD_PACKAGES=(base-devel git)
BRIGHTNESSCTL_PACKAGES=(brightnessctl)
DDC_PACKAGES=(ddcutil)

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/salesprendes/Dotfiles.git}"
PACMAN="${PACMAN:-pacman}"
SUDO="${SUDO:-sudo}"
INSTALL_USER="${SUDO_USER:-${USER:-}}"

if [[ -z "${INSTALL_USER}" ]]; then
  INSTALL_USER="$(id -un)"
fi

if [[ ${EUID} -eq 0 ]]; then
  SUDO=""
fi

INSTALL_HOME="$(getent passwd "${INSTALL_USER}" | cut -d: -f6)"
if [[ -z "${INSTALL_HOME}" ]]; then
  INSTALL_HOME="${HOME}"
fi

COLOR_RESET=$'\033[0m'
COLOR_DIM=$'\033[2m'
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'
COLOR_CYAN=$'\033[36m'
COLOR_BOLD=$'\033[1m'

spinner_pid=""

cleanup() {
  if [[ -n "${spinner_pid}" ]] && kill -0 "${spinner_pid}" 2>/dev/null; then
    kill "${spinner_pid}" 2>/dev/null || true
    wait "${spinner_pid}" 2>/dev/null || true
  fi
  printf "\033[?25h" || true
}
trap cleanup EXIT

on_error() {
  local line="$1"
  cleanup
  echo
  printf "%sError en la linea %s.%s\n" "${COLOR_RED}" "${line}" "${COLOR_RESET}" >&2
}
trap 'on_error "$LINENO"' ERR

title() {
  clear
  printf "%s\n" "${COLOR_CYAN}${COLOR_BOLD}"
  printf "  ███████╗████████╗ ██████╗ ██████╗ ███╗   ███╗\n"
  printf "  ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗████╗ ████║\n"
  printf "  ███████╗   ██║   ██║   ██║██████╔╝██╔████╔██║\n"
  printf "  ╚════██║   ██║   ██║   ██║██╔══██╗██║╚██╔╝██║\n"
  printf "  ███████║   ██║   ╚██████╔╝██║  ██║██║ ╚═╝ ██║\n"
  printf "  ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝\n"
  printf "%s\n" "${COLOR_RESET}"
  printf "  Instalador de paquetes para Arch Linux\n\n"
}

note() {
  printf "%s%s%s\n" "${COLOR_DIM}" "$*" "${COLOR_RESET}"
}

ok() {
  printf "  %s✓%s %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

warn() {
  printf "  %s!%s %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$*"
}

fail() {
  printf "  %s✗%s %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
  exit 1
}

run_spinner() {
  local message="$1"
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0

  trap 'exit 0' TERM INT
  trap - ERR
  set +e

  printf "\033[?25l"
  while true; do
    printf "\r  %s%s%s %s" "${COLOR_CYAN}" "${frames[$i]}" "${COLOR_RESET}" "${message}"
    i=$(((i + 1) % ${#frames[@]}))
    sleep 0.08
  done
}

with_spinner() {
  local message="$1"
  shift

  run_spinner "${message}" &
  spinner_pid=$!
  if "$@" >/dev/null 2>&1; then
    kill "${spinner_pid}" 2>/dev/null || true
    wait "${spinner_pid}" 2>/dev/null || true
    spinner_pid=""
    printf "\r  %s✓%s %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${message}"
  else
    local status=$?
    kill "${spinner_pid}" 2>/dev/null || true
    wait "${spinner_pid}" 2>/dev/null || true
    spinner_pid=""
    printf "\r  %s✗%s %s\n" "${COLOR_RED}" "${COLOR_RESET}" "${message}"
    return "${status}"
  fi
}

require_arch() {
  [[ -f /etc/arch-release ]] || fail "Este instalador esta pensado para Arch Linux."
  command -v "${PACMAN}" >/dev/null 2>&1 || fail "No se encontro pacman."
}

require_sudo() {
  if [[ -n "${SUDO}" ]]; then
    "${SUDO}" -k
    "${SUDO}" -p "  Se requiere sudo. Contrasena: " true
    ok "Privilegios de administrador preparados"
  fi
}

sync_databases() {
  with_spinner "Actualizando sistema y bases de datos de paquetes" ${SUDO} "${PACMAN}" -Syu --noconfirm
}

is_installed() {
  "${PACMAN}" -Qq "$1" >/dev/null 2>&1
}

missing_packages() {
  local pkg
  for pkg in "$@"; do
    if ! is_installed "${pkg}"; then
      printf "%s\n" "${pkg}"
    fi
  done
}

install_group() {
  local label="$1"
  shift
  local packages=("$@")
  local missing=()
  local pkg

  mapfile -t missing < <(missing_packages "${packages[@]}")
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "${label}: todo instalado"
    return
  fi

  note "${label}: ${#missing[@]} paquetes pendientes"
  for pkg in "${missing[@]}"; do
    printf "    %s•%s %s\n" "${COLOR_BLUE}" "${COLOR_RESET}" "${pkg}"
  done

  with_spinner "Descargando e instalando ${label}" \
    ${SUDO} "${PACMAN}" -S --needed --noconfirm -- "${missing[@]}"
}

supports_brightnessctl() {
  local dev
  shopt -s nullglob
  for dev in /sys/class/backlight/*; do
    [[ -r "${dev}/brightness" && -r "${dev}/max_brightness" ]] || continue
    [[ "$(cat "${dev}/max_brightness" 2>/dev/null || echo 0)" -gt 0 ]] || continue
    return 0
  done
  return 1
}

has_amd_graphics() {
  local vendor
  shopt -s nullglob
  for vendor in /sys/class/drm/card*/device/vendor; do
    [[ -r "${vendor}" ]] || continue
    if [[ "$(cat "${vendor}")" == "0x1002" ]]; then
      return 0
    fi
  done

  if command -v lspci >/dev/null 2>&1; then
    lspci -nn | grep -Eiq 'VGA|3D|Display' && lspci -nn | grep -Eiq 'AMD|ATI'
    return $?
  fi

  return 1
}

configure_ddc_permissions() {
  if ! getent group i2c >/dev/null 2>&1; then
    with_spinner "Creando grupo i2c" ${SUDO} groupadd i2c
  fi

  if id -nG "${INSTALL_USER}" | tr ' ' '\n' | grep -qx i2c; then
    ok "${INSTALL_USER} ya pertenece al grupo i2c"
  else
    with_spinner "Anadiendo ${INSTALL_USER} al grupo i2c" ${SUDO} usermod -aG i2c "${INSTALL_USER}"
    warn "Cierra sesion y vuelve a entrar para activar el grupo i2c."
  fi
}

install_brightness_stack() {
  if supports_brightnessctl; then
    install_group "control de brillo interno" "${BRIGHTNESSCTL_PACKAGES[@]}"
  else
    install_group "control DDC/CI para monitores externos" "${DDC_PACKAGES[@]}"
    configure_ddc_permissions
  fi
}

install_amd_stack() {
  if has_amd_graphics; then
    install_group "graficos AMD" "${AMD_PACKAGES[@]}"
  else
    ok "Graficos AMD no detectados; se omite ese grupo"
  fi
}

install_yay() {
  if command -v yay >/dev/null 2>&1; then
    ok "yay ya esta instalado"
    return
  fi

  install_group "herramientas para compilar yay" "${YAY_BUILD_PACKAGES[@]}"

  local build_dir="/tmp/storm-yay-build-${INSTALL_USER}-$$"
  local pkg_file=""
  local build_cmd
  build_cmd='set -Eeuo pipefail
build_dir="$1"
rm -rf "$build_dir"
git clone https://aur.archlinux.org/yay.git "$build_dir"
cd "$build_dir"
makepkg -f --noconfirm'

  if [[ ${EUID} -eq 0 ]]; then
    rm -rf "${build_dir}"
    with_spinner "Compilando yay como ${INSTALL_USER}" \
      runuser -u "${INSTALL_USER}" -- bash -lc "${build_cmd}" _ "${build_dir}"
  else
    with_spinner "Compilando yay como ${INSTALL_USER}" \
      bash -lc "${build_cmd}" _ "${build_dir}"
  fi

  pkg_file="$(find "${build_dir}" -maxdepth 1 -type f -name 'yay-*.pkg.tar.*' | head -n 1)"
  [[ -n "${pkg_file}" ]] || fail "No se encontro el paquete compilado de yay."

  with_spinner "Instalando paquete yay compilado" \
    ${SUDO} "${PACMAN}" -U --noconfirm -- "${pkg_file}"
}

script_dir() {
  local source="${BASH_SOURCE[0]:-}"
  if [[ -n "${source}" && -f "${source}" ]]; then
    cd -- "$(dirname -- "${source}")" && pwd -P
  else
    return 1
  fi
}

run_as_install_user() {
  if [[ ${EUID} -eq 0 && "${INSTALL_USER}" != "root" ]]; then
    runuser -u "${INSTALL_USER}" -- "$@"
  else
    "$@"
  fi
}

copy_tree_contents() {
  local src="$1"
  local dst="$2"

  [[ -d "${src}" ]] || return 0
  mkdir -p "${dst}"
  cp -a "${src}/." "${dst}/"
  if [[ ${EUID} -eq 0 ]]; then
    chown -R "${INSTALL_USER}:${INSTALL_USER}" "${dst}"
  fi
}

install_dotfiles() {
  local source_dir=""
  local dir=""

  install_group "herramientas para descargar dotfiles" git

  if dir="$(script_dir 2>/dev/null)"; then
    if [[ -d "${dir}/config" || -d "${dir}/local" ]]; then
      source_dir="${dir}"
    fi
  fi

  if [[ -z "${source_dir}" ]]; then
    source_dir="/tmp/storm-dotfiles-${INSTALL_USER}-$$"
    rm -rf "${source_dir}"
    with_spinner "Descargando dotfiles" \
      run_as_install_user git clone --depth 1 "${DOTFILES_REPO}" "${source_dir}"
  fi

  with_spinner "Copiando config a ${INSTALL_HOME}/.config" \
    copy_tree_contents "${source_dir}/config" "${INSTALL_HOME}/.config"

  with_spinner "Copiando local a ${INSTALL_HOME}/.local" \
    copy_tree_contents "${source_dir}/local" "${INSTALL_HOME}/.local"

  if [[ -d "${INSTALL_HOME}/.local/bin" ]]; then
    chmod -R u+rx "${INSTALL_HOME}/.local/bin"
  fi
}

enable_services() {
  local services=(
    NetworkManager.service
    bluetooth.service
    rtkit-daemon.service
    power-profiles-daemon.service
  )
  local service

  for service in "${services[@]}"; do
    if systemctl list-unit-files "${service}" >/dev/null 2>&1; then
      with_spinner "Habilitando ${service}" ${SUDO} systemctl enable --now "${service}"
    fi
  done
}

post_install() {
  if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    if [[ ${EUID} -eq 0 && "${INSTALL_USER}" != "root" ]]; then
      with_spinner "Actualizando carpetas XDG de ${INSTALL_USER}" runuser -u "${INSTALL_USER}" -- xdg-user-dirs-update
    else
      with_spinner "Actualizando carpetas XDG del usuario" xdg-user-dirs-update
    fi
  fi
}

main() {
  title
  note "La salida de pacman/makepkg se oculta para mantener la animacion limpia."
  echo

  require_arch
  require_sudo
  sync_databases
  install_group "paquetes base" "${BASE_PACKAGES[@]}"
  install_yay
  install_brightness_stack
  install_amd_stack
  enable_services
  post_install
  install_dotfiles

  echo
  ok "Instalacion finalizada"
  note "Si se modificaron grupos de usuario, reinicia la sesion antes de probar DDC/CI."
}

main "$@"
