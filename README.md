# asusctl-rogcontrol

Script de instalación de **asusctl** + **rog-control-center** (compilados desde
código fuente) en Debian y distribuciones derivadas, orientado a laptops ASUS
ROG con KDE Plasma.

**No instala Cardwire ni supergfxctl.** Ambos proyectos quedaron descartados:
supergfxctl está en desuso, y Cardwire seguía en fase beta ("rough edges"
según sus propios desarrolladores, soporte solo por Discord) y llegó a dar
conflictos de paquetes en pruebas reales. Este proyecto se centra únicamente
en asusctl/rog-control-center, específicos de hardware ASUS ROG.

> Este proyecto es la continuación de `asusctl-cardwire-debian`, renombrado
> tras quitar Cardwire.

## Qué instala

- **asusctl** y **rog-control-center**: compilados desde el repo oficial
(`gitlab.com/asus-linux/asusctl`, vía el fork activo en GitHub), vía
Rust/rustup, empaquetados con `checkinstall` para que queden registrados en
dpkg (y se puedan desinstalar limpiamente).

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

El script se detiene en el primer error. Revisa el contenido antes de
ejecutarlo, especialmente si vas a lanzarlo en un equipo que no sea de
pruebas. Guarda un registro de lo que cambió en
`~/.local/state/asusctl-rogcontrol/install.env`, que usa el script de
desinstalación para revertir solo lo que él mismo tocó.

## Desinstalar / revertir

```
chmod +x uninstall-asusctl-rogcontrol.sh
./uninstall-asusctl-rogcontrol.sh
```

Quita asusctl/rog-control-center (vía `apt purge`, ya que queda registrado en
dpkg), y revierte los cambios de sistema conocidos (desenmascarar
`power-profiles-daemon` si quedó enmascarado por una ejecución vieja del
instalador, opción de quitar rustup si lo instaló el propio script). Las
dependencias de compilación instaladas por apt no se tocan, por ser
librerías que puede compartir otro software.

Ver [MANUAL.md](./MANUAL.md) para el detalle de cada paso, permisos
necesarios y cómo revertir la instalación.

## Estado

Validado en máquina real, en Debian 13 (trixie) y en Debian Sid, con KDE
Plasma. Instalación, desinstalación y verificación final funcionando
correctamente en ambos casos.
