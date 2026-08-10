# Wayfinder map — skill de unificación de skills entre agentes locales

## Destino
Una skill que audite y repare el setup que permite que Claude Code, Codex,
Gemini CLI, Pi/DeepSeek (y cualquier agente nuevo) usen las skills de
`~/code/agent-skills` directamente, sin copias duplicadas que diverjan — el
mismo trabajo que se hizo a mano en una sesión real, ahora repetible.

## Decisiones

### Ubicación del path del repo
El path del clone (`~/code/agent-skills` por default) es específico de cada
máquina — no puede vivir *dentro* del repo (contaminaría el git history con
paths de una sola máquina) ni asumirse fijo. Se guarda en
`~/.agents/agent-skills.json`, al lado del `.skill-lock.json` que ya usa el
instalador de skills de terceros — mismo directorio, mismo criterio ("estado
de esta máquina, no versionado, compartido entre todas las herramientas que ya
miran `~/.agents/`").

Resolución en `find_repo.py`: explícito (`--path`) > estado guardado >
default (`~/code/agent-skills`) > búsqueda (`--search`) por remote matcheando
un hint (default: "agent-skills") bajo `~/code`, `~/dev`, `~/projects`,
`~/repos`. La búsqueda nunca es el paso 1 — es cara y ambigua (puede haber
varios repos con "agent-skills" en el remote) — solo se ofrece si el default
falla y el usuario no tiene el path a mano.

### Dos niveles: hub + directorio por herramienta
`~/.agents/skills` existe como capa intermedia para que una herramienta con
directorio propio (`~/.claude/skills`, `~/.codex/skills`, `~/.pi/agent/skills`)
tenga *un* lugar estable al que apuntar cada skill, sin saber nada de dónde
vive el repo. Si el repo se muda, solo hace falta actualizar los symlinks del
hub — los symlinks de cada herramienta hacia el hub no cambian.

### Dos modos por herramienta (`per_skill_symlink` vs `hub_alias`)
Descubierto en la sesión real: no todas las herramientas resuelven skills
igual.

- **`per_skill_symlink`** (Claude Code, Codex, Pi): la herramienta tiene su
  propio directorio de skills con una entrada nombrada por skill. Necesita un
  symlink por skill apuntando al hub.
- **`hub_alias`** (Gemini CLI): la herramienta lee `~/.agents/skills/` como un
  alias nativo de primera clase — literalmente documentado así en
  `bundle/docs/cli/skills.md` del paquete instalado, con *más* precedencia que
  su propia carpeta `~/.gemini/skills/`. No necesita ningún symlink por skill;
  alcanza con que el hub esté sano. Confirmable con `gemini skills list --all`.

### El fallback de descubrimiento (cómo se encontró lo de Gemini, en los hechos)
La primera hipótesis fue "Gemini no tiene mecanismo de skills" — conclusión
apurada por no encontrar una carpeta `~/.gemini/skills` poblada ni menciones en
su config (`settings.json`, `system.md`). La manera real en que se encontró la
respuesta fue:

1. Ubicar el binario (`which gemini`) y de ahí el paquete instalado
   (`npm root -g` + `@google/gemini-cli`).
2. Grepear ese paquete instalado por "skill" (case-insensitive) — encontró
   `bundle/docs/cli/skills.md`, que documenta el mecanismo completo, incluida
   la existencia del alias `~/.agents/skills/`.
3. Confirmar leyendo esa doc, no asumiendo — y verificar con el propio comando
   de la herramienta (`gemini skills list --all`), no solo con la inspección
   de archivos.

`discover_tools.py`'s `deep_scan()` automatiza los pasos 1-2 para cualquier
tool sin candidatos conocidos (o no en la tabla). El paso 3 —interpretar los
hits y confirmar con el comando propio de la herramienta si existe— sigue
siendo trabajo del agente: el script devuelve hits crudos, nunca una
conclusión ("installed", no "supports skills").

### Nunca pisar en silencio
`link_skill.py` se niega a tocar contenido real (no-symlink) salvo
`--replace`, y a repuntar un symlink que ya apunta a otro lado salvo
`--relink` — ambos gates pensados para cruzarse solo después de que
`diff_skill.py` mostró el diff real y el usuario confirmó explícitamente. Esto
refleja el mismo principio que `organize.py` en `youtube-audio-library`:
"reporta en vez de clobberear en silencio".

### Qué NO toca esta skill
Cualquier nombre presente en `~/.agents/.skill-lock.json` (skills de terceros
instaladas por el gestor externo) se marca `protected` en `inventory.py` y
nunca se propone como candidato a reemplazar — no son parte de este repo y
mezclar ambos mundos rompería lo que ese instalador gestiona.
