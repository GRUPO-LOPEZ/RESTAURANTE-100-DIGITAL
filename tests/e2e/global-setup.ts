import { execSync } from "node:child_process";

// Antes de las pruebas de flujo: base local recién creada con el seed, para que los bloqueos y
// las bajas de una corrida anterior no afecten a esta. Se puede saltear con E2E_SKIP_RESET=1
// (por ejemplo, en CI, que ya la recreó en un paso anterior).
export default function globalSetup() {
  if (process.env.E2E_SKIP_RESET === "1") return;
  execSync("npx supabase db reset", { stdio: "inherit" });
}
