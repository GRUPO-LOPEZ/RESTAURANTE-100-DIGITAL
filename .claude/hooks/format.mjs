// PostToolUse: formatea con Prettier el archivo recién editado.
// Nunca bloquea: si Prettier no soporta el archivo o falla, solo avisa.
import { spawnSync } from "node:child_process";
import { projectDir, readEvent, relativePath } from "./lib.mjs";

const event = readEvent();
const rel = relativePath(event, event.tool_input?.file_path);

if (rel && !rel.startsWith("..") && /\.(ts|tsx|js|mjs|cjs|jsx|json|css|md|ya?ml)$/.test(rel)) {
  const result = spawnSync("npx", ["prettier", "--write", "--ignore-unknown", rel], {
    cwd: projectDir(event),
    encoding: "utf8",
    shell: process.platform === "win32",
  });
  if (result.status !== 0) {
    process.stderr.write(`Prettier no pudo formatear ${rel}: ${result.stderr ?? ""}\n`);
  }
}
