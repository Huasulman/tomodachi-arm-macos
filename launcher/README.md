# Tomodachi Launcher

App de Mac para recompilar Tomodachi Life sin usar la terminal: eliges el `.nsp`, pulsas **Recompilar** y ves cada paso de `scripts/build_tomodachi.sh` con su progreso y su registro.

A Mac app that rebuilds Tomodachi Life without the terminal: pick the `.nsp`, press **Recompilar** and follow each step of `scripts/build_tomodachi.sh` with its progress and log.

## Requisitos | Requirements

- Mac con Apple Silicon y Xcode instalado (hace falta el compilador de Metal) | Apple Silicon Mac with Xcode (the Metal compiler is required)
- Las mismas herramientas que `scripts/build_tomodachi.sh`: Python con su `.venv`, .NET (`brew install dotnet`) | The same tools as `scripts/build_tomodachi.sh`: Python with its `.venv`, .NET
- Tu propio volcado del juego base (v0) en `.nsp` y tu `prod.keys` | Your own dump of the base game (v0) as `.nsp` and your `prod.keys`

## Instalar | Install

```bash
launcher/build.sh
```

Compila la app y la deja en `/Applications/Tomodachi Launcher.app`, apuntando a este repo.
Builds the app into `/Applications/Tomodachi Launcher.app`, pointing at this repository.

Para un release | for a release:

```bash
launcher/build.sh --dist <carpeta | folder>
```

Crea `Tomodachi-Launcher-<versión>-arm64.zip` sin la ruta de tu Mac ni el icono del juego; al abrirlo por primera vez pide la carpeta del repo.
Creates `Tomodachi-Launcher-<version>-arm64.zip` without your Mac's path or the game icon; on first launch it asks for the repo folder.

## Uso | Usage

1. Arrastra el `.nsp` del juego base a la ventana (o pulsa **Elegir…**). | Drop the base game `.nsp` on the window (or press **Elegir…**).
2. `prod.keys` se busca solo en el repo y en la carpeta de arriba; si no, pulsa **Cambiar…**. | `prod.keys` is looked up in the repo and one folder up; otherwise press **Cambiar…**.
3. Pulsa **Recompilar**. La primera vez los shaders tardan bastante. | Press **Recompilar**. Shaders take a while the first time.
4. Al terminar, **Jugar** abre `/Applications/Tomodachi Life.app`. | When done, **Jugar** opens the game.

Opciones | options:

- **Compilación limpia** vuelve a extraer el `.nsp` (úsala si cambias de archivo). | re-extracts the `.nsp`.
- **Borrar la carpeta de trabajo al terminar** borra `~/010051F0207B2000-work`; la app y las partidas no se tocan. | deletes the workspace; the app and saves are kept.

El registro se guarda en `~/Library/Logs/nxnative/launcher.log`. | The log is written to `~/Library/Logs/nxnative/launcher.log`.

## No distribuir | Do not distribute

Ni el `.nsp`, ni `prod.keys`, ni la app del juego que se genera se suben al repo o a un release: contienen material de Nintendo. Cada persona recompila con su propia copia.
Neither the `.nsp`, nor `prod.keys`, nor the generated game app go in the repository or a release: they contain Nintendo material. Everyone rebuilds from their own copy.
