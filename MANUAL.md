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

No hace falta tener BPF LSM activo — esa era una restricción específica
de Cardwire, que ya no forma parte de este proyecto. La sesión sí importa:
usa **Wayland**, ya que en X11 `rog-control-center` no funciona
correctamente.

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

## 5. power-profiles-daemon

`asusd` necesita que `power-profiles-daemon` esté instalado y corriendo
para poder cambiar de perfil de energía correctamente — según la
documentación de asusctl, **se complementan, no compiten**. (Una versión
anterior de este script asumía lo contrario y ofrecía enmascararlo; eso
era un error, ya corregido.) El script se asegura de que el paquete esté
instalado, lo desenmascara si venía enmascarado por una ejecución vieja, y
lo activa.

## 6. Validación final

Al terminar, el script muestra:

- Estado de `asusd` (`systemctl status`)
- `asusctl info` (si `asusd` está activo)

## Desinstalación (`uninstall-asusctl-rogcontrol.sh`)

Lee el estado guardado en `~/.local/state/asusctl-rogcontrol/install.env` y
revierte, en orden:

1. **asusctl / rog-control-center**: purga el paquete `asusctl` vía `apt`
   (registrado por `checkinstall`). Si no está registrado en dpkg (por
   ejemplo, si se instaló a mano sin `checkinstall`), imprime las rutas
   típicas a revisar manualmente.
2. **power-profiles-daemon**: si detecta que quedó enmascarado por una
   ejecución vieja del instalador (versiones anteriores lo enmascaraban
   por error), lo desenmascara y reactiva. En instalaciones nuevas del
   script no debería hacer falta, ya que ya no se enmascara.
3. **Rust (rustup / cargo-rustc de apt)**: pregunta explícitamente antes de
   tocar nada, porque `rustup` puede estar en uso por otros proyectos ajenos
   a este.
4. **Directorio de compilación y estado**: pregunta antes de borrar
   `~/Proyectos/asusctl-rogcontrol-build`.
5. **Verificación final**: comprueba que los comandos y servicios ya no
   existan.

Las dependencias de compilación instaladas por `apt` (librerías de sistema)
**no se quitan** en ningún caso, por ser software que puede compartir otro
paquete instalado.
