#!/usr/bin/env bash
#
# setup-asusctl-rogcontrol.sh
#
# Instala asusctl + rog-control-center (compilados desde código fuente, vía
# checkinstall) y switcheroo-control (detección/gestión de GPU híbrida,
# paquete oficial de Debian) en Debian y derivados (Debian 13/trixie o
# posterior, KDE Plasma).
#
# NO instala Cardwire ni supergfxctl: ambos proyectos quedaron descartados.
# Cardwire seguía en beta y llegó a dar conflictos de paquetes; el enfoque
# que usan Fedora y CachyOS por defecto es switcheroo-control, un servicio
# D-Bus oficial y liviano que no requiere compilar nada.
#
# Todo lo instalado queda registrado en dpkg (checkinstall para asusctl,
# apt para switcheroo-control), así que se puede revertir limpiamente con
# uninstall-asusctl-rogcontrol.sh.
#
# Uso:
#   chmod +x setup-asusctl-rogcontrol.sh
#   ./setup-asusctl-rogcontrol.sh
#
# El script se detiene en el primer error (set -e) y pide confirmación
# antes de cada bloque grande. Revisa el contenido antes de ejecutarlo.

set -euo pipefail

BUILD_DIR="$HOME/Proyectos/asusctl-rogcontrol-build"
STATE_DIR="$HOME/.local/state/asusctl-rogcontrol"
STATE_FILE="$STATE_DIR/install.env"

log()  { echo -e "\n\033[1;34m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

confirm() {
    read -r -p "$1 [s/N] " resp
    case "$resp" in
        [sS]) return 0 ;;
        *) return 1 ;;
    esac
}

mkdir -p "$STATE_DIR"
: > "$STATE_FILE"   # el estado se reescribe en cada ejecución
state_set() { echo "$1=$2" >> "$STATE_FILE"; }

# ---------------------------------------------------------------------------
# 0. Comprobaciones previas (bloqueantes)
# ---------------------------------------------------------------------------

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
# ninguno de los dos componentes actuales (asusctl, switcheroo-control) lo
# necesita. switcheroo-control funciona igual en Wayland y en X11.

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
# 3. Compilar e instalar asusctl (vía checkinstall -> paquete dpkg real)
# ---------------------------------------------------------------------------

log "Averiguando la última versión de asusctl"

# gitlab.com/asus-linux/asusctl (el repo "oficial" histórico) está
# ARCHIVADO (solo lectura) desde hace tiempo: su última tag se quedó
# congelada en 6.3.8 y nunca tendrá versiones más nuevas. El desarrollo
# activo continúa en GitHub, en OpenGamingCollective/asusctl. Seguimos la
# redirección pública de /releases/latest (sin pasar por api.github.com)
# para no depender de un número de versión fijo.
ASUSCTL_TAG=$(curl -sI https://github.com/OpenGamingCollective/asusctl/releases/latest \
    | grep -i '^location:' \
    | sed 's#.*/tag/##' \
    | tr -d '\r\n')

if [ -z "$ASUSCTL_TAG" ]; then
    die "No se pudo determinar la última versión de asusctl (falló la redirección de /releases/latest). Revisa https://github.com/OpenGamingCollective/asusctl/releases"
fi
ASUSCTL_VERSION="$ASUSCTL_TAG"
log "Última versión detectada: $ASUSCTL_VERSION"

log "Clonando y compilando asusctl v$ASUSCTL_VERSION"

if [ ! -d "asusctl" ]; then
    git clone --depth=1 https://github.com/OpenGamingCollective/asusctl.git -b "$ASUSCTL_VERSION" asusctl
fi
cd asusctl

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

make

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
    warn "Continuando con la instalación de switcheroo-control de todas formas."
fi

cd "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 4. Instalar switcheroo-control (paquete oficial de Debian, gráficos híbridos)
# ---------------------------------------------------------------------------
#
# switcheroo-control es el servicio D-Bus que usan por defecto Fedora y
# CachyOS para exponer la disponibilidad de GPU dual (integrada + dedicada).
# A diferencia de Cardwire, es un paquete oficial de Debian: no hace falta
# compilarlo ni descargarlo de GitHub.

log "Instalando switcheroo-control"

SWITCHEROO_INSTALLED_BY_SCRIPT="no"
if dpkg -l switcheroo-control 2>/dev/null | grep -q '^ii'; then
    echo "  switcheroo-control ya estaba instalado, se omite este paso."
else
    sudo apt install -y switcheroo-control
    SWITCHEROO_INSTALLED_BY_SCRIPT="si"
fi
state_set SWITCHEROO_INSTALLED_BY_SCRIPT "$SWITCHEROO_INSTALLED_BY_SCRIPT"

sudo systemctl enable --now switcheroo-control

# ---------------------------------------------------------------------------
# 5. Conflicto conocido: power-profiles-daemon
# ---------------------------------------------------------------------------

PPD_MASKED_BY_SCRIPT="no"
if systemctl is-active --quiet power-profiles-daemon 2>/dev/null; then
    warn "power-profiles-daemon está activo y puede chocar con asusd (perfiles de energía)."
    if confirm "¿Enmascarar power-profiles-daemon ahora?"; then
        sudo systemctl mask power-profiles-daemon
        sudo systemctl stop power-profiles-daemon || true
        PPD_MASKED_BY_SCRIPT="si"
    fi
fi
state_set PPD_MASKED_BY_SCRIPT "$PPD_MASKED_BY_SCRIPT"

# ---------------------------------------------------------------------------
# 6. Validación final
# ---------------------------------------------------------------------------

log "Validación final"

echo "--- asusd ---"
systemctl status asusd --no-pager || true
echo
echo "--- switcheroo-control ---"
systemctl status switcheroo-control --no-pager || true
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
echo
echo "--- switcherooctl list (GPUs detectadas) ---"
if command -v switcherooctl >/dev/null 2>&1; then
    switcherooctl list || warn "switcherooctl list falló; revisa 'journalctl -u switcheroo-control' para más detalle."
else
    warn "El comando 'switcherooctl' no está en el PATH todavía; puede requerir cerrar y abrir una terminal nueva."
fi

log "Instalación completada. Estado guardado en $STATE_FILE para el revertido."
echo "Para desinstalar todo limpiamente, usa: ./uninstall-asusctl-rogcontrol.sh"
