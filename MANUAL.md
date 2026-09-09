# Manual — asusctl-rogcontrol

Explicación detallada de cada paso del script, permisos que pide, y cómo
revertir la instalación.

---

## Requisitos previos

- Debian 13 (trixie) o derivado reciente.
- Usuario con permisos de `sudo` (no ejecutar el script como root).
- Kernel >= 6.6 (Debian 13 trae 6.12 por defecto; el script lo comprueba y
  aborta si no se cumple).
- Conexión a internet (para clonar asusctl, instalar rustup, y descargar
  paquetes de apt).

No hace falta sesión Wayland ni tener BPF LSM activo — esas eran
restricciones específicas de Cardwire, que ya no forma parte de este
proyecto.

---

## 1. Comprobaciones previas

El script verifica la versión de kernel (`uname -r`) contra el mínimo
6.6 que exige asusctl, y aborta con un mensaje claro si no se cumple.

## 2. Dependencias de compilación

Instala, vía `apt`, todas las librerías necesarias para compilar asusctl y
rog-control-center desde código fuente: herramientas de build
(`build-essential`, `cmake`, `pkg-config`, `checkinstall`), librerías de
sistema (udev, PCI, sysfs, GTK, X11/Wayland, Vulkan, etc.) y `npm` (para la
parte de interfaz de rog-control-center).

Estas dependencias **no se desinstalan** en el revertido, porque son
librerías de sistema que puede compartir otro software instalado en el
equipo — quitarlas a ciegas es más arriesgado que dejarlas.

## 3. Rust (rustup)

asusctl está escrito en Rust. El script:

1. Si detecta `cargo`/`rustc` instalados vía `apt` (versión de los repos de
   Debian), los quita — suelen chocar con `rustup`.
2. Si `rustup` no está instalado, lo instala desde `sh.rustup.rs`.
3. Configura `stable` como toolchain por defecto.

Ambas acciones quedan registradas en `~/.local/state/asusctl-rogcontrol/install.env`
para que el desinstalador sepa si debe revertirlas.

## 4. Compilar e instalar asusctl + rog-control-center

1. Consulta la redirección pública de
   `https://github.com/OpenGamingCollective/asusctl/releases/latest` para
   obtener la última versión (el repo histórico en GitLab está archivado en
   modo solo lectura desde hace tiempo, congelado en la versión 6.3.8; el
   desarrollo activo continúa en este fork de GitHub).
2. Clona esa versión exacta (`--depth=1 -b <tag>`).
3. Aplica un parche de permisos udev si hace falta: las reglas originales
   usaban el grupo `wheel` (convención de Fedora/Arch); Debian/Ubuntu usa
   `sudo`. En versiones recientes del fork esto ya no aplica, pero el script
   lo comprueba por si vuelve a cambiar.
4. Compila con `make`.
5. Empaqueta con `checkinstall` en vez de `make install` directo, para que
   quede registrado en `dpkg` como el paquete `asusctl` — así se puede
   desinstalar limpio después, sin tener que adivinar rutas de archivos.
6. Habilita el servicio `asusd` y trata de arrancarlo. **Si falla el
   arranque, el script no aborta**: es esperable en equipos sin hardware ASUS
   ROG real (por ejemplo, una VM), ya que `asusd` necesita las interfaces
   ACPI/WMI reales del portátil. El servicio queda `enabled` y arrancará solo
   en el hardware real.

## 5. switcheroo-control

En vez de Cardwire, el script instala el paquete oficial de Debian:

```
sudo apt install switcheroo-control
sudo systemctl enable --now switcheroo-control
```

Si el paquete ya estaba instalado (por ejemplo, si venía con tu entorno de
escritorio), el script lo detecta y omite la instalación, pero igual se
asegura de que el servicio esté habilitado y corriendo.

`switcheroo-control` es un servicio D-Bus: no "cambia" activamente la GPU en
uso como pretendía hacer Cardwire, sino que expone qué GPUs hay disponibles y
permite lanzar aplicaciones puntuales con la GPU dedicada, vía la variable de
entorno `DRI_PRIME=1` o desde el menú contextual del escritorio ("Ejecutar
usando la tarjeta gráfica dedicada"). Es el mismo mecanismo que usan Fedora y
CachyOS por defecto.

### Por qué switcheroo-control y no Cardwire

- **Cardwire** es un proyecto comunitario para gestión de gráficos híbridos
  vía eBPF LSM, marcado oficialmente como experimental por sus propios
  desarrolladores, con soporte solo por Discord. En pruebas reales llegó a
  dar conflictos de paquetes.
- **switcheroo-control** es un paquete oficial de Debian (equipo de GNOME),
  estable, sin restricciones de sesión (Wayland o X11 por igual), y es el
  estándar de facto que ya usan Fedora y CachyOS.

Si en algún momento Cardwire madura y se vuelve estable, se puede reevaluar
como alternativa — pero por ahora este proyecto se queda con el enfoque que
ya funciona en otras distros mainstream.

## 6. power-profiles-daemon

`asusd` gestiona perfiles de energía, y puede chocar con
`power-profiles-daemon` si ambos están activos. El script comprueba si está
activo y, de ser así, **pregunta** antes de enmascararlo (nunca lo hace sin
confirmación).

## 7. Validación final

Al terminar, el script muestra:

- Estado de `asusd` y `switcheroo-control` (`systemctl status`)
- `asusctl info` (si `asusd` está activo)
- `switcherooctl list` (GPUs detectadas)

## Desinstalación (`uninstall-asusctl-rogcontrol.sh`)

Lee el estado guardado en `~/.local/state/asusctl-rogcontrol/install.env` y
revierte, en orden:

1. **switcheroo-control**: solo lo purga si fue este script el que lo
   instaló (si ya estaba antes, no lo toca).
2. **asusctl / rog-control-center**: purga el paquete `asusctl` vía `apt`
   (registrado por `checkinstall`). Si no está registrado en dpkg (por
   ejemplo, si se instaló a mano sin `checkinstall`), imprime las rutas
   típicas a revisar manualmente.
3. **power-profiles-daemon**: lo desenmascara y reactiva solo si fue este
   script el que lo enmascaró.
4. **Rust (rustup / cargo-rustc de apt)**: pregunta explícitamente antes de
   tocar nada, porque `rustup` puede estar en uso por otros proyectos ajenos
   a este.
5. **Directorio de compilación y estado**: pregunta antes de borrar
   `~/Proyectos/asusctl-rogcontrol-build`.
6. **Verificación final**: comprueba que los comandos y servicios ya no
   existan.

Las dependencias de compilación instaladas por `apt` (librerías de sistema)
**no se quitan** en ningún caso, por ser software que puede compartir otro
paquete instalado.
