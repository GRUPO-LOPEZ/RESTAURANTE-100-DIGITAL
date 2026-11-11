// Prueba el hook que baja los cambios del repositorio al abrir Claude Code.
// Arma un "GitHub" de mentira (repositorio bare) con dos copias en una carpeta temporal.
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

const hook = path.resolve(__dirname, "../../.claude/hooks/sync-repo.sh");

let tmp: string;
let remote: string;
let soy: string;
let joaco: string;

function git(cwd: string, ...args: string[]): string {
  const result = spawnSync("git", args, { cwd, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`git ${args.join(" ")}: ${result.stderr}`);
  return result.stdout.trim();
}

function commit(cwd: string, file: string, text: string) {
  writeFileSync(path.join(cwd, file), text);
  git(cwd, "add", file);
  git(cwd, "commit", "-q", "-m", `cambio ${file}`);
}

function runHook(cwd: string): { status: number; message: string } {
  const result = spawnSync("sh", [hook], {
    input: JSON.stringify({ hook_event_name: "SessionStart", source: "startup", cwd }),
    env: { ...process.env, CLAUDE_PROJECT_DIR: cwd },
    encoding: "utf8",
  });
  const parsed = JSON.parse(result.stdout) as { systemMessage: string };
  return { status: result.status ?? -1, message: parsed.systemMessage };
}

beforeEach(() => {
  tmp = mkdtempSync(path.join(os.tmpdir(), "sync-repo-"));
  remote = path.join(tmp, "remote.git");
  soy = path.join(tmp, "soy");
  joaco = path.join(tmp, "joaco");
  git(tmp, "init", "-q", "--bare", "-b", "main", remote);
  git(tmp, "clone", "-q", remote, joaco);
  git(joaco, "config", "user.email", "prueba@example.com");
  git(joaco, "config", "user.name", "Prueba");
  git(joaco, "symbolic-ref", "HEAD", "refs/heads/main");
  commit(joaco, "a.txt", "uno");
  git(joaco, "push", "-q", "-u", "origin", "main");
  git(tmp, "clone", "-q", remote, soy);
  git(soy, "config", "user.email", "prueba@example.com");
  git(soy, "config", "user.name", "Prueba");
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe("sync-repo: bajar cambios al abrir", () => {
  it("avisa que está al día cuando no hay nada nuevo", () => {
    const { status, message } = runHook(soy);
    expect(status).toBe(0);
    expect(message).toContain("al día");
  });

  it("baja los cambios nuevos de GitHub", () => {
    commit(joaco, "b.txt", "dos");
    git(joaco, "push", "-q");
    const { status, message } = runHook(soy);
    expect(status).toBe(0);
    expect(message).toContain("se bajaron 1 cambio");
    expect(git(soy, "rev-parse", "HEAD")).toBe(git(joaco, "rev-parse", "HEAD"));
  });

  it("no pisa archivos modificados sin commitear", () => {
    commit(joaco, "b.txt", "dos");
    git(joaco, "push", "-q");
    writeFileSync(path.join(soy, "a.txt"), "trabajo sin guardar");
    const before = git(soy, "rev-parse", "HEAD");
    const { status, message } = runHook(soy);
    expect(status).toBe(0);
    expect(message).toContain("sin commitear");
    expect(git(soy, "rev-parse", "HEAD")).toBe(before);
  });

  it("no mezcla nada si la rama local y la remota se separaron", () => {
    commit(joaco, "b.txt", "dos");
    git(joaco, "push", "-q");
    commit(soy, "c.txt", "local");
    const before = git(soy, "rev-parse", "HEAD");
    const { status, message } = runHook(soy);
    expect(status).toBe(0);
    expect(message).toContain("se separaron");
    expect(git(soy, "rev-parse", "HEAD")).toBe(before);
  });

  it("sin conexión a GitHub, avisa y no falla", () => {
    git(soy, "remote", "set-url", "origin", path.join(tmp, "no-existe.git"));
    const { status, message } = runHook(soy);
    expect(status).toBe(0);
    expect(message).toContain("no se pudo consultar");
  });
});
