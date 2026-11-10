// ADR-0037: el superadministrador de prueba sin doble verificación es temporal y nunca va a producción. Esta prueba lo
// recuerda: falla si el script aparece en un flujo que no sea el de staging, en una migración o en el seed.
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const root = path.resolve(import.meta.dirname, "../..");
const read = (file: string) => readFileSync(path.join(root, file), "utf8");
const files = (dir: string) =>
  readdirSync(path.join(root, dir)).map((name) => path.join(dir, name).replaceAll("\\", "/"));

describe("el superadministrador de prueba sin MFA (ADR-0037)", () => {
  it("solo lo crea el flujo de staging", () => {
    const using = files(".github/workflows").filter((f) =>
      /test-superadmin|load_test_admin/.test(read(f)),
    );
    expect(using).toEqual([".github/workflows/deploy-staging.yml"]);
  });

  it("no está en ninguna migración ni en el seed", () => {
    const sql = [...files("supabase/migrations"), "supabase/seed.sql"].filter((f) =>
      /superadmin_test|superadmin\.prueba/.test(read(f)),
    );
    expect(sql).toEqual([]);
  });

  it("el script se niega a correr fuera de la base del grupo ficticio", () => {
    const script = read("supabase/dev/test-superadmin.sql");
    expect(script).toContain("where id <> '00000000-0000-4000-8000-000000000001'");
    expect(script).toContain("\\unset test_admin_password");
    expect(script).not.toMatch(/Demo-Local-2026/);
  });
});
