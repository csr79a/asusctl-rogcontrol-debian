#!/usr/bin/env bash
#
# setup-asusctl-rogcontrol.sh — Instalador de asusctl csr79a
#
# Instala asusctl + rog-control-center (compilados desde código fuente, vía
# checkinstall) en Debian y derivados (Debian 13/trixie o posterior, KDE
# Plasma).
#
# NO instala Cardwire ni supergfxctl: ambos proyectos quedaron descartados.
# Cardwire seguía en beta y llegó a dar conflictos de paquetes.
#
# Todo lo instalado queda registrado en dpkg (checkinstall para asusctl),
# así que se puede revertir limpiamente con uninstall-asusctl-rogcontrol.sh.
#
# Interfaz por pantallas (whiptail) para bienvenida, decisiones y resumen
# final; la compilación, checkinstall, la instalación de rustup y el
# diagnóstico final se muestran como texto normal de terminal (no tiene
# sentido meter esa salida dentro de una ventana).
#
# Uso:
#   chmod +x setup-asusctl-rogcontrol.sh
#   ./setup-asusctl-rogcontrol.sh            # instala/actualiza; si ya está la última
#                                            # versión, lo dice y sale sin tocar nada
#   ./setup-asusctl-rogcontrol.sh --check    # solo comprueba si hay actualización
#   ./setup-asusctl-rogcontrol.sh --force    # recompila aunque ya esté actualizado
#
# El script se detiene en el primer error (set -e) y pide confirmación
# antes de cada bloque grande. Revisa el contenido antes de ejecutarlo.

set -euo pipefail

TITLE="Instalador de asusctl csr79a"
VERSION="1.1.0"

BUILD_DIR="$HOME/Proyectos/asusctl-rogcontrol-build"
STATE_DIR="$HOME/.local/state/asusctl-rogcontrol"
STATE_FILE="$STATE_DIR/install.env"

log()  { echo -e "\n\033[1;34m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

confirm() {
    whiptail --title "$TITLE" --yesno "$1" "${2:-12}" "${3:-70}"
}

# ---------------------------------------------------------------------------
# Opciones y comprobación de versión (ANTES de tocar nada)
# ---------------------------------------------------------------------------
#
# Esta comprobación solo necesita curl y dpkg: no usa sudo, apt, whiptail ni
# rustup, y se hace antes de crear o reescribir el fichero de estado. Así, si
# no hay nada nuevo, el script solo lo dice y sale sin modificar el sistema.

CHECK_ONLY=0
FORCE=0

usage() {
    cat <<'EOF_USAGE'
Uso: ./setup-asusctl-rogcontrol.sh [opciones]

  (sin opciones)  Comprueba la última versión. Si ya está instalada, lo dice
                  y sale sin cambiar nada. Si hay una versión nueva (o no está
                  instalado), compila e instala.
  -c, --check     Solo comprueba y muestra el estado; no instala nada.
                  Código de salida: 0 = actualizado, 10 = hay actualización
                  (o no está instalado), 1 = error.
  -f, --force     Recompila e instala aunque ya esté la última versión.
  -h, --help      Muestra esta ayuda.
EOF_USAGE
}

for arg in "$@"; do
    case "$arg" in
        -c|--check) CHECK_ONLY=1 ;;
        -f|--force) FORCE=1 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "Opción desconocida: $arg" >&2; usage >&2; exit 1 ;;
    esac
done

# gitlab.com/asus-linux/asusctl (el repo "oficial" histórico) está
# ARCHIVADO (solo lectura) desde hace tiempo: su última tag se quedó
# congelada en 6.3.8 y nunca tendrá versiones más nuevas. El desarrollo
# activo continúa en GitHub, en OpenGamingCollective/asusctl. Seguimos la
# redirección pública de /releases/latest (sin pasar por api.github.com)
# para no depender de un número de versión fijo.
asusctl_latest_tag() {
    curl -sI --max-time 20 https://github.com/OpenGamingCollective/asusctl/releases/latest \
        | grep -i '^location:' \
        | sed 's#.*/tag/##' \
        | tr -d '\r\n' || true
}

# Como asusctl se instala vía checkinstall, queda registrado en dpkg con la
# versión que le pasamos (--pkgversion).
asusctl_installed_version() {
    if dpkg -l asusctl 2>/dev/null | grep -q '^ii'; then
        dpkg-query -W -f='${Version}' asusctl 2>/dev/null || true
    fi
}

command -v curl >/dev/null 2>&1 || die "Falta curl. Instálalo con: sudo apt install curl"

ASUSCTL_VERSION="$(asusctl_latest_tag)"
if [ -z "$ASUSCTL_VERSION" ]; then
    die "No se pudo determinar la última versión de asusctl (¿sin conexión?). Revisa https://github.com/OpenGamingCollective/asusctl/releases"
fi
ASUSCTL_INSTALLED_VERSION="$(asusctl_installed_version)"

# checkinstall añade su propio sufijo de revisión Debian (p.ej. "-1") a la
# versión que le pasamos con --pkgversion, así que dpkg guarda "6.5.0-1"
# aunque la tag real sea "6.5.0". Para comparar de forma justa, nos
# quedamos solo con la parte anterior al primer guion.
ASUSCTL_INSTALLED_VERSION_BASE="${ASUSCTL_INSTALLED_VERSION%%-*}"

if [ -n "$ASUSCTL_INSTALLED_VERSION" ] && [ "$ASUSCTL_INSTALLED_VERSION_BASE" = "$ASUSCTL_VERSION" ]; then
    ok "asusctl ya está actualizado (instalada: ${ASUSCTL_INSTALLED_VERSION}, última: ${ASUSCTL_VERSION}). Nada que hacer."
    if [ "$CHECK_ONLY" -eq 1 ] || [ "$FORCE" -eq 0 ]; then
        exit 0
    fi
    warn "--force: se recompilará la misma versión."
else
    if [ -n "$ASUSCTL_INSTALLED_VERSION" ]; then
        log "Hay una actualización disponible: ${ASUSCTL_INSTALLED_VERSION} -> ${ASUSCTL_VERSION}"
    else
        log "asusctl no está instalado. Última versión disponible: ${ASUSCTL_VERSION}"
    fi
    if [ "$CHECK_ONLY" -eq 1 ]; then
        echo "Para instalar/actualizar, ejecuta el script sin --check."
        exit 10
    fi
fi

mkdir -p "$STATE_DIR"
: > "$STATE_FILE"   # el estado se reescribe en cada ejecución
state_set() { echo "$1=$2" >> "$STATE_FILE"; }

# ---------------------------------------------------------------------------
# -1. Comprobaciones de entorno (usuario, apt, sudo, whiptail)
# ---------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    die "No ejecutes este script como root directamente. Usa tu usuario normal; se pedirá sudo cuando haga falta."
fi

if ! command -v apt >/dev/null 2>&1; then
    die "Este script está pensado para sistemas basados en APT (Debian/derivados)."
fi

if ! command -v sudo >/dev/null 2>&1; then
    die "No se encontró el comando 'sudo' en este sistema. Revisa la sección 'Requisitos previos: dejar sudo listo' del README antes de ejecutar este script."
fi

if ! command -v whiptail >/dev/null 2>&1; then
    log "Instalando whiptail (necesario para las pantallas de este script)"
    sudo apt update
    sudo apt install -y whiptail
fi

log "Comprobando permisos de sudo..."
if ! sudo -v; then
    die "No se pudieron validar los permisos de sudo. Revisa la sección 'Requisitos previos: dejar sudo listo' del README."
fi

# ---------------------------------------------------------------------------
# 0. Pantalla de bienvenida y comprobaciones previas (bloqueantes)
# ---------------------------------------------------------------------------

confirm "Versión del Instalador de asusctl csr79a ${VERSION}

Este programa compila e instala asusctl + rog-control-center desde código fuente, y los registra en dpkg vía checkinstall para poder desinstalarlos limpiamente después.

Requiere kernel >= 6.6 y hardware ASUS ROG para que asusd llegue a arrancar.

¿Desea continuar?" 16 70 || exit 0

log "Comprobando requisitos previos"

# 0.1 Kernel >= 6.6 (mínimo exigido por asusctl)
KERNEL_VERSION=$(uname -r | cut -d- -f1)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
if [ "$KERNEL_MAJOR" -lt 6 ] || { [ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -lt 6 ]; }; then
    die "Kernel detectado: $KERNEL_VERSION. asusctl exige kernel >= 6.6. En Debian 12/bookworm necesitarías un kernel de backports; en Debian 13/trixie (6.12) ya cumple."
fi
echo "  - Kernel $KERNEL_VERSION: OK (>= 6.6)"

# Nota: a diferencia de la versión anterior de este proyecto (que incluía
# Cardwire), aquí ya no se exige sesión Wayland ni se comprueba BPF LSM:
# asusctl no lo necesita.

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 1. Dependencias de compilación (apt)
# ---------------------------------------------------------------------------
#
# Estas dependencias NO se desinstalan automáticamente en el revertido: son
# librerías del sistema que pueden compartirse con otro software, así que
# quitarlas a ciegas es más arriesgado que dejarlas. El script de
# desinstalación deja la lista impresa por si quieres limpiarlas a mano.

log "Instalando dependencias de compilación (asusctl)"

sudo apt update

sudo apt install -y \
    build-essential git cmake pkg-config \
    curl checkinstall \
    libpci-dev libsysfs-dev libudev-dev libboost-dev \
    libgtk-3-dev libglib2.0-dev \
    libseat-dev libasound2-dev \
    libfreetype6-dev libfontconfig1-dev \
    libexpat1-dev \
    libxcb-composite0-dev libxcb1-dev libx11-dev libx11-xcb-dev \
    libssl-dev \
    libclang-dev llvm clang \
    libinput-dev libxkbcommon-dev libgbm-dev \
    libdrm-dev \
    libzstd-dev libpcre2-dev \
    libsystemd-dev \
    npm \
    gettext \
    libegl1-mesa-dev libvulkan-dev libglvnd-dev libwayland-dev

# ---------------------------------------------------------------------------
# 2. Rust: quitar el de los repos de Debian (si existe) e instalar rustup
# ---------------------------------------------------------------------------

log "Preparando Rust (rustup)"

CARGO_RUSTC_REMOVED="no"
if dpkg -l | grep -qE '^ii\s+(cargo|rustc)\s'; then
    warn "Se detectó cargo/rustc instalados vía apt. Se van a quitar para evitar conflictos con rustup."
    sudo apt remove -y cargo rustc || true
    CARGO_RUSTC_REMOVED="si"
fi
state_set CARGO_RUSTC_REMOVED "$CARGO_RUSTC_REMOVED"

RUSTUP_INSTALLED_BY_SCRIPT="no"
if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    RUSTUP_INSTALLED_BY_SCRIPT="si"
fi
state_set RUSTUP_INSTALLED_BY_SCRIPT "$RUSTUP_INSTALLED_BY_SCRIPT"

# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup default stable

# ---------------------------------------------------------------------------
# Diagnóstico automático de dependencias de compilación
# ---------------------------------------------------------------------------
#
# Objetivo: no descubrir las dependencias que faltan una a una, tras
# minutos de compilación, cada vez que asusctl publica una versión nueva.
#
#  1) ANTES de compilar: se leen los build.rs del propio repo y se comprueba
#     que existan las herramientas externas que ejecutan (p. ej. msgfmt).
#  2) Si aun así falla la compilación: se lee el log, se detecta qué
#     librería (.pc) o herramienta falta, se busca su paquete Debian con
#     apt-file y se ofrece instalarlo y reintentar.
#
# Los paquetes que se añaden aquí de forma automática se listan al final,
# para que los incorpores a la lista fija de dependencias (sección 1).

APT_FILE_READY="no"
AUTO_ADDED_PKGS=()

# Prepara apt-file. Se llama siempre desde el shell principal (no dentro de
# $(...)) para que la marca APT_FILE_READY persista; su salida va a stderr.
ensure_apt_file() {
    [ "$APT_FILE_READY" = "si" ] && return 0
    log "Preparando apt-file (para saber qué paquete provee cada dependencia)" >&2
    command -v apt-file >/dev/null 2>&1 || sudo apt install -y apt-file >&2
    sudo apt-file update >&2 || true
    APT_FILE_READY="si"
}

# Herramientas que ejecutan los build.rs del repo (Command::new("...")).
scan_build_tools() {
    { grep -rhoE 'Command::new\("[^"]+"\)' --include=build.rs . 2>/dev/null || true; } \
        | sed -E 's/Command::new\("([^"]+)"\)/\1/' | sort -u
}

# Paquete Debian que provee /usr/bin/<herramienta>
pkg_for_tool() {
    { apt-file search -x "(^|/)usr/bin/$1\$" 2>/dev/null || true; } | cut -d: -f1 | sort -u | head -n1
}

# Paquete Debian que provee <nombre>.pc (pkg-config)
pkg_for_pc() {
    { apt-file search -x "(^|/)usr/(lib/x86_64-linux-gnu|share|lib)/pkgconfig/$1\.pc\$" 2>/dev/null || true; } \
        | cut -d: -f1 | sort -u | head -n1
}

# Instala los paquetes que aún no lo estén. Devuelve 1 si no hay nada nuevo
# que instalar o si el usuario lo rechaza (así el bucle de reintentos no
# puede quedarse dando vueltas).
install_missing() {
    local to_install=() p
    for p in "$@"; do
        [ -n "$p" ] || continue
        dpkg -s "$p" >/dev/null 2>&1 || to_install+=("$p")
    done
    [ ${#to_install[@]} -gt 0 ] || return 1

    warn "Faltan dependencias de compilación: ${to_install[*]}"
    if confirm "Faltan dependencias de compilación:

${to_install[*]}

¿Instalarlas ahora?" 14 70; then
        sudo apt install -y "${to_install[@]}"
        AUTO_ADDED_PKGS+=("${to_install[@]}")
    else
        return 1
    fi
}

# 1) Comprobación previa: herramientas que usan los build.rs.
preflight_build_tools() {
    local tool pkgs=()
    for tool in $(scan_build_tools); do
        command -v "$tool" >/dev/null 2>&1 && continue
        warn "Un build.rs usa '$tool' y no está instalado."
        ensure_apt_file
        pkgs+=("$(pkg_for_tool "$tool")")
    done
    [ ${#pkgs[@]} -gt 0 ] || return 0
    install_missing "${pkgs[@]}" || die "Instala a mano las herramientas que faltan y vuelve a ejecutar el script."
}

# 2) Lee un log de compilación y devuelve los paquetes que faltan.
missing_pkgs_from_log() {
    local log_file="$1" name
    {
        # Librerías (pkg-config): "The system library `libseat` required by crate ..."
        { grep -oE 'The system library `[^`]+`' "$log_file" || true; } | sed -E 's/.*`([^`]+)`.*/\1/'
        # "No package 'xcb' found"
        { grep -oE "No package '[^']+' found" "$log_file" || true; } | sed -E "s/No package '([^']+)' found/\1/"
    } | sort -u | while read -r name; do
        [ -n "$name" ] && pkg_for_pc "$name"
    done
    {
        # Herramientas: "could not run msgfmt" / "msgfmt: command not found"
        { grep -oE 'could not run [A-Za-z0-9_.+-]+' "$log_file" || true; } | awk '{print $4}'
        { grep -oE '[A-Za-z0-9_.+-]+: (command not found|orden no encontrada)' "$log_file" || true; } | cut -d: -f1
    } | sort -u | while read -r name; do
        [ -n "$name" ] && pkg_for_tool "$name"
    done
    return 0
}

# Sustituye al "make" directo: compila y, si falla por una dependencia,
# la detecta, la instala (con tu confirmación) y reintenta.
build_with_dep_check() {
    local build_log="$BUILD_DIR/build.log" attempt pkgs=()
    for attempt in 1 2 3 4 5; do
        if make 2>&1 | tee "$build_log"; then
            return 0
        fi
        ensure_apt_file
        mapfile -t pkgs < <(missing_pkgs_from_log "$build_log" | sort -u)
        if [ ${#pkgs[@]} -eq 0 ]; then
            warn "La compilación falló, pero no parece un problema de dependencias. Revisa $build_log"
            return 1
        fi
        install_missing "${pkgs[@]}" || { warn "No hay nada nuevo que instalar. Revisa $build_log"; return 1; }
        if [ "$attempt" -lt 5 ]; then
            log "Reintentando la compilación (intento $((attempt + 1)) de 5)"
        fi
    done
    warn "Se agotaron los 5 intentos. Revisa $build_log"
    return 1
}

# ---------------------------------------------------------------------------
# 3. Compilar e instalar asusctl (vía checkinstall -> paquete dpkg real)
# ---------------------------------------------------------------------------

# La versión a instalar (ASUSCTL_VERSION) y la instalada ya se determinaron
# al principio del script, antes de tocar apt, rustup o el fichero de estado.
log "Versión a instalar: $ASUSCTL_VERSION (instalada: ${ASUSCTL_INSTALLED_VERSION:-ninguna})"

log "Clonando y compilando asusctl v$ASUSCTL_VERSION"

# Si la carpeta ya existe (de una ejecución anterior) hay que llevarla al tag
# nuevo: antes se reutilizaba tal cual y se recompilaba el código VIEJO
# registrándolo en dpkg como si fuera la versión nueva.
if [ ! -d "asusctl/.git" ]; then
    git clone --depth=1 https://github.com/OpenGamingCollective/asusctl.git -b "$ASUSCTL_VERSION" asusctl
    cd asusctl
else
    cd asusctl
    git fetch --depth=1 origin tag "$ASUSCTL_VERSION"
    git checkout -q -f "$ASUSCTL_VERSION"
fi

# Fix de permisos udev: las reglas de asusctl usaban por defecto el grupo
# "wheel" (convención de Fedora/Arch); Debian/Ubuntu usa "sudo". En
# versiones recientes (fork de GitHub) el archivo se renombró de
# "99-asusd.rules" a "asusd.rules" y ya no usa GROUP="wheel" en absoluto
# (se comprueba de todas formas, por si vuelve a cambiar en el futuro).
ASUSD_RULES_FILE=""
for candidate in data/99-asusd.rules data/asusd.rules; do
    if [ -f "$candidate" ]; then
        ASUSD_RULES_FILE="$candidate"
        break
    fi
done

if [ -n "$ASUSD_RULES_FILE" ] && grep -q 'GROUP="wheel"' "$ASUSD_RULES_FILE"; then
    log "Aplicando parche de grupo udev (wheel -> sudo) en $ASUSD_RULES_FILE"
    sed -i 's/GROUP="wheel"/GROUP="sudo"/g' "$ASUSD_RULES_FILE"
fi

log "Comprobando herramientas que necesitan los build.rs de esta versión"
preflight_build_tools

build_with_dep_check || die "La compilación falló. Revisa $BUILD_DIR/build.log"

log "Empaquetando asusctl con checkinstall (para que quede registrado en dpkg)"
sudo checkinstall \
    --pkgname=asusctl \
    --pkgversion="$ASUSCTL_VERSION" \
    --provides=asusctl \
    --nodoc \
    -y \
    make install

sudo systemctl daemon-reload
sudo systemctl enable asusd

# --- PARCHE: no abortar el script si asusd no arranca --------------------
# systemctl enable --now hacía las dos cosas en un solo comando; si el
# arranque fallaba (p.ej. sin hardware ASUS ROG real, como en una VM), ese
# comando devolvía código de error y set -e mataba el script aquí mismo.
# Separando "enable" de "start" y metiendo el start dentro de un "if", un
# fallo aquí solo genera un aviso y el script continúa con normalidad.
if ! sudo systemctl start asusd; then
    warn "asusd no ha arrancado (el proceso de control ha devuelto un error)."
    warn "Esto es ESPERABLE si no hay hardware ASUS ROG real (p.ej. en una VM):"
    warn "asusd necesita las interfaces ACPI/WMI reales del portátil para poder arrancar."
    warn "El servicio ha quedado 'enabled', así que arrancará solo en el hardware real."
    warn "Detalle: 'systemctl status asusd' / 'journalctl -xeu asusd.service'."
fi

cd "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 4. power-profiles-daemon
# ---------------------------------------------------------------------------
#
# NOTA (corregido): se creía que asusd chocaba con power-profiles-daemon y
# había que enmascarar este último. Según la wiki de Arch sobre asusctl,
# es al revés: el cambio de perfiles de energía de asusctl REQUIERE que
# power-profiles-daemon esté corriendo. Enmascararlo rompe la integración
# en vez de evitar un conflicto. Por eso este script ya NO lo toca; si en
# tu sistema estaba enmascarado por una versión anterior de este script,
# desenmascáralo con:
#   sudo systemctl unmask power-profiles-daemon
#   sudo systemctl enable --now power-profiles-daemon

PPD_MASKED_BY_SCRIPT="no"
state_set PPD_MASKED_BY_SCRIPT "$PPD_MASKED_BY_SCRIPT"

log "Comprobando power-profiles-daemon (requerido por asusctl para cambiar perfiles de energía)"
sudo apt install -y power-profiles-daemon
if systemctl is-enabled power-profiles-daemon 2>/dev/null | grep -q masked; then
    warn "power-profiles-daemon estaba enmascarado (posiblemente por una versión anterior de este script); desenmascarando."
    sudo systemctl unmask power-profiles-daemon
fi
sudo systemctl enable --now power-profiles-daemon

# ---------------------------------------------------------------------------
# 5. Validación final
# ---------------------------------------------------------------------------

log "Validación final"

echo "--- asusd ---"
systemctl status asusd --no-pager || true
echo
echo "--- asusctl info (versión y datos del sistema detectados) ---"
if systemctl is-active --quiet asusd; then
    # asusctl pasó de flags sueltos (-s, -v...) a subcomandos (info, aura,
    # profile...) en algún punto de su desarrollo; "-s" ya no existe y da
    # "Unrecognized argument" pase lo que pase con el hardware.
    asusctl info || warn "asusctl info falló pese a que asusd está activo; revisa 'asusctl --help' por si la CLI ha cambiado de nuevo. Detalle: 'journalctl -u asusd'."
else
    warn "asusd no está activo, se omite 'asusctl info' (no hay daemon con el que hablar; ver el aviso de la sección 3)."
fi

if [ ${#AUTO_ADDED_PKGS[@]} -gt 0 ]; then
    warn "Se instalaron dependencias que no estaban en la lista fija: ${AUTO_ADDED_PKGS[*]}"
    warn "Añádelas al 'sudo apt install' de la sección 1 para no depender del diagnóstico la próxima vez."
fi

log "Instalación completada. Estado guardado en $STATE_FILE para el revertido."
echo "Para desinstalar todo limpiamente, usa: ./uninstall-asusctl-rogcontrol.sh"

SUMMARY="asusctl v${ASUSCTL_VERSION} instalado y registrado en dpkg.

Para desinstalar todo limpiamente, usa: ./uninstall-asusctl-rogcontrol.sh"
if systemctl is-active --quiet asusd; then
    SUMMARY+="

asusd está activo."
else
    SUMMARY+="

asusd no ha arrancado (esperable en una VM sin hardware ASUS ROG real; en tu portátil real debería arrancar solo). Revisa 'systemctl status asusd' si tienes hardware real y no arranca."
fi

whiptail --title "$TITLE" --msgbox "$SUMMARY" 16 74
