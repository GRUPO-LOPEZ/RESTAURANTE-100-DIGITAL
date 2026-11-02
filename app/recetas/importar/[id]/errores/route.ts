import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { UUID } from "@/lib/data";
import { getImportIssues } from "@/lib/imports/jobs";
import { createClient } from "@/lib/supabase/server";

// Los problemas de una importación como CSV, para corregir el Excel (ADR-0027). Lee con la sesión
// de la persona: la base solo devuelve los de una importación que ve. Sin precios.
const LIMIT = 20_000;
const PAGE = 1000;

// Una celda de CSV. Lo que empieza con =, +, - o @ se antepone con ' para que una planilla no lo
// ejecute como fórmula (el texto viene del Excel subido, que no es confiable).
function cell(value: unknown): string {
  let text = value === null || value === undefined ? "" : String(value);
  if (/^[=+\-@\t\r\n＝＋－＠]/.test(text.trimStart())) text = `'${text}`;
  return `"${text.replace(/"/g, '""')}"`;
}

export async function GET(
  request: NextRequest,
  ctx: RouteContext<"/recetas/importar/[id]/errores">,
) {
  const { id } = await ctx.params;
  if (!UUID.test(id)) return new NextResponse("No encontrado", { status: 404 });
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.redirect(new URL("/ingresar", request.nextUrl));

  // La API devuelve hasta 1.000 filas por pedido (max_rows): se piden de a páginas.
  const rows: Awaited<ReturnType<typeof getImportIssues>>["rows"] = [];
  try {
    for (let page = 0; page * PAGE < LIMIT; page++) {
      const chunk = await getImportIssues(id, page, PAGE);
      rows.push(...chunk.rows);
      if (rows.length >= chunk.total || chunk.rows.length < PAGE) break;
    }
  } catch {
    // Vuelve a la vista previa con un aviso (no se baja un archivo con el texto del error).
    return NextResponse.redirect(new URL(`/recetas/importar/${id}?csv=error`, request.nextUrl));
  }
  const lines = [["Tipo", "Solapa", "Fila", "Campo", "Problema"].map(cell).join(",")];
  for (const e of rows)
    lines.push(
      [e.severity === "error" ? "Error" : "Aviso", e.sheet, e.row, e.field, e.message]
        .map(cell)
        .join(","),
    );
  // BOM para que las planillas abran bien los acentos.
  return new Response(`﻿${lines.join("\r\n")}\r\n`, {
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="problemas-importacion.csv"`,
      "cache-control": "no-store",
    },
  });
}
