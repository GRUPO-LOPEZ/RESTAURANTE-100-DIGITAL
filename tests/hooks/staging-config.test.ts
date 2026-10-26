// Vigila la publicación en staging (ADR-0018): solo después de las pruebas, sin los datos de
// prueba locales, sin claves en el repositorio y con los límites normales de Supabase.
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const root = path.resolve(__dirname, "../..");
const read = (file: string) => readFileSync(path.join(root, file), "utf8");

// Lector mínimo de supabase/config.toml: devuelve las claves de una sección, sin comentarios.
function tomlSection(toml: string, name: string): Record<string, string> {
  const values: Record<string, string> = {};
  let inside = false;
  for (const raw of toml.split(/\r?\n/)) {
    const line = raw.replace(/\s+#.*$/, "").trim();
    if (!line || line.startsWith("#")) continue;
    const header = /^\[(.+)\]$/.exec(line);
    if (header) {
      inside = header[1] === name;
      continue;
    }
    const [, key, value] = /^([\w-]+)\s*=\s*(.+)$/.exec(line) ?? [];
    if (inside && key && value) values[key] = value.replace(/^"(.*)"$/, "$1");
  }
  return values;
}

// Solo el código: los comentarios pueden nombrar lo prohibido para explicarlo.
const withoutComments = (text: string, marker: string) =>
  text
    .split(/\r?\n/)
    .filter((line) => !line.trim().startsWith(marker))
    .join("\n");

const config = read("supabase/config.toml");
const workflow = withoutComments(read(".github/workflows/deploy-staging.yml"), "#");
const demoData = withoutComments(read("supabase/staging/demo-data.sql"), "--");

describe("Staging: configuración de Supabase", () => {
  it("[remotes.staging] apunta a un proyecto y no carga el seed local", () => {
    expect(tomlSection(config, "remotes.staging").project_id).toMatch(/^[a-z]{20}$/);
    expect(tomlSection(config, "remotes.staging.db.seed").enabled).toBe("false");
  });

  it("usa los límites normales de ingreso, no los de local y CI", () => {
    const limits = tomlSection(config, "remotes.staging.auth.rate_limit");
    expect(Number(limits.sign_in_sign_ups)).toBeLessThanOrEqual(30);
    expect(Number(limits.token_verifications)).toBeLessThanOrEqual(30);
  });

  it("las direcciones de Auth son https", () => {
    const auth = tomlSection(config, "remotes.staging.auth");
    expect(auth.site_url).toMatch(/^https:\/\//);
    expect(auth.additional_redirect_urls).not.toMatch(/http:\/\//);
  });
});

describe("Staging: flujo de publicación", () => {
  it("publica solo después de que 'Pruebas' termina en verde sobre main", () => {
    expect(read(".github/workflows/ci.yml")).toMatch(/^name: Pruebas$/m);
    expect(workflow).toMatch(/workflows: \[Pruebas\]/);
    expect(workflow).toContain("github.event.workflow_run.conclusion == 'success'");
    expect(workflow).toContain("branches: [main]");
  });

  it("verifica que el destino sea el proyecto de [remotes.staging]", () => {
    expect(workflow).toMatch(/\[remotes\\\.staging\\\]/);
  });

  it("nunca carga el seed local ni usa la clave service_role", () => {
    expect(workflow).not.toContain("--include-seed");
    expect(workflow).not.toContain("seed.sql");
    expect(workflow).not.toMatch(/service_role/i);
  });

  it("publica la app recién después de la base, las funciones y la configuración", () => {
    const app = workflow.indexOf("vercel@");
    for (const step of ["db push", "functions deploy", "config push"]) {
      expect(workflow.indexOf(step)).toBeGreaterThan(-1);
      expect(workflow.indexOf(step)).toBeLessThan(app);
    }
  });

  it("las claves salen de los secretos de GitHub", () => {
    for (const name of ["SUPABASE_ACCESS_TOKEN", "SUPABASE_DB_PASSWORD", "VERCEL_TOKEN"]) {
      expect(workflow).toContain(`\${{ secrets.${name} }}`);
    }
  });
});

describe("Staging: datos de prueba", () => {
  it("no trae la contraseña, el secreto TOTP ni las cuentas del seed local", () => {
    expect(demoData).not.toContain("Demo-Local-2026!");
    expect(demoData).not.toContain("JBSWY3DPEHPK3PXP");
    expect(demoData).not.toContain("mfa_factors");
    expect(demoData).not.toContain("e2e-");
  });

  it("la contraseña llega por variable y se usa en una sola sentencia", () => {
    const uses = demoData.match(/:'demo_password'/g) ?? [];
    // Una para validar el largo y otra para calcular el hash.
    expect(uses).toHaveLength(2);
    expect(demoData).toMatch(/extensions\.crypt\(:'demo_password'/);
  });

  it("aborta sobre una base con otros datos", () => {
    expect(demoData).toMatch(
      /exists \(select 1 from org\.groups\) or exists \(select 1 from auth\.users\)/,
    );
  });
});
