// PostToolUse: formatea con Prettier el archivo recién editado.
// Nunca bloquea: si Prettier no soporta el archivo o falla, solo avisa.
// Se llama a Prettier con el mismo Node y sin shell, para que una ruta rara no ejecute nada.
import { spawnSync } from "node:child_process";
import path from "node:path";
import { projectDir, readEvent, relativePath } from "./lib.mjs";

const event = readEvent();
const rel = relativePath(event, event.tool_input?.file_path);

if (rel && !rel.startsWith("..") && /\.(ts|tsx|js|mjs|cjs|jsx|json|css|md|ya?ml)$/.test(rel)) {
  const cwd = projectDir(event);
  const prettier = path.join(cwd, "node_modules", "prettier", "bin", "prettier.cjs");
  const result = spawnSync(process.execPath, [prettier, "--write", "--ignore-unknown", "--", rel], {
    cwd,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    process.stderr.write(`Prettier no pudo formatear ${rel}: ${result.stderr ?? ""}\n`);
  }
}
