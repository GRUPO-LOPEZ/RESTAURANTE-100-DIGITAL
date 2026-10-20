// Prueba los hooks de Claude Code (.claude/hooks) con eventos simulados.
import { spawnSync } from "node:child_process";
import path from "node:path";
import { describe, expect, it } from "vitest";

const root = path.resolve(__dirname, "../..");
const ENV = ".e" + "nv"; // se arma así para que el propio guardián no bloquee este archivo

function run(hook: string, event: object): number {
  const result = spawnSync("node", [path.join(root, ".claude/hooks", `${hook}.mjs`)], {
    input: JSON.stringify(event),
    env: { ...process.env, CLAUDE_PROJECT_DIR: root },
    encoding: "utf8",
  });
  return result.status ?? -1;
}

const bash = (command: string) => ({
  tool_name: "Bash",
  tool_input: { command },
});
const read = (file_path: string) => ({
  tool_name: "Read",
  tool_input: { file_path },
});

describe("guard: secretos y ambientes remotos", () => {
  it.each([
    ["leer el archivo de variables", read(ENV)],
    ["leer variables locales de supabase", read(`supabase/${ENV}.local`)],
    [
      "editar variables de producción",
      { tool_name: "Edit", tool_input: { file_path: `${ENV}.production` } },
    ],
    ["cat del archivo de variables", bash(`cat ${ENV}`)],
    ["supabase link", bash("npx supabase link --project-ref abc")],
    ["db push remoto", bash("npx supabase db push --linked")],
    ["db url remota", bash("npx supabase db dump --db-url postgres://x")],
    ["push forzado", bash("git push -f origin main")],
    ["push --force", bash("git push --force origin main")],
    ["borrar rama remota", bash("git push origin --delete main")],
    ["deploy vercel", bash("npx vercel deploy --prod")],
    ["buscar archivos de variables", { tool_name: "Glob", tool_input: { pattern: `**/${ENV}*` } }],
    // Casos encontrados por security-auditor (2026-10-20)
    ["reset remoto vía npm run", bash("npm run db:reset -- --linked")],
    [
      "test db remoto vía npm run",
      bash("npm run test:db -- --db-url postgres://u@db.x.co/postgres"),
    ],
    ["db dump", bash("npx supabase db dump")],
    ["db pull", bash("npx supabase db pull")],
    ["functions deploy", bash("npx supabase functions deploy invitar")],
    ["supabase login", bash("npx supabase login")],
    ["migration list remoto", bash("npx supabase migration list")],
    ["gen types remoto", bash("npx supabase gen types typescript --project-id abc")],
    ["psql a host remoto", bash("psql postgresql://postgres:x@db.abc.supabase.co:5432/postgres")],
    ["push con +refspec", bash("git push origin +main")],
    ["push con -fu", bash("git push -fu origin main")],
    ["push con git -C", bash("git -C . push --force origin main")],
    ["git show del archivo de variables", bash(`git show HEAD:${ENV}.local`)],
    ["token de supabase", bash("cat ~/.supabase/access-token")],
    ["vercel pull", bash("npx vercel pull --environment=production")],
    ["leer credenciales de vercel", read(".vercel/project.json")],
    ["leer .npmrc", read(".npmrc")],
  ])("bloquea: %s", (_name, event) => {
    expect(run("guard", event)).toBe(2);
  });

  it.each([
    ["leer el ejemplo", read(`${ENV}.example`)],
    ["leer el README", read("README.md")],
    ["process.env en código", bash('node -e "console.log(process.env.HOME)"')],
    ["supabase local", bash("npx supabase db reset")],
    ["supabase test db", bash("npx supabase test db")],
    ["gen types local", bash("npx supabase gen types typescript --local --schema core")],
    ["git add de migraciones", bash("git add supabase/migrations/x.sql")],
    ["npm run db:reset", bash("npm run db:reset")],
    [
      "psql local",
      bash("psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c 'select 1'"),
    ],
    ["vercel --version", bash("npx vercel --version")],
    ["push normal", bash("git push -u origin chore/fase-0-entorno")],
    ["grep en app", { tool_name: "Grep", tool_input: { pattern: "env", path: "app" } }],
  ])("permite: %s", (_name, event) => {
    expect(run("guard", event)).toBe(0);
  });
});

describe("protect-migrations", () => {
  it("permite editar una migración que todavía no está commiteada", () => {
    const event = {
      tool_name: "Edit",
      tool_input: { file_path: "supabase/migrations/20990101000000_nueva.sql" },
    };
    expect(run("protect-migrations", event)).toBe(0);
  });

  it("bloquea editar una migración ya commiteada", () => {
    const committed = spawnSync("git", ["ls-files", "supabase/migrations/*.sql"], {
      cwd: root,
      encoding: "utf8",
    })
      .stdout.split("\n")
      .find(Boolean);
    expect(committed, "tiene que haber al menos una migración commiteada").toBeDefined();
    expect(
      run("protect-migrations", { tool_name: "Edit", tool_input: { file_path: committed } }),
    ).toBe(2);
  });

  it("bloquea aunque la ruta venga con otras mayúsculas (Windows)", () => {
    const committed = spawnSync("git", ["ls-files", "supabase/migrations/*.sql"], {
      cwd: root,
      encoding: "utf8",
    })
      .stdout.split("\n")
      .find(Boolean)!;
    const upper = committed.replace("supabase/migrations", "Supabase/Migrations");
    expect(run("protect-migrations", { tool_name: "Edit", tool_input: { file_path: upper } })).toBe(
      2,
    );
  });

  it("no afecta archivos fuera de migraciones", () => {
    expect(
      run("protect-migrations", {
        tool_name: "Edit",
        tool_input: { file_path: "README.md" },
      }),
    ).toBe(0);
  });
});
