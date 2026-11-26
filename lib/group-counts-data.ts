import { z } from "zod";

import type { GroupItem } from "@/lib/group-counts";
import { createClient } from "@/lib/supabase/server";
import type { Channel } from "@/lib/suppliers";

// Conteos del panel izquierdo de los listados de Compras (criterio 7 de Soy, ADR-0068). Cada uno cuenta con los mismos
// filtros y permisos que su lista, menos el del proveedor (o del rubro): el número coincide con el total de la tabla al
// elegirlo (pgTAP 419). Con la sesión de la persona.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

const supplierRow = z.object({
  supplier_id: z.string(),
  supplier_name: z.string(),
  total: z.coerce.number(),
});
const rubroRow = z.object({
  category_id: z.string(),
  category_name: z.string(),
  total: z.coerce.number(),
});

function suppliers(data: unknown, what: string): GroupItem[] {
  const parsed = z.array(supplierRow).safeParse(data);
  if (!parsed.success) failed(what);
  return parsed.data.map((r) => ({ id: r.supplier_id, name: r.supplier_name, count: r.total }));
}

export async function getOrderSupplierCounts(filter: {
  status?: string;
  restaurantId?: string;
  mine?: boolean;
}): Promise<GroupItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("order_supplier_counts", {
    p_status: filter.status,
    p_restaurant_id: filter.restaurantId,
    p_mine: filter.mine ?? false,
  });
  if (error) failed("los proveedores de las órdenes");
  return suppliers(data, "los proveedores de las órdenes");
}

export async function getInvoiceSupplierCounts(filter: {
  status?: string;
  restaurantId?: string;
  from?: string;
  to?: string;
}): Promise<GroupItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("invoice_supplier_counts", {
    p_status: filter.status,
    p_restaurant_id: filter.restaurantId,
    p_from: filter.from,
    p_to: filter.to,
  });
  if (error) failed("los proveedores de las facturas");
  return suppliers(data, "los proveedores de las facturas");
}

export async function getPaymentSupplierCounts(filter: {
  tab: string;
  restaurantId?: string;
}): Promise<GroupItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("payment_supplier_counts", {
    p_tab: filter.tab,
    p_restaurant_id: filter.restaurantId,
  });
  if (error) failed("los proveedores de los pagos");
  return suppliers(data, "los proveedores de los pagos");
}

export async function getPriceListSupplierCounts(filter: {
  status?: string;
}): Promise<GroupItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("price_list_supplier_counts", {
    p_status: filter.status,
  });
  if (error) failed("los proveedores de las listas");
  return suppliers(data, "los proveedores de las listas");
}

export async function getSupplierRubroCounts(filter: {
  search?: string;
  active: boolean;
  channel?: Channel;
}): Promise<GroupItem[]> {
  const supabase = await createClient();
  // Los mismos filtros que getSupplierList (lib/suppliers-data.ts), menos el rubro.
  const { data, error } = await supabase.schema("purchasing").rpc("supplier_rubro_counts", {
    p_search: filter.search ?? "",
    p_active: filter.active,
    p_channel: filter.channel,
  });
  if (error) failed("los rubros de los proveedores");
  const parsed = z.array(rubroRow).safeParse(data);
  if (!parsed.success) failed("los rubros de los proveedores");
  return parsed.data.map((r) => ({ id: r.category_id, name: r.category_name, count: r.total }));
}
