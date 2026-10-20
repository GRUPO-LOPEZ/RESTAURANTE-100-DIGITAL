// PreToolUse: una migración que ya está en un commit no se edita.
// Para corregirla se crea una migración nueva (prompt maestro, secciones 3 y 4).
import { execFileSync } from "node:child_process";
import { block, projectDir, readEvent, relativePath } from "./lib.mjs";

const event = readEvent();
const rel = relativePath(event, event.tool_input?.file_path);

if (/^supabase\/migrations\/.+\.sql$/.test(rel)) {
  let committed = false;
  try {
    execFileSync("git", ["cat-file", "-e", `HEAD:${rel}`], {
      cwd: projectDir(event),
      stdio: "ignore",
    });
    committed = true;
  } catch {
    committed = false;
  }
  if (committed) {
    block(
      `${rel} ya está commiteada. No se edita: creá una migración nueva con "npx supabase migration new <nombre>".`,
    );
  }
}
