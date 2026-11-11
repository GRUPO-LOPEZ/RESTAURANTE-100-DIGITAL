#!/bin/sh
# SessionStart: al abrir Claude Code (por ejemplo, al entrar a VS Code), baja los
# cambios nuevos del repositorio si los hay.
# Está en sh y no en Node a propósito: solo necesita git, así anda en cualquier
# compu que tenga el repositorio, aunque todavía no tenga Node instalado.
# Es conservador: nunca pisa trabajo local.
#   - Si hay archivos modificados sin commitear, no baja nada y avisa.
#   - Solo hace "fast-forward": si la rama local y la remota se separaron, avisa y no toca nada.
#   - Sin internet o sin rama remota, avisa y sigue.
# Nunca bloquea el inicio de la sesión: siempre sale con código 0.

cat >/dev/null 2>&1 # descarta el evento que llega por stdin
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
export GIT_TERMINAL_PROMPT=0

finish() {
  # Escapa el texto para JSON: barras, comillas y saltos de línea.
  json=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/ /g' -e 's/\r$//' | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')
  printf '{"systemMessage":"Repositorio: %s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Sincronización del repositorio al iniciar: %s"}}\n' "$json" "$json"
  exit 0
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || finish "no es un repositorio de git; no se buscaron cambios."

branch=$(git branch --show-current 2>/dev/null)
[ -n "$branch" ] || finish "no hay una rama activa; no se bajaron cambios."

git fetch --prune --quiet origin >/dev/null 2>&1 ||
  finish "no se pudo consultar GitHub (¿sin internet?); se trabaja con la copia local."

git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 ||
  finish "la rama \"$branch\" no tiene rama remota; no hay nada que bajar."

set -- $(git rev-list --left-right --count 'HEAD...@{u}')
ahead=${1:-0}
behind=${2:-0}

[ "$behind" -eq 0 ] && finish "la rama \"$branch\" ya estaba al día con GitHub."

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  finish "hay $behind cambio(s) nuevo(s) en GitHub para \"$branch\", pero no se bajaron porque hay archivos modificados sin commitear. Guardalos o descartalos y volvé a abrir."
fi

if [ "$ahead" -gt 0 ]; then
  finish "la rama \"$branch\" tiene $ahead commit(s) propio(s) y $behind nuevo(s) en GitHub: se separaron y no se bajó nada para no mezclar trabajo. Hay que resolverlo a mano."
fi

before=$(git rev-parse HEAD)
if ! err=$(git merge --ff-only --quiet '@{u}' 2>&1); then
  finish "no se pudieron bajar los cambios de \"$branch\": $(printf '%s' "$err" | head -n 1)"
fi

list=$(git log --oneline --no-decorate -n 10 "$before..HEAD" | sed 's/^/  • /')
finish "se bajaron $behind cambio(s) nuevo(s) en \"$branch\":
$list"
