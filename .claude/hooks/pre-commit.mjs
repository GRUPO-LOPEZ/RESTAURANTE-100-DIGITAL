// PreToolUse (Bash): antes de cada "git commit" corre el linter y los tipos.
// Si fallan, el commit queda bloqueado hasta arreglar la causa.
import { spawnSync } from "node:child_process";
import { block, projectDir, readEvent } from "./lib.mjs";

const event = readEvent();
const cmd = String(event.tool_input?.command ?? "");

if (/\bgit\s+commit\b/.test(cmd)) {
  for (const script of ["lint", "typecheck"]) {
    const result = spawnSync("npm", ["run", "--silent", script], {
      cwd: projectDir(event),
      encoding: "utf8",
      shell: process.platform === "win32",
    });
    if (result.status !== 0) {
      const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim().slice(-3000);
      block(`"npm run ${script}" falló. Arreglá la causa antes de commitear.\n${output}`);
    }
  }
}
