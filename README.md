# asusctl-rogcontrol

Script de instalación de **asusctl** + **rog-control-center** (compilados desde
código fuente) y **switcheroo-control** (detección/gestión de GPU híbrida) en
Debian y distribuciones derivadas, orientado a laptops ASUS ROG con KDE Plasma.

**No instala Cardwire ni supergfxctl.** Ambos proyectos quedaron descartados:
supergfxctl está en desuso, y Cardwire seguía en fase beta ("rough edges"
según sus propios desarrolladores, soporte solo por Discord) y llegó a dar
conflictos de paquetes en pruebas reales. En su lugar se usa
**switcheroo-control**, el mismo enfoque que traen por defecto Fedora y
CachyOS: un servicio D-Bus oficial, liviano, mantenido por el equipo de
GNOME, sin necesidad de compilar ni descargar nada de terceros.

> Este proyecto es la continuación de `asusctl-cardwire-debian`, renombrado
> tras quitar Cardwire.

## Qué instala

- **asusctl** y **rog-control-center**: compilados desde el repo oficial
(`gitlab.com/asus-linux/asusctl`, vía el fork activo en GitHub), vía
Rust/rustup, empaquetados con `checkinstall` para que queden registrados en
dpkg (y se puedan desinstalar limpiamente).
- **switcheroo-control**: paquete oficial de los repos de Debian
(`apt install switcheroo-control`). Expone por D-Bus qué GPUs hay
disponibles (integrada/dedicada) y permite lanzar aplicaciones puntuales
con la GPU dedicada (`DRI_PRIME=1`, o desde el menú contextual en
GNOME/KDE).

## Requisitos

- Debian 13 (trixie) o derivado reciente — kernel 6.12 por defecto.
- Kernel >= 6.6 (mínimo exigido por asusctl).
- Funciona igual en sesión **Wayland o X11** — a diferencia de la versión
anterior con Cardwire, ya no hay restricción de sesión.

## Uso

```
chmod +x setup-asusctl-rogcontrol.sh
./setup-asusctl-rogcontrol.sh
```

El script se detiene en el primer error y pide confirmación antes de pasos
sensibles (como enmascarar `power-profiles-daemon`). Revisa el contenido
antes de ejecutarlo, especialmente si vas a lanzarlo en un equipo que no sea
de pruebas. Guarda un registro de lo que cambió en
`~/.local/state/asusctl-rogcontrol/install.env`, que usa el script de
desinstalación para revertir solo lo que él mismo tocó.

## Desinstalar / revertir

```
chmod +x uninstall-asusctl-rogcontrol.sh
./uninstall-asusctl-rogcontrol.sh
```

Quita asusctl/rog-control-center (vía `apt purge`, ya que queda registrado en
dpkg) y switcheroo-control (solo si lo instaló este script), y revierte los
cambios de sistema conocidos (desenmascarar `power-profiles-daemon` si el
instalador lo enmascaró, opción de quitar rustup si lo instaló el propio
script). Las dependencias de compilación instaladas por apt no se tocan, por
ser librerías que puede compartir otro software.

Ver [MANUAL.md](./MANUAL.md) para el detalle de cada paso, permisos
necesarios y cómo revertir la instalación.

## Estado

Proyecto en desarrollo/revisión — pendiente de validar en una instalación
limpia de Debian 13 con KDE Plasma antes de darlo por definitivo.
