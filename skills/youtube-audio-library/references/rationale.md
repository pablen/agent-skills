# Wayfinder map — skill de descarga/organización de audio desde YouTube

## Destino
Diseñar una skill (`SKILL.md` + scripts) que permita: buscar canciones en YouTube por
criterios (artista, duración), contrastar contra lo ya descargado, descargar el audio
en mejor calidad, renombrar/organizar en carpetas por artista, convertir opcionalmente
a un formato/bitrate menor, y mantener un catálogo (csv/md) con metadata de cada tema.
Los pasos determinísticos van en scripts; el agente solo aporta criterio (elegir
versión correcta, confirmar acciones masivas, normalizar nombres).

Cuando no queden decisiones abiertas abajo, pasamos a escribir la skill.

## Estado de decisiones

| # | Decisión | Estado |
|---|----------|--------|
| 1 | Ubicación de la biblioteca (originals/converted/catalog) | ✅ Resuelta |
| 2 | Formato del catálogo (csv vs md vs otro) y sus columnas | ✅ Resuelta |
| 3 | Plantilla de nombres de archivo y carpetas | ✅ Resuelta |
| 4 | Estrategia de búsqueda y filtros (duración, exclusión de versiones raras) | ✅ Resuelta |
| 5 | Lógica de dedup contra el catálogo (match exacto/fuzzy) | ✅ Resuelta |
| 11 | Lenguaje/runtime de los scripts | ✅ Resuelta |
| 6 | Calidad/formato de descarga original | ✅ Resuelta |
| 7 | Conversión opcional: formato/bitrate default y cuándo aplicarla | ✅ Resuelta |
| 8 | Tagging ID3 automático (mutagen) sí/no | ✅ Resuelta |
| 9 | Manejo de errores y casos raros (fallos de descarga, formatos incompatibles) | ✅ Resuelta |
| 10 | Nivel de confirmación del usuario en cada etapa (búsqueda, descarga, conversión) | ✅ Resuelta |

---

## Decisiones resueltas

### #1 — Ubicación de la biblioteca
La skill se instala **globalmente** (no es específica de este repo). Opera relativa
al **cwd** de la sesión del agente: el usuario crea una carpeta (ej. `music-library/`),
levanta ahí una sesión, y le pide usar la skill. La skill busca/crea `originals/`,
`converted/` y `catalog.csv` en el directorio actual. Esto permite tener varios
"proyectos" de biblioteca en paralelo en el sistema, cada uno con catálogo propio y
aislado — sin acoplar la skill a este repo de código.

**Implicancia de diseño:** el `SKILL.md` y los scripts deben resolver rutas siempre
relativas a `cwd`, nunca a la ubicación de instalación de la skill. Falta definir si
la skill debe *auto-detectar* una carpeta de librería existente subiendo directorios,
o si asume que siempre se invoca parada ya en la raíz de la librería (a confirmar
más adelante si hace falta).

### #2 — Formato del catálogo
**CSV**, no markdown ni JSON: parseo determinístico con librería estándar, sin
ambigüedades de escaping, y más compacto en tokens si el agente necesita leerlo
crudo (aunque el uso normal es vía scripts que devuelven resúmenes).

Se separa en **dos CSV normalizados**, unidos por `video_id`, para soportar múltiples
formatos de conversión del mismo tema sin duplicar metadata ni forzar una sola
conversión por fila:

- **`catalog.csv`** (una fila por canción — identidad):
  `video_id, song, artist, duration_sec, source_url, download_date, notes`
- **`files.csv`** (una fila por archivo físico — original o conversión):
  `video_id, kind, format, bitrate, size_bytes, path, created_date`
  (`kind` = `original` | `converted`)

El chequeo de dedup (¿ya tengo esta canción?) sólo consulta `catalog.csv` por
`video_id`; agregar un nuevo formato de conversión es simplemente una fila nueva en
`files.csv`.

### #3 — Plantilla de nombres de archivo y carpetas
- **Artista**: siempre el artista principal, uno solo por carpeta. Colaboraciones se
  reflejan dentro del nombre de la canción, ej. `Canción (feat. Pirulito) - Artista.ext`,
  nunca como carpeta compuesta.
- **Sanitización**: cualquier carácter no apto para filesystem (`/`, `:`, `?`, `*`,
  emojis, etc.) se reemplaza por `-`.
- **Originals**: `originals/<Artista>/<Canción> - <Artista>.<ext>`
- **Converted**: misma estructura, agrupada primero por `[formato-calidad]/`:
  `converted/<formato-calidad>/<Artista>/<Canción> - <Artista>.<ext>`
  (ej. `converted/mp3-192/Canticuénticos/Chacarera Jeringosa - Canticuénticos.mp3`)

### #4 — Estrategia de búsqueda y filtros
- `search.py` trae **20 resultados** por defecto vía `ytsearch20:<query>` con
  `--flat-playlist --dump-json` (metadata only, sin descargar), y aplica el filtro
  determinístico de duración (rango numérico) que haya pedido el usuario.
- **La búsqueda NO decide ni descarga automáticamente.** El script solo filtra por
  duración y devuelve metadata cruda (título, canal, duración, vistas, formatos/
  calidad disponibles). El **agente** analiza esos resultados con criterio: si el
  canal parece oficial, si el título sugiere una versión "pura" vs. contenido
  derivado (reaction, cover, full album, lyrics, etc.), calidad disponible — y arma
  una **propuesta de qué descargar**.
- El usuario **itera** sobre esa propuesta antes de que se dispare cualquier
  descarga: puede pedir refinar la búsqueda, descartar resultados puntuales, o
  aprobar la selección final. Recién ahí se invoca `download.py` sobre los videos
  confirmados.

### #5 — Dedup contra el catálogo
El script de búsqueda **no cruza contra el catálogo ni decide duplicados**: solo
sabe buscar y devolver resultados con su metadata. El cruce contra `catalog.csv`
(¿ya la tengo? ¿es la misma canción con otro `video_id`/upload?) queda **a criterio
del agente**, leyendo el catálogo directamente — sin fuzzy-matching automático ni
lógica de similitud embebida en un script. Esto evita falsos negativos/positivos de
un matcher rígido y aprovecha que el agente ya tiene que mirar los resultados de
búsqueda de todos modos (decisión #4).

### #11 — Lenguaje de los scripts
**Python 3**, sin dependencias más allá de la stdlib para lo posible (`csv`, `json`,
`subprocess`, `pathlib`). Motivos: yt-dlp ya está escrito en Python (posibilidad de
usar su API directamente si hace falta), Python3 viene preinstalado en macOS, y no
requiere paso de `npm install`/build para una skill que se invoca desde cualquier
carpeta del sistema. Dependencias opcionales puntuales (ej. `mutagen` para tags) se
evalúan por separado si se confirman.

### #6 — Calidad/formato de descarga original
Se baja siempre con `-f bestaudio -x`: la **mejor calidad disponible**, en su
formato/códec nativo, **sin forzar re-encode ni contenedor específico**. Sin piso
mínimo de calidad ni advertencias — se registra en `files.csv` el `format`/`bitrate`
real obtenido y queda ahí, a la vista en el catálogo.

### #7 — Conversión opcional
- **Default: MP3 192kbps** (objetivo final: compatibilidad con hardware viejo).
- **Regla de conversión** (`convert.py` vía `ffprobe`): se convierte salvo que el
  original **ya sea MP3 con bitrate ≤ 192kbps** (ahí se saltea). Si el formato
  original es distinto de MP3 (webm/opus/m4a/etc.), **se convierte siempre**,
  independientemente del bitrate — porque el objetivo no es solo "no bajar calidad"
  sino terminar en un contenedor MP3 compatible.
- **La conversión es un paso posterior y opcional a la descarga**, nunca automática
  en el mismo paso. Flujo completo:
  1. Usuario pide algo tipo "bajá 5 canciones que no tenga de María Elena Walsh, de
     menos de 5 min".
  2. Agente busca (`search.py`), cruza contra `catalog.csv` (decisión #5), propone
     candidatas.
  3. Usuario refina conversacionalmente (descarta, pide más opciones, etc.) y
     confirma la selección final.
  4. Se descargan los originales confirmados (`download.py`), se actualiza
     `catalog.csv`/`files.csv`.
  5. Agente muestra resultado de las descargas (n archivos, con su calidad/formato).
  6. Agente **pregunta** si se quiere convertir (sugiriendo MP3 192kbps u otro
     formato/bitrate a pedido). El usuario puede rechazar este paso.
  7. Si acepta, se corre `convert.py` sobre lo descargado y se actualiza
     `files.csv` con las nuevas filas de conversión.

### #8 — Tagging ID3 automático
**Sí**, con `mutagen` (única dependencia externa por ahora, vía `pip`). Al convertir
(paso 7 del flujo), `convert.py` escribe tags de título/artista en el MP3 resultante
usando los datos ya normalizados del catálogo — para que los archivos sean usables
directamente en cualquier reproductor/librería musical sin depender del nombre de
archivo.

### #9 — Manejo de errores y casos raros
- **Descarga individual falla** (video privado, geo-bloqueo, red): **1 reintento
  automático**, y si vuelve a fallar se marca como fallida y se **continúa con el
  resto** del lote — no se frena todo por un ítem.
- **Conversión falla** (ffmpeg, formato raro/corrupto): mismo criterio, se continúa
  con el resto.
- En ambos casos, al terminar el lote se **reporta un resumen** con éxitos y
  fallos (qué falló y por qué), no solo silenciar el error.

### #10 — Nivel de confirmación / principio de orquestación
Ambos casos puntuales requieren confirmación explícita: crear la estructura de
librería (`originals/`, `converted/`, `catalog.csv`) si no existe en el cwd, y
renombrar/reorganizar en bloque audios preexistentes que no siguen la convención.

Esto refleja un **principio general de diseño** para todo el `SKILL.md`: los
scripts hacen cosas puntuales y determinísticas (buscar, descargar, convertir,
leer/escribir catálogo), pero **toda la orquestación la hace el agente**, siguiendo
guías y defaults documentados en la skill — no lógica rígida hardcodeada. Esto
permite que, sesión a sesión, el usuario pueda pedir alterar levemente el workflow
default (saltear un paso, cambiar un orden, usar otro criterio puntual) sin que la
skill se lo impida por estar todo automatizado de punta a punta.
