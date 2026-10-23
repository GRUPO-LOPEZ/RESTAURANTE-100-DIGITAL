import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import {
  ACTION_LABELS,
  FIELD_LABELS,
  MODULE_LABELS,
  TABLE_LABELS,
  UUID,
  formatDateTime,
} from "@/lib/data";
import { createClient } from "@/lib/supabase/server";

// Exportar el historial (sección 9) como CSV, con los mismos filtros que la pantalla y en
// español. La base valida audit.export por alcance, oculta los costos a quien no los puede ver y
// deja la exportación en el registro de seguridad. Si algo falla, vuelve al historial con un aviso.
const MODULES = new Set(["org", "users", "roles", "approvals", "notifications", "test_documents"]);
const EXPORT_LIMIT = 2000;

const SOURCE_LABELS: Record<string, string> = {
  manual: "Una persona desde la app",
  edge_function: "Función del servidor",
  agent: "Agente de IA",
  import: "Carga masiva",
  integration: "Integración",
  seed: "Datos de prueba",
  maintenance: "Mantenimiento",
  auth: "Ingreso",
};

function date(value: string | null, end = false): string | undefined {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  const d = new Date(`${value}T00:00:00-03:00`);
  if (Number.isNaN(d.getTime())) return undefined;
  if (end) d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString();
}

function uuid(value: string | null): string | undefined {
  return value && UUID.test(value) ? value : undefined;
}

// Una celda de CSV. Lo que empieza con =, +, - o @ se antepone con ' para que una planilla no
// lo ejecute como fórmula.
function cell(value: unknown): string {
  let text = value === null || value === undefined ? "" : String(value);
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  return `"${text.replace(/"/g, '""')}"`;
}

const HEADER = [
  "Fecha",
  "Persona",
  "Rol",
  "Acción",
  "Módulo",
  "Qué",
  "Registro",
  "Campo",
  "Antes",
  "Después",
  "Motivo",
  "Origen",
  "Lugar",
  "Operación",
];

export async function GET(request: NextRequest) {
  const p = request.nextUrl.searchParams;
  // Las redirecciones usan el host del pedido (detrás de un proxy, request.url puede ser otro).
  const host = request.headers.get("host") ?? request.nextUrl.host;
  const proto =
    request.headers.get("x-forwarded-proto") ?? request.nextUrl.protocol.replace(":", "");
  const base = `${proto}://${host}`;
  const back = new URL("/historial", base);
  for (const key of ["desde", "hasta", "persona", "marca", "local", "modulo", "registro"]) {
    const v = p.get(key);
    if (v) back.searchParams.set(key, v);
  }
  const local = p.get("local");
  const moduleParam = p.get("modulo");
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.redirect(new URL("/ingresar", base));

  const [{ data, error }, roles] = await Promise.all([
    supabase.schema("core").rpc("audit_export", {
      p_from: date(p.get("desde")),
      p_to: date(p.get("hasta"), true),
      p_actor_id: uuid(p.get("persona")),
      p_brand_id: uuid(p.get("marca")),
      p_restaurant_id: local === "todos" ? undefined : uuid(local),
      p_module: moduleParam && MODULES.has(moduleParam) ? moduleParam : undefined,
      p_record_id: uuid(p.get("registro")),
      p_limit: EXPORT_LIMIT,
    }),
    supabase.schema("core").from("roles").select("code, name"),
  ]);
  if (error) {
    back.searchParams.set("error", "exportar");
    return NextResponse.redirect(back);
  }
  const roleNames = new Map((roles.data ?? []).map((r) => [r.code, r.name]));

  const lines = [HEADER.map(cell).join(",")];
  for (const r of data ?? []) {
    lines.push(
      [
        r.occurred_at ? formatDateTime(r.occurred_at) : "",
        r.actor_name,
        r.actor_role_code ? (roleNames.get(r.actor_role_code) ?? r.actor_role_code) : "",
        ACTION_LABELS[r.action ?? ""] ?? r.action,
        MODULE_LABELS[r.module ?? ""] ?? r.module,
        TABLE_LABELS[r.table_name ?? ""] ?? r.table_name,
        r.record_id,
        FIELD_LABELS[r.field ?? ""] ?? r.field,
        r.old_value,
        r.new_value,
        r.reason,
        SOURCE_LABELS[r.source ?? ""] ?? r.source,
        r.place_name,
        r.operation_id,
      ]
        .map(cell)
        .join(","),
    );
  }
  const today = new Date().toISOString().slice(0, 10);
  // BOM para que las planillas abran bien los acentos.
  return new Response(`﻿${lines.join("\r\n")}\r\n`, {
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="historial-${today}.csv"`,
      "cache-control": "no-store",
    },
  });
}
