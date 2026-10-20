// PreToolUse: una migración que ya está en un commit no se edita.
// Para corregirla se crea una migración nueva (prompt maestro, secciones 3 y 4).
// La comparación ignora mayúsculas porque en Windows "Supabase/Migrations" es la misma carpeta.
// CI repite este control para cambios hechos por fuera de Claude Code.
import { execFileSync } from "node:child_process";
import { block, projectDir, readEvent, relativePath } from "./lib.mjs";

const event = readEvent();
const rel = relativePath(event, event.tool_input?.file_path).toLowerCase();

if (/^supabase\/migrations\/.+\.sql$/.test(rel)) {
  let committed = [];
  try {
    committed = execFileSync(
      "git",
      ["ls-tree", "-r", "--name-only", "HEAD", "--", "supabase/migrations"],
      { cwd: projectDir(event), encoding: "utf8" },
    )
      .split("\n")
      .map((file) => file.trim().toLowerCase());
  } catch {
    committed = [];
  }
  if (committed.includes(rel)) {
    block(
      `${rel} ya está commiteada. No se edita: creá una migración nueva con "npx supabase migration new <nombre>".`,
    );
  }
}
