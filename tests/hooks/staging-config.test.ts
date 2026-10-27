// Vigila la publicación en staging (ADR-0018): solo después de las pruebas, sin los datos de
// prueba locales, sin claves en el repositorio ni al alcance de código de terceros, y con los
// límites normales de Supabase.
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
const [baseJob = "", appJob = ""] = workflow.split(/^ {2}app:$/m);

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

  it("hereda el registro cerrado y sin ingresos anónimos", () => {
    const auth = tomlSection(config, "auth");
    expect(auth.enable_signup).toBe("false");
    expect(auth.enable_anonymous_sign_ins).toBe("false");
    const staging = tomlSection(config, "remotes.staging.auth");
    expect(staging.enable_signup).toBeUndefined();
    expect(staging.enable_anonymous_sign_ins).toBeUndefined();
  });
});

describe("Staging: cuándo se publica", () => {
  it("solo después de que 'Pruebas' termina en verde por un push a main", () => {
    expect(read(".github/workflows/ci.yml")).toMatch(/^name: Pruebas$/m);
    expect(workflow).toMatch(/workflows: \[Pruebas\]/);
    expect(workflow).toContain("branches: [main]");
    expect(baseJob).toContain("github.event.workflow_run.conclusion == 'success'");
    expect(baseJob).toContain("github.event.workflow_run.event == 'push'");
  });

  it("a mano, solo desde main y con 'Pruebas' en verde para ese commit", () => {
    expect(baseJob).toContain("github.ref == 'refs/heads/main'");
    expect(baseJob).toMatch(
      /actions\/workflows\/ci\.yml\/runs\?head_sha=\$SHA&event=push&status=success/,
    );
  });

  it("verifica que la base y la app de destino sean las de staging", () => {
    expect(baseJob).toMatch(/\[remotes\\\.staging\\\]/);
    expect(baseJob).toContain('[[ "$STAGING_DB_URL" =~ $pooler ]]');
    expect(appJob).toContain("NEXT_PUBLIC_SUPABASE_URL");
    // La dirección que se verifica es la misma que usa Auth para los enlaces.
    const siteHost = new URL(tomlSection(config, "remotes.staging.auth").site_url ?? "").host;
    expect(appJob).toContain(`vercel inspect ${siteHost}`);
  });

  it("acepta solo la conexión del pooler de staging, sin contraseña ni parámetros", () => {
    const ref = tomlSection(config, "remotes.staging").project_id ?? "";
    const [, pattern = ""] = /pooler="(.+)"$/m.exec(baseJob) ?? [];
    const pooler = new RegExp(pattern.replace("${expected}", ref));
    const host = "aws-1-sa-east-1.pooler.supabase.com:5432/postgres";
    expect(pooler.test(`postgresql://postgres.${ref}@${host}`)).toBe(true);
    expect(pooler.test(`postgresql://postgres.${ref}:clave@${host}`)).toBe(false);
    expect(pooler.test(`postgresql://postgres.${ref}@${host}?host=otro`)).toBe(false);
    expect(pooler.test(`postgresql://postgres.otroproyectoxxxxxxx@${host}`)).toBe(false);
    expect(pooler.test(`postgresql://postgres@db.${ref}.supabase.co:5432/postgres`)).toBe(false);
  });

  it("la app se publica recién después de la base, las funciones y la configuración", () => {
    expect(appJob).toMatch(/^ {4}needs: base$/m);
    // El comando completo: "supabasedb push" (sin espacio) no es un comando de la CLI.
    for (const step of [
      "link --project-ref",
      "db push --yes",
      "functions deploy auth-login invite-user",
      "config push --yes",
    ]) {
      expect(baseJob).toMatch(new RegExp(`^ {8}run: npx --no-install supabase ${step}`, "m"));
    }
    expect(baseJob).not.toContain("vercel");
  });
});

describe("Staging: claves y código de terceros", () => {
  it("nunca carga el seed local ni usa la clave service_role", () => {
    expect(workflow).not.toContain("--include-seed");
    expect(workflow).not.toContain("seed.sql");
    expect(workflow).not.toMatch(/secrets\.\w*service_role/i);
  });

  it("las claves se declaran paso por paso, nunca para todo el job", () => {
    for (const line of workflow.split("\n").filter((l) => l.includes("secrets."))) {
      const jobLevelId = /^ {6}VERCEL_(ORG|PROJECT)_ID: \$\{\{ secrets\.VERCEL_\1_ID \}\}$/;
      if (!jobLevelId.test(line)) expect(line).toMatch(/^ {10}\w+: \$\{\{ secrets\.\w+ \}\}$/);
    }
    expect(baseJob).toContain("${{ secrets.SUPABASE_ACCESS_TOKEN }}");
    expect(appJob).toContain("${{ secrets.VERCEL_TOKEN }}");
  });

  it("la app no ve ninguna clave de Supabase", () => {
    expect(appJob).not.toMatch(/SUPABASE_ACCESS_TOKEN|SUPABASE_DB_PASSWORD|STAGING_DB_URL|DEMO_/);
  });

  it("instalar y armar la app no ven el token de Vercel", () => {
    const step = (name: string) =>
      appJob.slice(appJob.indexOf(`name: ${name}`)).split("- name:")[0];
    expect(step("Instalar dependencias")).not.toContain("VERCEL_TOKEN");
    expect(step("Armar la app")).not.toContain("VERCEL_TOKEN");
  });

  it("las CLI salen del package-lock: versión exacta y nunca se bajan en el momento", () => {
    const pkg = JSON.parse(read("package.json")) as { devDependencies?: Record<string, string> };
    expect(pkg.devDependencies?.vercel).toMatch(/^\d+\.\d+\.\d+$/);
    expect(pkg.devDependencies?.supabase).toMatch(/^\d+\.\d+\.\d+$/);
    expect(workflow).not.toMatch(/npx (?!--no-install )/);
    expect(workflow).not.toMatch(/vercel@/);
    expect(workflow).not.toContain("--token");
  });

  it("solo el job de la base puede leer las corridas de 'Pruebas'", () => {
    expect(workflow.match(/actions: read/g) ?? []).toHaveLength(1);
    expect(baseJob).toContain("actions: read");
  });

  it("ninguna contraseña viaja en la línea de comando de psql", () => {
    expect(workflow).not.toMatch(/psql[^\n]*-v /);
  });
});

describe("Staging: datos de prueba", () => {
  it("no trae la contraseña, el secreto TOTP ni las cuentas del seed local", () => {
    expect(demoData).not.toContain("Demo-Local-2026!");
    expect(demoData).not.toContain("JBSWY3DPEHPK3PXP");
    expect(demoData).not.toContain("mfa_factors");
    expect(demoData).not.toContain("e2e-");
  });

  it("las contraseñas llegan por variables de entorno y se usan en una sola sentencia", () => {
    expect(demoData).toContain("\\getenv demo_admin_password DEMO_ADMIN_PASSWORD");
    expect(demoData).toContain("\\getenv demo_password DEMO_PASSWORD");
    for (const name of ["demo_admin_password", "demo_password"]) {
      expect(demoData.match(new RegExp(`:'${name}'`, "g")) ?? []).toHaveLength(1);
      expect(demoData).toContain(`extensions.crypt(:'${name}', extensions.gen_salt('bf', 10))`);
    }
  });

  it("los roles con doble verificación usan su propia contraseña", () => {
    expect(demoData).toContain(
      "case when r.requires_mfa then :'demo_admin_hash' else :'demo_hash' end",
    );
  });

  it("aborta sobre una base con otros datos", () => {
    expect(demoData).toMatch(
      /exists \(select 1 from org\.groups\) or exists \(select 1 from auth\.users\)/,
    );
  });
});
