import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";

// lib/data.ts crea el cliente de Supabase del servidor: acá solo interesan los nombres.
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn() }));

// El Historial y la ficha de la persona dicen qué cambió con el nombre de la tabla. Toda tabla con auditoría tiene el
// suyo: si no, la gente lee «Dato del sistema» (ADR-0062). Estas no llevan auditoría de cambios:
const UNAUDITED = new Set<string>([
  "audit.audit_events",
  "audit.audit_seals",
  "audit.authentication_security_event_seals",
  "audit.authentication_security_events",
  "core.actors",
  "core.login_throttles",
  "costing.cost_recalc_queue",
  "costing.recipe_cost_current",
  "costing.recipe_cost_snapshot_lines",
  "costing.recipe_cost_snapshots",
  "org.provinces",
  "org.time_zones",
]);

describe("nombres de las tablas con auditoría", () => {
  it("todas tienen un nombre en español", async () => {
    const { TABLE_LABELS } = await import("@/lib/data");
    // Las tablas de cada esquema, de los tipos generados de la base (npm run db:types).
    const tables: string[] = [];
    let schema = "";
    let inTables = false;
    for (const line of readFileSync("lib/database.types.ts", "utf8").split(/\r?\n/)) {
      const top = /^ {2}([a-z]+): \{$/.exec(line);
      if (top?.[1]) schema = top[1];
      if (/^ {4}Tables: \{$/.test(line)) inTables = true;
      else if (/^ {4}[A-Z]/.test(line)) inTables = false;
      const table = /^ {6}([a-z_0-9]+): \{$/.exec(line);
      if (inTables && table?.[1]) tables.push(`${schema}.${table[1]}`);
    }
    expect(tables.length).toBeGreaterThan(60);
    const missing = tables.filter((t) => !TABLE_LABELS[t] && !UNAUDITED.has(t)).sort();
    expect(missing).toEqual([]);
  });
});
