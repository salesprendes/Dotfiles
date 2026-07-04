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
WIRELESS_REGDOM_CONF=/etc/conf.d/wireless-regdom
NETWORKMANAGER_RESOLVED_CONF=/etc/NetworkManager/conf.d/10-dns-systemd-resolved.conf
RESOLV_CONF=/etc/resolv.conf
SYSTEMD_RESOLVED_STUB_RESOLV_CONF=../run/systemd/resolve/stub-resolv.conf

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

# --- Glifos según la capacidad del terminal (autónomo, sin parámetros) -----
# La consola de texto del kernel (TERM=linux) y los terminales "tontos" no
# tienen braille ni ✓/✗ en su fuente y los pintan como cuadros. Se detecta y
# se cae a ASCII automáticamente, para que el spinner y los símbolos se vean
# bien siempre, haya o no una fuente rica instalada.
supports_unicode() {
  case "${TERM:-}" in
    linux | dumb | "") return 1 ;;
  esac
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]8* | *[Uu][Tt][Ff]-8*) return 0 ;;
  esac
  return 1
}

if supports_unicode; then
  SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  MARK_OK="✓"; MARK_WARN="!"; MARK_FAIL="✗"; MARK_BULLET="•"
else
  SPINNER_FRAMES=('|' '/' '-' '\')
  MARK_OK="+"; MARK_WARN="!"; MARK_FAIL="x"; MARK_BULLET="*"
fi

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
# Línea de estado con símbolo. El \r inicial reaprovecha la línea del spinner
# (inofensivo fuera de él: ya estamos al inicio de la línea).
_status_line() { printf "\r  %s%s%s %s\n" "$1" "$2" "${COLOR_RESET}" "$3"; }
ok()   { _status_line "${COLOR_GREEN}"  "${MARK_OK}"   "$*"; }
warn() { _status_line "${COLOR_YELLOW}" "${MARK_WARN}" "$*"; }
fail() { _status_line "${COLOR_RED}"    "${MARK_FAIL}" "$*" >&2; exit 1; }

run_spinner() {
  local message="$1"
  local i=0

  trap 'exit 0' TERM INT
  trap - ERR
  set +e

  printf "\033[?25l"
  while true; do
    printf "\r  %s%s%s %s" "${COLOR_CYAN}" "${SPINNER_FRAMES[$i]}" "${COLOR_RESET}" "${message}"
    i=$(((i + 1) % ${#SPINNER_FRAMES[@]}))
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
    _status_line "${COLOR_GREEN}" "${MARK_OK}" "${message}"
  else
    _status_line "${COLOR_RED}" "${MARK_FAIL}" "${message}"
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
  run_as_install_user mktemp -d "/tmp/${SCRIPT_NAME}-${name}-${INSTALL_USER}.XXXXXX"
}

chown_install_user() {
  [[ ${EUID} -eq 0 ]] || return 0
  chown -R "${INSTALL_USER}:${INSTALL_USER}" "$@"
}

# --- Ayudantes comunes -----------------------------------------------------
# Sello de tiempo para los respaldos (.bak.AAAAMMDD-HHMMSS).
timestamp() { date +%Y%m%d-%H%M%S; }

# ¿Existe la unit de systemd (para poder omitirla si no está)?
service_exists() { systemctl list-unit-files "$1" 2>/dev/null | grep -q "$1"; }

# ¿Pertenece <usuario> al <grupo>?
user_in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }

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
    printf "    %s%s%s %s\n" "${COLOR_BLUE}" "${MARK_BULLET}" "${COLOR_RESET}" "${pkg}"
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

  if user_in_group "${INSTALL_USER}" i2c; then
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
# Dominio regulatorio Wi-Fi
# ---------------------------------------------------------------------------
normalize_regdom() {
  local code="${1:-}"
  code="${code%%#*}"
  code="${code//[[:space:]]/}"
  code="${code//\"/}"
  code="${code//\'/}"
  code="${code^^}"

  [[ "${code}" =~ ^([A-Z]{2}|00)$ ]] || return 1
  printf '%s\n' "${code}"
}

wireless_regdom_in_db() {
  local code
  code="$(normalize_regdom "${1:-}")" || return 1
  [[ -r "${WIRELESS_REGDOM_CONF}" ]] || return 1

  grep -Eq "^[[:space:]]*#?[[:space:]]*WIRELESS_REGDOM=[\"']?${code}[\"']?([[:space:]]*(#.*)?)?$" \
    "${WIRELESS_REGDOM_CONF}"
}

active_wireless_regdom() {
  [[ -r "${WIRELESS_REGDOM_CONF}" ]] || return 1

  local key value code
  while IFS='=' read -r key value; do
    key="${key//[[:space:]]/}"
    [[ "${key}" == "WIRELESS_REGDOM" ]] || continue
    code="$(normalize_regdom "${value}")" || continue
    printf '%s\n' "${code}"
    return 0
  done < "${WIRELESS_REGDOM_CONF}"

  return 1
}

regdom_from_locale_value() {
  local value="${1:-}" code
  value="${value//\"/}"
  value="${value//\'/}"
  value="${value%%.*}"
  value="${value%%@*}"

  [[ "${value}" =~ _([A-Za-z]{2})$ ]] || return 1
  code="$(normalize_regdom "${BASH_REMATCH[1]}")" || return 1
  wireless_regdom_in_db "${code}" || return 1
  printf '%s\n' "${code}"
}

detect_wireless_regdom_from_locale() {
  local key file value code
  local keys=(LC_ADDRESS LC_IDENTIFICATION LC_TIME LANG)
  local files=(/etc/locale.conf /etc/default/locale)

  for key in "${keys[@]}"; do
    for file in "${files[@]}"; do
      [[ -r "${file}" ]] || continue
      value="$(sed -n "s/^${key}=//p" "${file}" | tail -n1)"
      [[ -n "${value}" ]] || continue
      code="$(regdom_from_locale_value "${value}")" || continue
      printf '%s\n' "${code}"
      return 0
    done
  done

  return 1
}

system_timezone() {
  local target tz
  target="$(readlink -f /etc/localtime 2>/dev/null || true)"
  if [[ "${target}" == /usr/share/zoneinfo/* ]]; then
    tz="${target#/usr/share/zoneinfo/}"
    tz="${tz#posix/}"
    tz="${tz#right/}"
    [[ -n "${tz}" ]] && printf '%s\n' "${tz}" && return 0
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    tz="$(timedatectl show -P Timezone 2>/dev/null || true)"
    [[ -n "${tz}" ]] && printf '%s\n' "${tz}" && return 0
  fi

  return 1
}

detect_wireless_regdom_from_timezone() {
  local tz tab countries _coords zone _comments code
  tz="$(system_timezone)" || return 1

  for tab in /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab; do
    [[ -r "${tab}" ]] || continue
    while IFS=$'\t' read -r countries _coords zone _comments; do
      [[ -n "${countries}" && "${countries}" != \#* ]] || continue
      [[ "${zone}" == "${tz}" ]] || continue
      code="$(normalize_regdom "${countries%%,*}")" || continue
      wireless_regdom_in_db "${code}" || continue
      printf '%s\n' "${code}"
      return 0
    done < "${tab}"
  done

  return 1
}

detect_wireless_regdom() {
  local code

  if [[ -n "${WIRELESS_REGDOM:-}" ]]; then
    code="$(normalize_regdom "${WIRELESS_REGDOM}")" \
      && wireless_regdom_in_db "${code}" \
      && printf '%s\n' "${code}" \
      && return 0
  fi

  code="$(active_wireless_regdom 2>/dev/null || true)"
  if [[ -n "${code}" ]] && wireless_regdom_in_db "${code}"; then
    printf '%s\n' "${code}"
    return 0
  fi

  code="$(detect_wireless_regdom_from_locale 2>/dev/null || true)"
  if [[ -n "${code}" ]]; then
    printf '%s\n' "${code}"
    return 0
  fi

  code="$(detect_wireless_regdom_from_timezone 2>/dev/null || true)"
  if [[ -n "${code}" ]]; then
    printf '%s\n' "${code}"
    return 0
  fi

  return 1
}

write_wireless_regdom_config() {
  local regdom="$1" tmp
  tmp="$(mktemp "/tmp/${SCRIPT_NAME}-regdom.XXXXXX")"

  awk -v regdom="${regdom}" '
    BEGIN {
      target = "WIRELESS_REGDOM=\"" regdom "\""
      wrote = 0
    }
    /^[[:space:]]*#?[[:space:]]*WIRELESS_REGDOM=/ {
      if ($0 ~ "^[[:space:]]*#?[[:space:]]*WIRELESS_REGDOM=\"" regdom "\"([[:space:]]*(#.*)?)?$") {
        if (!wrote) {
          print target
          wrote = 1
        } else {
          print $0
        }
        next
      }
      if ($0 ~ "^[[:space:]]*WIRELESS_REGDOM=") {
        print "#" $0
        next
      }
    }
    { print }
    END {
      if (!wrote) {
        print target
      }
    }
  ' "${WIRELESS_REGDOM_CONF}" > "${tmp}"

  if cmp -s "${tmp}" "${WIRELESS_REGDOM_CONF}"; then
    ok "Dominio regulatorio Wi-Fi ya configurado (${regdom})"
  else
    with_spinner "Configurando dominio regulatorio Wi-Fi (${regdom})" \
      run_as_root install -m 644 "${tmp}" "${WIRELESS_REGDOM_CONF}"
  fi

  rm -f "${tmp}"
}

apply_wireless_regdom_now() {
  local regdom="$1"
  if ! command -v iw >/dev/null 2>&1; then
    warn "iw no está instalado; el dominio Wi-Fi se aplicará al cargar cfg80211."
    return 0
  fi

  if run_as_root iw reg set "${regdom}" >"${LOG_FILE:?}" 2>&1; then
    ok "Dominio regulatorio Wi-Fi aplicado en caliente (${regdom})"
  else
    warn "Dominio regulatorio Wi-Fi guardado (${regdom}), pero no se pudo aplicar en caliente."
    warn "Se aplicará al cargar cfg80211 o tras reiniciar."
  fi
}

configure_wireless_regdom() {
  if [[ ! -f "${WIRELESS_REGDOM_CONF}" ]]; then
    warn "${WIRELESS_REGDOM_CONF} no existe; se omite el dominio regulatorio Wi-Fi."
    return 0
  fi

  local regdom
  if ! regdom="$(detect_wireless_regdom)"; then
    warn "No se pudo detectar el país para Wi-Fi; edita ${WIRELESS_REGDOM_CONF} manualmente."
    return 0
  fi

  write_wireless_regdom_config "${regdom}"
  apply_wireless_regdom_now "${regdom}"
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
    local backup
    backup="${dst}.bak.$(timestamp)"
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
    backup="${dst}.bak.$(timestamp)"
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
  local services=(systemd-resolved.service NetworkManager.service bluetooth.service rtkit-daemon.service power-profiles-daemon.service upower.service systemd-homed.service)
  local service
  for service in "${services[@]}"; do
    if ! service_exists "${service}"; then
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

configure_systemd_resolved_dns() {
  if ! service_exists systemd-resolved.service; then
    note "systemd-resolved.service no está disponible; se omite DNS con systemd-resolved"
    return 0
  fi

  install_root_file "${NETWORKMANAGER_RESOLVED_CONF}" 644 \
    "DNS de NetworkManager con systemd-resolved" <<'NMDNSEOF'
[main]
dns=systemd-resolved
NMDNSEOF

  if [[ "$(readlink "${RESOLV_CONF}" 2>/dev/null || true)" == "${SYSTEMD_RESOLVED_STUB_RESOLV_CONF}" ]]; then
    ok "${RESOLV_CONF} ya apunta a systemd-resolved"
  else
    with_spinner "Apuntando ${RESOLV_CONF} a systemd-resolved" \
      run_as_root ln -sfn "${SYSTEMD_RESOLVED_STUB_RESOLV_CONF}" "${RESOLV_CONF}"
  fi

  if ! systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
    with_spinner "Arrancando systemd-resolved.service" \
      run_as_root systemctl start systemd-resolved.service
  fi

  if systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
    with_spinner "Reiniciando NetworkManager para aplicar DNS" \
      run_as_root systemctl restart NetworkManager.service
  else
    ok "NetworkManager aplicará DNS con systemd-resolved al iniciar"
  fi
}

post_install() {
  command -v xdg-user-dirs-update >/dev/null 2>&1 || return 0
  local system_lang
  system_lang="$(grep '^LANG=' /etc/locale.conf 2>/dev/null | cut -d= -f2 | tr -d '"')"
  local lang_env=()
  [[ -n "${system_lang}" ]] && lang_env=("LANG=${system_lang}")

  with_spinner "Actualizando carpetas XDG de ${INSTALL_USER}" \
    run_as_install_user env -u LC_ALL "${lang_env[@]}" xdg-user-dirs-update
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
    run_as_root cp -a "${cfg}" "${cfg}.bak.$(timestamp)"
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
  if user_in_group greeter video; then
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
# Hook de suspensión: re-enumera los HID de ASUS al reanudar
# ---------------------------------------------------------------------------
# Tras reanudar (s2idle), el firmware del teclado/ratón ROG puede restaurar
# estados HID latcheados en sus interfaces secundarias (Bloq Mayús fantasma
# en la interfaz NKRO, macros a medias...). Este hook de systemd-sleep
# re-enumera los dispositivos USB de ASUS en la fase "post" del ciclo de
# sueño: equivale a desenchufarlos y enchufarlos, sin tocar nada más.
SLEEP_HOOK_DST="/usr/lib/systemd/system-sleep/99-reset-asus-hid.sh"

# ¿Hay algún dispositivo USB de ASUS (idVendor 0b05) conectado?
has_asus_usb_hid() {
  (
    shopt -s nullglob
    local vendor
    for vendor in /sys/bus/usb/devices/*/idVendor; do
      [[ -r "${vendor}" ]] || continue
      [[ "$(cat "${vendor}" 2>/dev/null)" == "0b05" ]] && return 0
    done
    return 1
  )
}

install_sleep_hook() {
  if ! has_asus_usb_hid; then
    ok "Sin periféricos USB de ASUS; se omite el hook de reanudación"
    return 0
  fi
  local tmp
  tmp="$(mktemp "/tmp/${SCRIPT_NAME}-sleephook.XXXXXX")"
  cat > "${tmp}" <<'EOF'
#!/bin/sh
# Hook de systemd-sleep: tras reanudar (post), re-enumera los dispositivos
# USB de ASUS (0b05: teclado ROG Scope II y dongle del ratón Keris II).
# Equivale a desenchufar y enchufar: limpia estados HID latcheados
# (Bloq Mayús fantasma en interfaces secundarias, macros a medias, etc.)
# que el firmware restaura mal cuando la reanudación s2idle va "sucia".
[ "$1" = "post" ] || exit 0
for d in /sys/bus/usb/devices/*; do
    [ -f "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor")" = "0b05" ] || continue
    echo 0 > "$d/authorized" 2>/dev/null
    sleep 1
    echo 1 > "$d/authorized" 2>/dev/null
done
exit 0
EOF
  if [[ -f "${SLEEP_HOOK_DST}" ]] && cmp -s "${tmp}" "${SLEEP_HOOK_DST}"; then
    ok "Hook de reanudación ya instalado"
    rm -f "${tmp}"
    return 0
  fi
  with_spinner "Instalando hook de reanudación (${SLEEP_HOOK_DST})" \
    run_as_root install -m 755 "${tmp}" "${SLEEP_HOOK_DST}"
  rm -f "${tmp}"
}

# ---------------------------------------------------------------------------
# Ajustes de sistema (inspirados en Omarchy)
# ---------------------------------------------------------------------------
# Instala un archivo de sistema desde stdin si no existe o cambió (idempotente).
#   uso: install_root_file <destino> <modo> <etiqueta> <<'EOF' ... EOF
install_root_file() {
  local dst="$1" mode="$2" label="$3" tmp
  tmp="$(mktemp "/tmp/${SCRIPT_NAME}-rootfile.XXXXXX")"
  cat > "${tmp}"
  if [[ -f "${dst}" ]] && cmp -s "${tmp}" "${dst}"; then
    ok "${label}: ya instalado"
  else
    with_spinner "Instalando ${label}" \
      run_as_root install -D -m "${mode}" "${tmp}" "${dst}"
  fi
  rm -f "${tmp}"
}

# El autosuspend USB (2 s por defecto) duerme periféricos HID que luego
# despiertan con estados corruptos. usbcore va compilado en el kernel de
# Arch, así que el clásico "options usbcore autosuspend=-1" de modprobe.d
# NO aplica: se usa una regla udev por dispositivo, que sí funciona siempre.
disable_usb_autosuspend() {
  install_root_file /etc/udev/rules.d/50-usb-no-autosuspend.rules 644 \
    "regla udev anti-autosuspend USB" <<'UDEVEOF'
# Desactiva el autosuspend USB por dispositivo. En este kernel usbcore va
# compilado (built-in), así que "options usbcore autosuspend=-1" en
# modprobe.d NO aplica; esta regla udev cubre cada dispositivo al aparecer.
# Evita periféricos HID que se duermen y despiertan con estados corruptos.
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
UDEVEOF
  run_as_root udevadm control --reload 2>/dev/null || true
  # La regla solo cubre dispositivos que aparezcan a partir de ahora;
  # esto la aplica también a los ya conectados.
  run_as_root sh -c 'for c in /sys/bus/usb/devices/*/power/control; do echo on > "$c" 2>/dev/null || true; done'
}

# Los demonios FUSE de gvfs (Nautilus) pueden bloquear la congelación del
# kernel y hacer que la suspensión falle en silencio. Hook de Omarchy:
# desmonta antes de dormir y reinicia gvfs al despertar.
install_fuse_sleep_hook() {
  if ! is_installed gvfs; then
    ok "gvfs no instalado; se omite el hook FUSE de suspensión"
    return 0
  fi
  install_root_file /usr/lib/systemd/system-sleep/unmount-fuse 755 \
    "hook FUSE de suspensión (gvfs)" <<'FUSEEOF'
#!/bin/bash

# Lazy-unmount gvfsd-fuse filesystems before suspend/hibernate to prevent the
# kernel's process freeze from timing out. FUSE daemons (like gvfsd-fuse from
# Nautilus) can block in uninterruptible sleep during freeze, causing suspend
# to silently fail. After wake, restart gvfs so the FUSE mount is restored.

if [[ $1 == "pre" ]]; then
  while IFS=' ' read -r _ mountpoint fstype _; do
    if [[ $fstype == fuse.gvfsd-fuse ]]; then
      mountpoint=$(printf '%b' "$mountpoint")
      fusermount3 -uz "$mountpoint" 2>/dev/null || fusermount -uz "$mountpoint" 2>/dev/null || true
    fi
  done < /proc/mounts
fi

if [[ $1 == "post" ]]; then
  # Run in background — user.slice is still frozen at this point, so a
  # synchronous restart would block the thaw for up to 90 seconds.
  (
    sleep 5
    for uid_dir in /run/user/*; do
      uid=$(basename "$uid_dir")
      if [[ -S $uid_dir/bus ]]; then
        sudo -u "#$uid" env \
          DBUS_SESSION_BUS_ADDRESS="unix:path=$uid_dir/bus" \
          XDG_RUNTIME_DIR="$uid_dir" \
          systemctl --user restart gvfs-daemon.service 2>/dev/null || true
      fi
    done
  ) &
fi
FUSEEOF
}

# systemd espera 90 s a cada servicio colgado al apagar; con 5 s el
# apagado es casi instantáneo (mismos valores que usa Omarchy).
configure_fast_shutdown() {
  install_root_file /etc/systemd/system.conf.d/10-faster-shutdown.conf 644 \
    "apagado rápido (sistema)" <<'SHUTEOF'
[Manager]
DefaultTimeoutStopSec=5s
SHUTEOF
  install_root_file /etc/systemd/system/user@.service.d/faster-shutdown.conf 644 \
    "apagado rápido (sesión de usuario)" <<'USEREOF'
[Service]
TimeoutStopSec=5s
USEREOF
  run_as_root systemctl daemon-reload
}

apply_system_tweaks() {
  disable_usb_autosuspend
  install_fuse_sleep_hook
  configure_fast_shutdown
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
  configure_wireless_regdom
  install_brightness_stack
  install_amd_stack
  enable_services
  configure_systemd_resolved_dns
  post_install
  install_dotfiles
  setup_greetd
  install_sleep_hook
  apply_system_tweaks
  set_default_shell

  echo
  ok "Instalación finalizada"
  note "Si se modificaron grupos de usuario, reinicia la sesión antes de probar DDC/CI."
}

main "$@"
