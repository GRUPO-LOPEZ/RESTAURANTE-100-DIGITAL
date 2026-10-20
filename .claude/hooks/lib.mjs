// Utilidades compartidas por los hooks de Claude Code.
// Un hook recibe por stdin el JSON del evento. Para bloquear una acción
// se escribe el motivo en stderr y se sale con código 2.
import { readFileSync } from "node:fs";
import path from "node:path";

export function readEvent() {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return {};
  }
}

export function projectDir(event) {
  return process.env.CLAUDE_PROJECT_DIR || event.cwd || process.cwd();
}

// Ruta relativa al proyecto, siempre con "/".
export function relativePath(event, filePath) {
  if (!filePath) return "";
  const rel = path.relative(projectDir(event), path.resolve(projectDir(event), filePath));
  return rel.split(path.sep).join("/");
}

export function block(reason) {
  process.stderr.write(`Bloqueado por un hook del proyecto: ${reason}\n`);
  process.exit(2);
}
