#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=salesprendes

BASE_PACKAGES=(base-devel git linux-firmware quickshell qt6-declarative hyprland ttf-jetbrains-mono-nerd cliphist wl-clipboard hyprlock polkit hyprpolkitagent procps-ng nano networkmanager bluez bluez-utils pipewire wireplumber pipewire-pulse playerctl upower rtkit hypridle power-profiles-daemon xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xdg-user-dirs hyprshot net-tools imv wireless-regdb nautilus kitty zsh zsh-autosuggestions zsh-syntax-highlighting starship fastfetch uwsm)
AMD_PACKAGES=(mesa vulkan-radeon mesa-utils vulkan-tools libva-utils lib32-mesa lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver)

BRIGHTNESSCTL_PACKAGES=(brightnessctl)
DDC_PACKAGES=(ddcutil)
GREETD_PACKAGES=(greetd cage)

# --- Valores por defecto (entorno) -----------------------------------------
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/salesprendes/Dotfiles.git}"
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
    command -v "${SUDO}" >/dev/null 2>&1 || fail "No se encontró sudo."
    if ! "${SUDO}" -v -p "  Se requiere sudo. Contraseña: "; then
      fail "No se pudo validar sudo. Ejecuta el script con un usuario con permisos sudo o usa: sudo ./script.sh"
    fi
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

# Carpeta de imágenes del usuario según xdg-user-dirs (XDG_PICTURES_DIR),
# expandiendo $HOME al home del usuario destino.
user_pictures_dir() {
  local conf="${INSTALL_HOME}/.config/user-dirs.dirs" dir=""
  if [[ -f "${conf}" ]]; then
    dir="$(sed -n 's/^XDG_PICTURES_DIR="\(.*\)"$/\1/p' "${conf}" | head -n1)"
    dir="${dir//\$HOME/${INSTALL_HOME}}"
  fi
  [[ -n "${dir}" ]] || dir="${INSTALL_HOME}/Imágenes"
  printf '%s\n' "${dir}"
}

# Copia un fichero suelto al home respaldando el existente (#6) y ajustando dueño.
install_home_file() {
  local src="$1" dst="$2"

  [[ -f "${src}" ]] || return 0

  if [[ -e "${dst}" ]]; then
    local backup
    backup="${dst}.bak.$(date +%Y%m%d-%H%M%S)"
    mv -- "${dst}" "${backup}"
    warn "Respaldado ${dst} en ${backup}"
  fi

  cp -a "${src}" "${dst}"
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

  # Wallpapers del repo → carpeta de imágenes del usuario (xdg-user-dirs).
  if [[ -d "${source_dir}/Wallpapers" ]]; then
    local pictures
    pictures="$(user_pictures_dir)"
    with_spinner "Copiando Wallpapers a ${pictures}/Wallpapers" \
      copy_tree_contents "${source_dir}/Wallpapers" "${pictures}/Wallpapers"
  fi

  # .zshrc: el repo lo guarda como 'zshrc' (sin punto) en la raíz.
  if [[ -f "${source_dir}/zshrc" ]]; then
    with_spinner "Copiando .zshrc a ${INSTALL_HOME}/.zshrc" \
      install_home_file "${source_dir}/zshrc" "${INSTALL_HOME}/.zshrc"
  fi

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
  local system_lang
  system_lang="$(grep '^LANG=' /etc/locale.conf 2>/dev/null | cut -d= -f2 | tr -d '"')"
  local lang_env=()
  [[ -n "${system_lang}" ]] && lang_env=("LANG=${system_lang}")

  if [[ ${EUID} -eq 0 && "${INSTALL_USER}" != "root" ]]; then
    with_spinner "Actualizando carpetas XDG de ${INSTALL_USER}" \
      runuser -u "${INSTALL_USER}" -- env -u LC_ALL "${lang_env[@]}" xdg-user-dirs-update
  else
    with_spinner "Actualizando carpetas XDG del usuario" env -u LC_ALL "${lang_env[@]}" xdg-user-dirs-update
  fi
}

# ---------------------------------------------------------------------------
# Shell por defecto: zsh
# ---------------------------------------------------------------------------
set_default_shell() {
  local zsh_bin
  zsh_bin="$(command -v zsh 2>/dev/null || true)"
  if [[ -z "${zsh_bin}" ]]; then
    warn "zsh no está instalado; se omite el cambio de shell"
    return 0
  fi

  # chsh solo acepta shells que figuren en /etc/shells.
  if ! grep -qxF "${zsh_bin}" /etc/shells 2>/dev/null; then
    if printf '%s\n' "${zsh_bin}" | run_as_root tee -a /etc/shells >/dev/null; then
      ok "Registrado ${zsh_bin} en /etc/shells"
    fi
  fi

  local current
  current="$(getent passwd "${INSTALL_USER}" | cut -d: -f7)"
  if [[ "${current}" == "${zsh_bin}" ]]; then
    ok "zsh ya es el shell por defecto de ${INSTALL_USER}"
    return 0
  fi

  with_spinner "Estableciendo zsh como shell por defecto de ${INSTALL_USER}" \
    run_as_root chsh -s "${zsh_bin}" "${INSTALL_USER}"
  note "El nuevo shell se aplicará en el próximo inicio de sesión."
}

# ---------------------------------------------------------------------------
# greetd: pantalla de login (cage + quickshell)
# ---------------------------------------------------------------------------
GREETD_THEME_DST=/etc/greetd/quickshell
# cage no soporta wlr-layer-shell (el tema usa FloatingWindow) y sin la
# variable Qt dibujaría barra de título en la ventana del greeter. La
# redirección silencia los logs de cage/quickshell, que greetd volcaría
# a la consola VT1 y se verían un instante al arrancar.
GREETD_COMMAND='cage -s -- env QT_WAYLAND_DISABLE_WINDOWDECORATION=1 qs -p /etc/greetd/quickshell >/dev/null 2>&1'

# Copia el módulo Greeter (desde la config recién instalada del usuario) y
# genera el shell.qml raíz que quickshell exige en la raíz de su config.
deploy_greetd_theme() {
  local src="$1"
  run_as_root mkdir -p "${GREETD_THEME_DST}/Modules"
  run_as_root rm -rf "${GREETD_THEME_DST}/Modules/Greeter"
  run_as_root cp -r "${src}" "${GREETD_THEME_DST}/Modules/Greeter"
  run_as_root tee "${GREETD_THEME_DST}/shell.qml" >/dev/null <<'EOF'
//  shell.qml — punto de entrada que Quickshell busca en la raíz de la
//  config. Solo instancia el Greeter. (Generado por script.sh)
import Quickshell
import qs.Modules.Greeter

ShellRoot {
    Greeter {}
}
EOF
  run_as_root chmod -R a+rX "${GREETD_THEME_DST}"
}

configure_greetd_session() {
  local cfg=/etc/greetd/config.toml
  if [[ -f "${cfg}" ]]; then
    run_as_root cp -a "${cfg}" "${cfg}.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  run_as_root tee "${cfg}" >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "${GREETD_COMMAND}"
user = "greeter"
EOF
}

# Fondo del greeter: el tema espera /etc/greetd/wall.png legible por el
# usuario 'greeter'. Se toma el wallpaper actual de quickshell si existe.
install_greeter_wallpaper() {
  local dst=/etc/greetd/wall.png
  if [[ -f "${dst}" ]]; then
    ok "Fondo del greeter ya presente"
    return 0
  fi

  local settings="${INSTALL_HOME}/.config/quickshell/settings.json" src=""
  if [[ -f "${settings}" ]]; then
    src="$(sed -n 's/.*"wallpaperCurrent"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${settings}" | head -n1)"
  fi
  # Sin settings o con ruta rota → el fondo por defecto de los Wallpapers
  # del repo (los copia install_dotfiles a la carpeta de imágenes).
  if [[ -z "${src}" || ! -f "${src}" ]]; then
    src="$(user_pictures_dir)/Wallpapers/kitty.png"
  fi

  if [[ -n "${src}" && -f "${src}" ]]; then
    with_spinner "Copiando fondo del greeter desde ${src}" \
      run_as_root install -m 644 "${src}" "${dst}"
  else
    warn "No se encontró wallpaper; el greeter saldrá sin fondo."
    warn "Copia una imagen a ${dst} (legible por todos) cuando quieras."
  fi
}

# Estado del greeter (recuerda el último usuario) + permisos del usuario
# 'greeter' que crea el paquete greetd.
prepare_greeter_runtime() {
  if ! getent passwd greeter >/dev/null 2>&1; then
    warn "El usuario 'greeter' no existe (¿falló la instalación de greetd?)"
    return 0
  fi
  run_as_root mkdir -p /var/lib/greeter
  run_as_root chown greeter:greeter /var/lib/greeter
  if id -nG greeter | tr ' ' '\n' | grep -qx video; then
    ok "greeter ya pertenece al grupo video"
  else
    with_spinner "Añadiendo greeter al grupo video" \
      run_as_root usermod -aG video greeter
  fi
}

enable_greetd_service() {
  if systemctl is-enabled --quiet greetd.service 2>/dev/null; then
    ok "greetd.service ya habilitado"
    return 0
  fi
  # display-manager.service es el symlink que comparten todos los gestores
  # de login: si apunta a otro (sddm, gdm...), no se pisa.
  if [[ -e /etc/systemd/system/display-manager.service ]]; then
    warn "Hay otro gestor de login habilitado; deshabilítalo y ejecuta:"
    warn "  sudo systemctl enable greetd.service"
    return 0
  fi
  # Sin --now: activarlo en caliente cortaría la sesión actual.
  with_spinner "Habilitando greetd.service (activo tras reiniciar)" \
    run_as_root systemctl enable greetd.service
}

setup_greetd() {
  install_group "greetd (pantalla de login)" "${GREETD_PACKAGES[@]}"

  local theme_src="${INSTALL_HOME}/.config/quickshell/Modules/Greeter"
  if [[ ! -d "${theme_src}" ]]; then
    warn "No se encontró el tema del greeter en ${theme_src}; se omite greetd."
    return 0
  fi

  with_spinner "Desplegando tema del greeter en ${GREETD_THEME_DST}" \
    deploy_greetd_theme "${theme_src}"

  if [[ -f /etc/greetd/config.toml ]] \
      && grep -qF "${GREETD_COMMAND}" /etc/greetd/config.toml; then
    ok "config.toml de greetd ya configurado"
  else
    with_spinner "Escribiendo /etc/greetd/config.toml" \
      configure_greetd_session
  fi
  install_greeter_wallpaper
  prepare_greeter_runtime
  enable_greetd_service
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
  install_brightness_stack
  install_amd_stack
  enable_services
  post_install
  install_dotfiles
  setup_greetd
  set_default_shell

  echo
  ok "Instalación finalizada"
  note "Si se modificaron grupos de usuario, reinicia la sesión antes de probar DDC/CI."
}

main "$@"
