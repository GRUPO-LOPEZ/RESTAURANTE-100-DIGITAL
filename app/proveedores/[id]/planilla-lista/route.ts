import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { buildPriceListTemplate } from "@/lib/imports/price-list-file";
import { createClient } from "@/lib/supabase/server";

// La planilla modelo de lista de precios para mandarle a un proveedor (decisión 22 de Soy, ADR-0071): nuestras columnas
// y un renglón de ejemplo inventado, con su nombre. La baja quien ve listas de precios; el proveedor lo lee la RLS.
export async function GET(
  request: NextRequest,
  { params }: RouteContext<"/proveedores/[id]/planilla-lista">,
) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id))
    return NextResponse.redirect(new URL("/proveedores", request.nextUrl));
  const db = await createClient();
  const { data: claims } = await db.auth.getClaims();
  if (!claims?.claims) return NextResponse.redirect(new URL("/ingresar", request.nextUrl));
  const groups = await db
    .schema("core")
    .rpc("permitted_group_ids", { p_permission: "purchasing.view_price_lists" });
  if (!Array.isArray(groups.data) || groups.data.length === 0)
    return NextResponse.redirect(new URL(`/proveedores/${id}`, request.nextUrl));
  const { data: supplier } = await db
    .schema("catalog")
    .from("suppliers")
    .select("name, trade_name, group_id")
    .eq("id", id)
    .maybeSingle();
  if (!supplier) return NextResponse.redirect(new URL("/proveedores", request.nextUrl));
  // Ve listas en el grupo de ese proveedor (no en cualquiera).
  if (!(groups.data as unknown[]).includes(supplier.group_id))
    return NextResponse.redirect(new URL(`/proveedores/${id}`, request.nextUrl));
  const name = supplier.trade_name || supplier.name;
  const file = await buildPriceListTemplate(name);
  // El nombre del archivo, sin acentos ni signos.
  const slug =
    name
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[^A-Za-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .toLowerCase()
      .slice(0, 40) || "proveedor";
  return new Response(new Uint8Array(file), {
    headers: {
      "content-type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "content-disposition": `attachment; filename="lista-de-precios-${slug}.xlsx"`,
      "cache-control": "no-store",
    },
  });
}
