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

  it("la API expone los esquemas de negocio decididos, nunca audit, y staging los hereda", () => {
    const schemas = tomlSection(config, "api").schemas ?? "";
    for (const schema of ["core", "org", "workflow", "catalog"]) {
      expect(schemas).toContain(`"${schema}"`);
    }
    expect(schemas).not.toContain('"audit"');
    expect(tomlSection(config, "remotes.staging.api").schemas).toBeUndefined();
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
    // En el equipo de staging, no en la cuenta personal del dueño del token.
    expect(appJob).toContain(`vercel inspect ${siteHost} --scope "$VERCEL_ORG_ID"`);
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

  it("el job de la app saca el proyecto de config.toml, no de una salida de la base", () => {
    // GitHub vacía las salidas de un job que coinciden con un secreto: el proyecto de staging
    // es igual a STAGING_PROJECT_REF, así que nunca puede viajar como salida.
    expect(workflow).not.toContain("needs.base.outputs.project_ref");
    const [, outputs = ""] = /^ {4}outputs:\n((?: {6}.+\n)+)/m.exec(baseJob) ?? [];
    expect(outputs.trim().split("\n")).toEqual(["sha: ${{ steps.commit.outputs.sha }}"]);
    expect(appJob).toMatch(/\[remotes\\\.staging\\\]/);
    expect(appJob).toContain("supabase/config.toml");
  });

  it("de Vercel acepta solo las 2 variables públicas y las del sistema", () => {
    const [, pattern = ""] = /grep -Ev '(.+?)' "\$vars"/.exec(appJob) ?? [];
    const allowed = new RegExp(pattern);
    // Lo que agrega Vercel por su cuenta (VERCEL="1" incluido) y nuestras dos variables.
    for (const line of [
      'VERCEL="1"',
      'VERCEL_ENV="production"',
      'VERCEL_TARGET_ENV="production"',
      'TURBO_CACHE="remote:rw"',
      'NX_DAEMON="false"',
      'NEXT_PUBLIC_SUPABASE_URL="https://x.supabase.co"',
      'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="sb_publishable_x"',
    ]) {
      expect(allowed.test(line), line).toBe(true);
    }
    // Una clave de servidor nunca pasa, aunque empiece parecido.
    for (const line of [
      'SUPABASE_SERVICE_ROLE_KEY="x"',
      'VERCELX="x"',
      'NEXT_PUBLIC_SUPABASE_SECRET="x"',
    ]) {
      expect(allowed.test(line), line).toBe(false);
    }
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

describe("Staging: recetas de prueba (la prueba de la Fase 2 para Soy)", () => {
  const script = read("supabase/staging/demo-recipes.sql");

  it("se cargan solo a mano, con la opción tildada, y sin las contraseñas de la demo", () => {
    const step =
      baseJob
        .slice(baseJob.indexOf("name: Cargar materias primas, precios y recetas de prueba"))
        .split("- name:")[0] ?? "";
    expect(step).toContain(
      "if: github.event_name == 'workflow_dispatch' && inputs.load_demo_recipes",
    );
    expect(step).toContain("psql -X --no-password -f supabase/staging/demo-recipes.sql");
    // Exactamente estas variables: ni las contraseñas de la demo ni el token de Supabase.
    const env = [...step.matchAll(/^ {10}(\w+):/gm)].map(([, name]) => name).sort();
    expect(env).toEqual(["PGPASSWORD", "PGSSLMODE", "STAGING_DB_URL"]);
    // Corre en la base de staging, después de comprobar que el destino es staging.
    expect(baseJob.indexOf("name: Verificar que el destino es staging")).toBeGreaterThan(-1);
    expect(
      baseJob.indexOf("name: Cargar materias primas, precios y recetas de prueba"),
    ).toBeGreaterThan(baseJob.indexOf("name: Verificar que el destino es staging"));
  });

  it("el script frena sin el grupo de prueba, no repite la carga y es todo o nada", () => {
    expect(script).toContain("\\set ON_ERROR_STOP on");
    expect(script).toContain("Falta el Grupo Demo");
    expect(script).toContain("ya estaba cargada: no se cambia nada");
    expect(script).toMatch(/^begin;$/m);
    expect(script).toMatch(/^ {2}commit;$/m);
    // Solo datos inventados: precios de prueba y proveedores marcados como ficticios.
    expect(script).toContain("'test_value'");
    expect(script).not.toMatch(/service_role|encrypted_password|auth\.users/);
  });
});

describe("Staging: compras de prueba (la prueba de la Fase 3 para Soy)", () => {
  const script = read("supabase/staging/demo-purchasing.sql");
  const stepOf = (name: string) =>
    baseJob.slice(baseJob.indexOf(`name: ${name}`)).split("- name:")[0] ?? "";
  const load = stepOf("Cargar compras, facturas y pagos de prueba");
  const photos = stepOf("Subir las fotos de prueba");

  it("se cargan solo a mano, con la opción tildada, después de las recetas y sin otras claves", () => {
    for (const step of [load, photos]) {
      expect(step).toContain(
        "if: github.event_name == 'workflow_dispatch' && inputs.load_demo_purchasing",
      );
    }
    // Ensayar (DRY_RUN) no sube fotos.
    expect(photos).toContain("&& !inputs.demo_purchasing_dry_run");
    expect(load).toContain('if [ "$DRY" = "true" ]; then export DRY_RUN=1; fi');
    expect(load).toContain("-f supabase/staging/demo-purchasing.sql");
    const envOf = (step: string) =>
      [...step.matchAll(/^ {10}(\w+):/gm)].map(([, name]) => name).sort();
    expect(envOf(load)).toEqual(["DRY", "FILES_OUT", "PGPASSWORD", "PGSSLMODE", "STAGING_DB_URL"]);
    // Las fotos solo con el token de la CLI: ni la base ni las contraseñas de la demo. Y solo si el proyecto
    // conectado es el de staging que se verificó.
    expect(envOf(photos)).toEqual(["EXPECTED_REF", "SUPABASE_ACCESS_TOKEN"]);
    expect(photos).toContain("EXPECTED_REF: ${{ steps.target.outputs.project_ref }}");
    expect(photos).toContain('"$(cat supabase/.temp/project-ref 2>/dev/null)" != "$EXPECTED_REF"');
    const at = (name: string) => baseJob.indexOf(`name: ${name}`);
    expect(at("Cargar compras, facturas y pagos de prueba")).toBeGreaterThan(
      at("Cargar materias primas, precios y recetas de prueba"),
    );
    expect(at("Subir las fotos de prueba")).toBeGreaterThan(
      at("Cargar compras, facturas y pagos de prueba"),
    );
  });

  it("sube solo la imagen de prueba, al bucket de compras y a rutas del Grupo Demo", () => {
    expect(photos).toContain("supabase/staging/factura-de-prueba.jpg");
    expect(photos).toContain('"ss:///purchasing-documents/$path"');
    expect(photos).toContain("^00000000-0000-4000-8000-000000000001/");
    // Las órdenes de la CLI: de a un archivo, en el proyecto conectado (el de staging).
    const cli = photos.split("\n").filter((l) => l.includes("supabase storage"));
    expect(cli).toHaveLength(2);
    for (const line of cli) {
      expect(line).toContain("--linked");
      expect(line).not.toMatch(/ (--local|--recursive|-r)( |$)/);
    }
  });

  it("el script frena sin la Fase 2, no repite la carga y es todo o nada", () => {
    expect(script).toContain("\\set ON_ERROR_STOP on");
    expect(script).toContain("Falta la prueba de la Fase 2");
    expect(script).toContain("ya estaba cargada: no se cambia nada");
    expect(script).toMatch(/^begin;$/m);
    expect(script).toMatch(/^ {2}commit;$/m);
    // Solo datos inventados y con las funciones de la app: nada de usuarios, claves ni escrituras directas en compras.
    expect(script).not.toMatch(/service_role|encrypted_password|auth\.users/);
    expect(script).not.toMatch(
      /insert into purchasing\.(invoices|payments|price_lists|purchase_orders|receipts)/,
    );
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
