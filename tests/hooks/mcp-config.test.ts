// Vigila la configuración de MCP (ADR-0011): solo la base local, en solo lectura,
// y sin herramientas que cambien la base o muestren claves.
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const root = path.resolve(__dirname, "../..");
const SERVER = "supabase-local";

type McpConfig = { mcpServers?: Record<string, { type?: string; url?: string }> };
type Settings = { permissions: { allow: string[]; ask: string[]; deny: string[] } };

const readJson = <T>(file: string): T =>
  JSON.parse(readFileSync(path.join(root, file), "utf8")) as T;

// Devuelve los problemas de una configuración de MCP; vacío si cumple el ADR-0011.
function mcpProblems(config: McpConfig): string[] {
  const problems: string[] = [];
  for (const [name, server] of Object.entries(config.mcpServers ?? {})) {
    if (name !== SERVER) problems.push(`servidor no autorizado: ${name}`);
    let url: URL;
    try {
      url = new URL(server.url ?? "");
    } catch {
      problems.push(`${name}: sin URL válida`);
      continue;
    }
    if (!["localhost", "127.0.0.1"].includes(url.hostname))
      problems.push(`${name}: no es la base local (${url.hostname})`);
    if (url.searchParams.get("read_only") !== "true")
      problems.push(`${name}: no está en solo lectura`);
  }
  return problems;
}

describe("MCP: solo la base local en solo lectura", () => {
  it("la configuración del repositorio cumple el ADR-0011", () => {
    const config = readJson<McpConfig>(".mcp.json");
    expect(Object.keys(config.mcpServers ?? {})).toEqual([SERVER]);
    expect(mcpProblems(config)).toEqual([]);
  });

  it.each([
    ["la nube de Supabase", { [SERVER]: { url: "https://mcp.supabase.com/mcp?read_only=true" } }],
    ["sin solo lectura", { [SERVER]: { url: "http://localhost:54321/mcp" } }],
    ["solo lectura apagado", { [SERVER]: { url: "http://localhost:54321/mcp?read_only=false" } }],
    [
      "un servidor extra",
      {
        [SERVER]: { url: "http://localhost:54321/mcp?read_only=true" },
        otro: { url: "http://localhost:1/x?read_only=true" },
      },
    ],
    ["sin URL", { [SERVER]: {} }],
  ])("rechaza una configuración con %s", (_caso, mcpServers) => {
    expect(mcpProblems({ mcpServers })).not.toEqual([]);
  });
});

describe("MCP: permisos de Claude Code", () => {
  const { allow, ask, deny } = readJson<Settings>(".claude/settings.json").permissions;
  const tool = (name: string) => `mcp__${SERVER}__${name}`;

  it.each(["apply_migration", "get_publishable_keys"])("deniega %s", (name) => {
    expect(deny).toContain(tool(name));
    expect(allow).not.toContain(tool(name));
  });

  it("execute_sql siempre pide aprobación", () => {
    expect(ask).toContain(tool("execute_sql"));
    expect(allow).not.toContain(tool("execute_sql"));
  });

  it("no hay permisos generales sobre el servidor ni sobre otros MCP", () => {
    const mcpRules = [...allow, ...ask].filter((rule) => rule.startsWith("mcp__"));
    for (const rule of mcpRules) {
      expect(rule.startsWith(`mcp__${SERVER}__`)).toBe(true);
      expect(rule).not.toMatch(/\*$/);
    }
    expect(allow).not.toContain(`mcp__${SERVER}`);
  });
});
