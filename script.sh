#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=salesprendes

BASE_PACKAGES=(linux-firmware quickshell qt6-declarative hyprland ttf-jetbrains-mono-nerd cliphist wl-clipboard hyprlock polkit hyprpolkitagent curl procps-ng nano networkmanager bluez bluez-utils pipewire wireplumber pipewire-pulse playerctl upower rtkit hypridle power-profiles-daemon xdg-user-dirs hyprshot net-tools imv)

# Nota: libva-mesa-driver y lib32-libva-mesa-driver ya no existen como paquetes
# independientes; sus drivers VA-API van incluidos en mesa / lib32-mesa.
AMD_PACKAGES=(mesa vulkan-radeon mesa-utils vulkan-tools libva-utils lib32-mesa lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver)

YAY_BUILD_PACKAGES=(base-devel git)
BRIGHTNESSCTL_PACKAGES=(brightnessctl)
DDC_PACKAGES=(ddcutil)

# --- Valores por defecto (entorno) -----------------------------------------
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/salesprendes/Dotfiles.git}"
WALLPAPERS_REPO="${WALLPAPERS_REPO:-https://github.com/D3Ext/aesthetic-wallpapers.git}"
PACMAN="${PACMAN:-pacman}"
SUDO="${SUDO:-sudo}"
INSTALL_USER="${SUDO_USER:-${USER:-}}"

# --- Asegurar una locale UTF-8 para que los acentos se vean bien (#10) -----
if ! locale 2>/dev/null | grep -qi 'utf-?8'; then
  export LC_ALL=C.UTF-8
fi

COLOR_RESET=$'\033[0m'
COLOR_DIM=$'\033[2m'
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'
COLOR_CYAN=$'\033[36m'
COLOR_BOLD=$'\033[1m'

# Estado interno.
LOG_FILE=""
INSTALL_HOME=""
INSTALLED_CACHE_LOADED=0
declare -A INSTALLED_PACKAGES=()

# ---------------------------------------------------------------------------
# Spinner, traps y logging
# ---------------------------------------------------------------------------
spinner_pid=""

_stop_spinner() {
  if [[ -n "${spinner_pid}" ]]; then
    kill "${spinner_pid}" 2>/dev/null || true
    wait "${spinner_pid}" 2>/dev/null || true
    spinner_pid=""
  fi
}

cleanup() {
  _stop_spinner
  printf "\033[?25h" || true
}
trap cleanup EXIT

on_error() {
  cleanup
  echo
  printf "%sError en la línea %s.%s\n" "${COLOR_RED}" "$1" "${COLOR_RESET}" >&2
}
trap 'on_error "$LINENO"' ERR

on_interrupt() {
  cleanup
  echo
  warn "Cancelado por el usuario."
  exit 130
}
trap on_interrupt INT

title() {
  clear
  printf "%s" "${COLOR_CYAN}${COLOR_BOLD}"
  cat <<'BANNER'

  ███████╗ █████╗ ██╗     ███████╗███████╗██████╗ ██████╗ ███████╗███╗   ██╗██████╗ ███████╗███████╗
  ██╔════╝██╔══██╗██║     ██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔════╝
  ███████╗███████║██║     █████╗  ███████╗██████╔╝██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ███████╗
  ╚════██║██╔══██║██║     ██╔══╝  ╚════██║██╔═══╝ ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ╚════██║
  ███████║██║  ██║███████╗███████╗███████║██║     ██║  ██║███████╗██║ ╚████║██████╔╝███████╗███████║
  ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚══════╝

BANNER
  printf "%s" "${COLOR_RESET}"
  printf "  Instalador de paquetes para Arch Linux\n\n"
}

note() { printf "%s%s%s\n" "${COLOR_DIM}" "$*" "${COLOR_RESET}"; }
ok()   { printf "  %s✓%s %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$*"; }
warn() { printf "  %s!%s %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$*"; }
fail() { printf "  %s✗%s %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2; exit 1; }

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

# Ejecuta un comando con spinner. En fallo muestra la cola del log (#2).
with_spinner() {
  local message="$1"
  shift
  local status=0

  run_spinner "${message}" &
  spinner_pid=$!

  "$@" >"${LOG_FILE:?}" 2>&1 || status=$?
  _stop_spinner

  if [[ ${status} -eq 0 ]]; then
    printf "\r  %s✓%s %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "${message}"
  else
    printf "\r  %s✗%s %s\n" "${COLOR_RED}" "${COLOR_RESET}" "${message}"
    note "Últimas líneas del log (${LOG_FILE}):"
    tail -n 30 "${LOG_FILE}" >&2 || true
    return "${status}"
  fi
}

# ---------------------------------------------------------------------------
# Validaciones iniciales
# ---------------------------------------------------------------------------
require_arch() {
  [[ -f /etc/arch-release ]] || fail "Este instalador está pensado para Arch Linux."
  command -v "${PACMAN}" >/dev/null 2>&1 || fail "No se encontró pacman."
}

validate_user() {  # (#9)
  [[ -n "${INSTALL_USER}" ]] || fail "No se pudo determinar el usuario destino."
  getent passwd "${INSTALL_USER}" >/dev/null 2>&1 \
    || fail "El usuario '${INSTALL_USER}' no existe."
}

require_sudo() {
  if [[ -n "${SUDO}" ]]; then
    "${SUDO}" -k
    "${SUDO}" -p "  Se requiere sudo. Contraseña: " true
    ok "Privilegios de administrador preparados"
  fi
}

run_as_root() {
  if [[ -n "${SUDO}" ]]; then
    "${SUDO}" "$@"
  else
    "$@"
  fi
}

make_temp_dir() {
  local name="$1"
  if [[ ${EUID} -eq 0 && "${INSTALL_USER}" != "root" ]]; then
    runuser -u "${INSTALL_USER}" -- mktemp -d "/tmp/${SCRIPT_NAME}-${name}-${INSTALL_USER}.XXXXXX"
  else
    mktemp -d "/tmp/${SCRIPT_NAME}-${name}-${INSTALL_USER}.XXXXXX"
  fi
}

chown_install_user() {
  [[ ${EUID} -eq 0 ]] || return 0
  chown -R "${INSTALL_USER}:${INSTALL_USER}" "$@"
}

# ---------------------------------------------------------------------------
# Cache de paquetes instalados (#8): una sola consulta a pacman.
# ---------------------------------------------------------------------------
load_installed_cache() {
  INSTALLED_PACKAGES=()
  local pkg
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] && INSTALLED_PACKAGES["${pkg}"]=1
  done < <("${PACMAN}" -Qq 2>/dev/null || true)
  INSTALLED_CACHE_LOADED=1
}

is_installed() {
  [[ ${INSTALLED_CACHE_LOADED} -eq 1 ]] || load_installed_cache
  [[ ${INSTALLED_PACKAGES[$1]+_} ]]
}

missing_packages() {
  [[ ${INSTALLED_CACHE_LOADED} -eq 1 ]] || load_installed_cache
  local pkg
  for pkg in "$@"; do
    is_installed "${pkg}" || printf "%s\n" "${pkg}"
  done
}

# ---------------------------------------------------------------------------
# Instalación
# ---------------------------------------------------------------------------
sync_databases() {
  with_spinner "Actualizando sistema y bases de datos de paquetes (-Syu)" \
    run_as_root "${PACMAN}" -Syu --noconfirm
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

  note "${label}: ${#missing[@]} paquete(s) pendiente(s)"
  for pkg in "${missing[@]}"; do
    printf "    %s•%s %s\n" "${COLOR_BLUE}" "${COLOR_RESET}" "${pkg}"
  done

  with_spinner "Descargando e instalando ${label}" \
    run_as_root "${PACMAN}" -S --needed --noconfirm -- "${missing[@]}"

  load_installed_cache
}

# ---------------------------------------------------------------------------
# Detección de hardware (nullglob confinado a un subshell: #4)
# ---------------------------------------------------------------------------
supports_brightnessctl() {
  (
    shopt -s nullglob
    local dev
    for dev in /sys/class/backlight/*; do
      [[ -r "${dev}/brightness" && -r "${dev}/max_brightness" ]] || continue
      [[ "$(cat "${dev}/max_brightness" 2>/dev/null)" -gt 0 ]] || continue
      return 0
    done
    return 1
  )
}

has_amd_graphics() {
  (
    shopt -s nullglob
    local vendor
    for vendor in /sys/class/drm/card*/device/vendor; do
      [[ -r "${vendor}" ]] || continue
      [[ "$(cat "${vendor}")" == "0x1002" ]] && return 0
    done

    if command -v lspci >/dev/null 2>&1; then
      lspci -nn | grep -Ei 'VGA|3D|Display' | grep -qi 'AMD|ATI' && return 0
    fi

    return 1
  )
}

configure_ddc_permissions() {
  if ! getent group i2c >/dev/null 2>&1; then
    with_spinner "Creando grupo i2c" run_as_root groupadd i2c
  fi

  if id -nG "${INSTALL_USER}" | tr ' ' '\n' | grep -qx i2c; then
    ok "${INSTALL_USER} ya pertenece al grupo i2c"
  else
    with_spinner "Añadiendo ${INSTALL_USER} al grupo i2c" \
      run_as_root usermod -aG i2c "${INSTALL_USER}"
    warn "Cierra sesión y vuelve a entrar para activar el grupo i2c."
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
    install_group "gráficos AMD" "${AMD_PACKAGES[@]}"
  else
    ok "Gráficos AMD no detectados; se omite ese grupo"
  fi
}

# ---------------------------------------------------------------------------
# yay (build script en fichero temporal en vez de cadena: #14)
# ---------------------------------------------------------------------------
install_yay() {
  if command -v yay >/dev/null 2>&1; then
    ok "yay ya está instalado"
    return
  fi

  install_group "herramientas para compilar yay" "${YAY_BUILD_PACKAGES[@]}"

  local build_dir
  local build_script
  build_dir="$(make_temp_dir yay-build)"
  build_script="$(mktemp)"
  chmod 755 "${build_script}"

  cat > "${build_script}" <<'BUILD'
set -Eeuo pipefail
build_dir="$1"
rm -rf "$build_dir"
git clone https://aur.archlinux.org/yay.git "$build_dir"
cd "$build_dir"
makepkg -f --noconfirm
BUILD

  if [[ ${EUID} -eq 0 ]]; then
    rm -rf "${build_dir}"
    with_spinner "Compilando yay como ${INSTALL_USER}" \
      runuser -u "${INSTALL_USER}" -- bash "${build_script}" _ "${build_dir}"
  else
    with_spinner "Compilando yay como ${INSTALL_USER}" \
      bash "${build_script}" _ "${build_dir}"
  fi

  rm -f "${build_script}"

  local pkg_file
  pkg_file="$(find "${build_dir}" -maxdepth 1 -type f -name 'yay-*.pkg.tar.*' | head -n 1)"
  [[ -n "${pkg_file}" ]] || fail "No se encontró el paquete compilado de yay."

  with_spinner "Instalando paquete yay compilado" \
    run_as_root "${PACMAN}" -U --noconfirm -- "${pkg_file}"

  rm -rf "${build_dir}"
}

# ---------------------------------------------------------------------------
# Dotfiles
# ---------------------------------------------------------------------------
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

# Copia un árbol; respalda SOLO los ficheros que se sobreescribirían (#6).
copy_tree_contents() {
  local src="$1" dst="$2"

  [[ -d "${src}" ]] || return 0
  mkdir -p "${dst}"

  local conflicts=()
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#./}"
    [[ -e "${dst}/${rel}" ]] && conflicts+=("${rel}")
  done < <(cd "${src}" && find . -type f -print0)

  if [[ ${#conflicts[@]} -gt 0 ]]; then
    local stamp backup
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="${dst}.bak.${stamp}"
    mkdir -p "${backup}"
    local c
    for c in "${conflicts[@]}"; do
      mkdir -p "${backup}/$(dirname -- "${c}")"
      mv -- "${dst}/${c}" "${backup}/${c}"
    done
    warn "${#conflicts[@]} fichero(s) existente(s) respaldado(s) en ${backup}"
  fi

  cp -a "${src}/." "${dst}/"
  chown_install_user "${dst}"
}

install_dotfiles() {
  local source_dir="" dir="" cleanup_source=0

  install_group "herramientas para descargar dotfiles" git

  if dir="$(script_dir 2>/dev/null)"; then
    if [[ -d "${dir}/config" || -d "${dir}/local" ]]; then
      source_dir="${dir}"
    fi
  fi

  if [[ -z "${source_dir}" ]]; then
    source_dir="$(make_temp_dir dotfiles)"
    cleanup_source=1
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

  if [[ ${cleanup_source} -eq 1 ]]; then
    rm -rf "${source_dir}"
  fi
}

# ---------------------------------------------------------------------------
# Servicios (#1)
# ---------------------------------------------------------------------------
enable_services() {
  local services=(NetworkManager.service bluetooth.service rtkit-daemon.service power-profiles-daemon.service)
  local service
  for service in "${services[@]}"; do
    if ! systemctl list-unit-files "${service}" 2>/dev/null | grep -q "${service}"; then
      note "${service} no está disponible; se omite"
      continue
    fi
    if systemctl is-enabled --quiet "${service}" 2>/dev/null; then
      ok "${service} ya habilitado"
      continue
    fi
    with_spinner "Habilitando ${service}" \
      run_as_root systemctl enable --now "${service}"
  done
}

post_install() {
  command -v xdg-user-dirs-update >/dev/null 2>&1 || return 0
  if [[ ${EUID} -eq 0 && "${INSTALL_USER}" != "root" ]]; then
    with_spinner "Actualizando carpetas XDG de ${INSTALL_USER}" \
      runuser -u "${INSTALL_USER}" -- xdg-user-dirs-update
  else
    with_spinner "Actualizando carpetas XDG del usuario" xdg-user-dirs-update
  fi
}

# ---------------------------------------------------------------------------
# Fondos de pantalla (se ejecuta DESPUÉS de generar las carpetas XDG)
# ---------------------------------------------------------------------------
# Copia las imágenes (sin sobrescribir las existentes) y, si se ejecuta como
# root, ajusta la propiedad al usuario destino.
copy_wallpapers() {
  local src="$1" dst="$2"
  local file name copied=0 skipped=0

  [[ -d "${src}" ]] || { warn "No se encontró ${src}"; return 0; }
  mkdir -p "${dst}"

  while IFS= read -r -d '' file; do
    name="$(basename -- "${file}")"
    if [[ -e "${dst}/${name}" ]]; then
      ((skipped += 1))
      continue
    fi
    cp -p -- "${file}" "${dst}/"
    ((copied += 1))
  done < <(find "${src}" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
       -o -iname '*.webp' -o -iname '*.gif' \) -print0)

  chown_install_user "${dst}"
  ok "Fondos copiados: ${copied}; ya existentes: ${skipped}"
}

install_wallpapers() {
  local pics wall_dir tmp

  # Carpeta de imágenes XDG (localizada: ~/Imágenes, ~/Images, ~/Pictures…).
  # post_install ya ejecutó xdg-user-dirs-update, así que xdg-user-dir resuelve
  # la ruta correcta para el idioma del sistema.
  pics="$(run_as_install_user env HOME="${INSTALL_HOME}" xdg-user-dir PICTURES 2>/dev/null || true)"
  [[ -n "${pics}" ]] || pics="${INSTALL_HOME}/Pictures"
  wall_dir="${pics}/Wallpapers"

  # Crear la carpeta Wallpapers si no existe.
  if [[ -d "${wall_dir}" ]]; then
    ok "Carpeta de fondos ya existe: ${wall_dir}"
  else
    run_as_install_user mkdir -p "${wall_dir}"
    ok "Creada carpeta de fondos: ${wall_dir}"
  fi

  command -v git >/dev/null 2>&1 || install_group "git para descargar fondos" git

  tmp="$(make_temp_dir wallpapers)"

  # Best-effort: si falla la descarga, se avisa pero no se aborta la instalación.
  if ! with_spinner "Descargando fondos (aesthetic-wallpapers)" \
        run_as_install_user git clone --depth 1 "${WALLPAPERS_REPO}" "${tmp}"; then
    warn "No se pudieron descargar los fondos; se continúa."
    rm -rf "${tmp}"
    return 0
  fi

  with_spinner "Copiando fondos a ${wall_dir}" \
    copy_wallpapers "${tmp}/images" "${wall_dir}"

  rm -rf "${tmp}"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  if [[ -z "${INSTALL_USER}" ]]; then
    INSTALL_USER="$(id -un)"
  fi

  if [[ ${EUID} -eq 0 ]]; then
    SUDO=""
  fi

  validate_user

  INSTALL_HOME="$(getent passwd "${INSTALL_USER}" | cut -d: -f6)"
  if [[ -z "${INSTALL_HOME}" ]]; then
    INSTALL_HOME="${HOME}"
  fi

  LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME}-install-${INSTALL_USER}-$$.log}"
  : > "${LOG_FILE}"

  title
  note "La salida de pacman/makepkg se oculta para mantener la animación limpia."
  note "Log completo: ${LOG_FILE}"
  echo

  require_arch
  require_sudo

  load_installed_cache
  sync_databases
  install_group "paquetes base" "${BASE_PACKAGES[@]}"
  install_yay
  install_brightness_stack
  install_amd_stack
  enable_services
  post_install
  install_wallpapers
  install_dotfiles

  echo
  ok "Instalación finalizada"
  note "Si se modificaron grupos de usuario, reinicia la sesión antes de probar DDC/CI."
}

main "$@"
