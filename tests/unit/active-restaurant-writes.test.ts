// El local aplicado arriba nunca decide una escritura (ADR-0048). Un enlace con ?local= lo cambia al llegar, así que
// ninguna acción de servidor que escribe puede tomarlo como valor por defecto: cada escritura recibe su local explícito.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

function actionFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return actionFiles(path);
    return /actions\.tsx?$/.test(name) ? [path] : [];
  });
}

describe("el local aplicado no decide escrituras", () => {
  const files = actionFiles(join(process.cwd(), "app"));

  it("hay acciones para revisar", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  it("ninguna acción lee el local aplicado", () => {
    const offenders = files.filter((f) =>
      /getActiveRestaurantId|my_active_restaurant|last_restaurant_id/.test(readFileSync(f, "utf8")),
    );
    expect(offenders).toEqual([]);
  });
});
