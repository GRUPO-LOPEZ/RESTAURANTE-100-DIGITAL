import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { buildSupplierTemplate } from "@/lib/imports/supplier-sheet";
import { getPurchaseRubros } from "@/lib/suppliers-data";
import { createClient } from "@/lib/supabase/server";

// La plantilla de la planilla de proveedores (ADR-0055): los encabezados, una fila de ejemplo inventada y una hoja
// «Valores» con las opciones y los rubros de compra del grupo. La baja quien administra proveedores.
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.redirect(new URL("/ingresar", request.nextUrl));
  const groups = await supabase
    .schema("core")
    .rpc("permitted_group_ids", { p_permission: "purchasing.manage_suppliers" });
  if (!Array.isArray(groups.data) || groups.data.length === 0)
    return NextResponse.redirect(new URL("/proveedores", request.nextUrl));
  let rubros: string[] = [];
  try {
    rubros = (await getPurchaseRubros()).map((r) => r.name);
  } catch {
    return NextResponse.redirect(new URL("/proveedores/importar?plantilla=error", request.nextUrl));
  }
  const file = await buildSupplierTemplate(rubros);
  return new Response(new Uint8Array(file), {
    headers: {
      "content-type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "content-disposition": `attachment; filename="plantilla-proveedores.xlsx"`,
      "cache-control": "no-store",
    },
  });
}
