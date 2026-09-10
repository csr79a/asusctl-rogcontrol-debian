#!/usr/bin/env bash
#
# uninstall-asusctl-rogcontrol.sh
#
# Revierte todo lo que instaló setup-asusctl-rogcontrol.sh: asusctl/
# rog-control-center, y cualquier cambio de sistema que el instalador haya
# aplicado (enmascarar power-profiles-daemon, quitar cargo/rustc de apt,
# instalar rustup). Deja el sistema lo más parecido posible a como estaba
# antes de ejecutar el instalador.
#
# Uso:
#   chmod +x uninstall-asusctl-rogcontrol.sh
#   ./uninstall-asusctl-rogcontrol.sh
#
# Lee el estado guardado por el instalador en:
#   ~/.local/state/asusctl-rogcontrol/install.env
# Si ese archivo no existe (por ejemplo, instalaste a mano o borraste el
# estado), el script sigue funcionando pero pregunta en vez de asumir qué
# cambios se hicieron.

set -uo pipefail   # sin -e: queremos seguir aunque un paso de limpieza falle

STATE_DIR="$HOME/.local/state/asusctl-rogcontrol"
STATE_FILE="$STATE_DIR/install.env"
BUILD_DIR="$HOME/Proyectos/asusctl-rogcontrol-build"

log()  { echo -e "\n\033[1;34m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }

confirm() {
    read -r -p "$1 [s/N] " resp
    case "$resp" in
        [sS]) return 0 ;;
        *) return 1 ;;
    esac
}

CARGO_RUSTC_REMOVED="desconocido"
RUSTUP_INSTALLED_BY_SCRIPT="desconocido"
PPD_MASKED_BY_SCRIPT="desconocido"

if [ -f "$STATE_FILE" ]; then
    log "Estado del instalador encontrado en $STATE_FILE"
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    echo "  CARGO_RUSTC_REMOVED=$CARGO_RUSTC_REMOVED"
    echo "  RUSTUP_INSTALLED_BY_SCRIPT=$RUSTUP_INSTALLED_BY_SCRIPT"
    echo "  PPD_MASKED_BY_SCRIPT=$PPD_MASKED_BY_SCRIPT"
else
    warn "No se encontró $STATE_FILE. Se puede seguir, pero el script preguntará en vez de asumir qué tocó el instalador."
fi

echo
warn "Esto va a desinstalar asusctl y rog-control-center, y revertir los"
warn "cambios de sistema conocidos."
confirm "¿Continuar?" || { echo "Cancelado."; exit 0; }

# ---------------------------------------------------------------------------
# 1. asusctl / rog-control-center
# ---------------------------------------------------------------------------
#
# El instalador usa checkinstall para envolver "make install" en un paquete
# dpkg real (nombre: asusctl), así que se puede desinstalar limpio, sin
# adivinar rutas de archivos a mano.

log "Quitando asusctl / rog-control-center"

if systemctl list-unit-files 2>/dev/null | grep -q '^asusd'; then
    sudo systemctl disable --now asusd 2>/dev/null || true
fi

if dpkg -l asusctl 2>/dev/null | grep -q '^ii'; then
    sudo apt purge -y asusctl
    ok "Paquete asusctl purgado con apt (instalado originalmente vía checkinstall)."
else
    warn "No se detectó el paquete 'asusctl' instalado vía apt/dpkg."
    warn "Si en tu caso se instaló con 'sudo make install' directo (sin checkinstall,"
    warn "por ejemplo si adaptaste el script a mano), no queda registrado en dpkg y"
    warn "hay que quitarlo a mano. Rutas típicas a revisar:"
    echo "    /usr/bin/asusd /usr/bin/asusd-user /usr/bin/asusctl /usr/bin/asus-shutdown /usr/bin/rog-control-center"
    echo "    /usr/lib/systemd/system/asusd*.service"
    echo "    /usr/lib/udev/rules.d/*asusd*.rules"
    echo "    /usr/share/asusd/ /usr/share/asusctl/ /usr/share/rog-gui/"
    echo "    /usr/share/icons/hicolor/*/apps/asus_noti* /usr/share/icons/hicolor/*/apps/rog-control-center.png"
    echo "    /usr/share/applications/*rog-control-center*"
fi

sudo systemctl daemon-reload
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. power-profiles-daemon (solo si el instalador lo enmascaró)
# ---------------------------------------------------------------------------

log "Revisando power-profiles-daemon"

if [ "$PPD_MASKED_BY_SCRIPT" = "si" ]; then
    sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
    sudo systemctl enable --now power-profiles-daemon 2>/dev/null || true
    ok "power-profiles-daemon desenmascarado y reactivado (lo había enmascarado el instalador)."
elif [ "$PPD_MASKED_BY_SCRIPT" = "desconocido" ]; then
    if systemctl is-enabled power-profiles-daemon 2>/dev/null | grep -q masked; then
        warn "power-profiles-daemon está enmascarado y no hay estado guardado que confirme si lo hizo este instalador."
        confirm "¿Desenmascararlo y reactivarlo igualmente?" && {
            sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
            sudo systemctl enable --now power-profiles-daemon 2>/dev/null || true
        }
    else
        echo "  No está enmascarado, no hace falta tocar nada."
    fi
else
    echo "  El instalador no lo tocó, no hace falta hacer nada aquí."
fi

# ---------------------------------------------------------------------------
# 3. Rust (cargo/rustc de apt y rustup) — opcional, se pregunta siempre
# ---------------------------------------------------------------------------
#
# Esto NO se revierte por defecto: rustup puede estar en uso por otros
# proyectos ajenos a este, así que quitarlo a ciegas es más peligroso que
# dejarlo. Solo se toca si confirmas explícitamente.

log "Rust (rustup / cargo-rustc de apt)"

if [ "$RUSTUP_INSTALLED_BY_SCRIPT" = "si" ]; then
    warn "El instalador instaló rustup porque no existía antes."
    if confirm "¿Quieres desinstalar rustup también? (di 'n' si lo usas para otra cosa)"; then
        if command -v rustup >/dev/null 2>&1; then
            rustup self uninstall -y
            ok "rustup desinstalado."
        fi
    fi
else
    echo "  rustup ya existía antes del instalador (o no hay estado guardado); no se toca."
fi

if [ "$CARGO_RUSTC_REMOVED" = "si" ]; then
    warn "El instalador había quitado 'cargo' y 'rustc' de apt (los del repo de Debian) para evitar conflictos con rustup."
    confirm "¿Reinstalarlos de apt ahora?" && sudo apt install -y cargo rustc
fi

# ---------------------------------------------------------------------------
# 4. Directorio de compilación y estado
# ---------------------------------------------------------------------------

log "Limpieza de archivos locales del proyecto"

if [ -d "$BUILD_DIR" ]; then
    confirm "¿Borrar también el directorio de compilación ($BUILD_DIR)?" && rm -rf "$BUILD_DIR" && ok "Directorio de build eliminado."
fi

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
fi

# ---------------------------------------------------------------------------
# 5. Verificación final
# ---------------------------------------------------------------------------

log "Verificación final"

for cmd in asusctl rog-control-center; do
    if command -v "$cmd" >/dev/null 2>&1; then
        warn "'$cmd' todavía se encuentra en el PATH (revisa manualmente)."
    else
        ok "'$cmd' ya no está disponible."
    fi
done

for svc in asusd; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
        warn "El servicio '$svc' todavía existe en systemd (revisa manualmente)."
    else
        ok "El servicio '$svc' ya no existe."
    fi
done

log "Desinstalación completada."
echo "Las dependencias de compilación instaladas por apt (libclang-dev, etc.)"
echo "NO se han quitado a propósito: son librerías del sistema que puede usar otro software,"
echo "así que quitarlas a ciegas es más arriesgado que dejarlas instaladas."
