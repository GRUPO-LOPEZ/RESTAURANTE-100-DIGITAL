import { z } from "zod";

import type { GroupItem } from "@/lib/group-counts";
import { createClient } from "@/lib/supabase/server";

// Lecturas de la orden de pago (ADR-0070). Con la sesión de la persona: la base decide qué ve (la cuenta del proveedor
// completa solo para quien paga o ve la condición de pago).

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

const method = z.enum(["cash", "transfer", "check", "echeq", "card", "electronic_code"]);

const detail = z.object({
  id: z.string(),
  number: z.string(),
  status: z.enum(["registered", "voided"]),
  version: z.number(),
  paid_on: z.string(),
  total: z.coerce.number(),
  notes: z.string().nullable(),
  voided_reason: z.string().nullable(),
  voided_at: z.string().nullable(),
  withholdings: z.object({
    income_tax: z.coerce.number(),
    vat: z.coerce.number(),
    gross_income: z.coerce.number(),
  }),
  can_void: z.boolean(),
  restaurant: z.object({ id: z.string(), name: z.string() }).nullable(),
  payer: z.object({ name: z.string(), tax_id: z.string().nullable() }).nullable(),
  supplier: z
    .object({
      id: z.string(),
      name: z.string(),
      legal_name: z.string(),
      tax_id: z.string().nullable(),
    })
    .nullable(),
  registered_by: z.string().nullable(),
  registered_at: z.string(),
  lines: z.array(
    z.object({
      method,
      amount: z.coerce.number(),
      reference: z.string().nullable(),
      from: z.object({ name: z.string(), kind: z.enum(["cash", "bank", "card"]) }).nullable(),
      to: z
        .object({
          bank: z.string().nullable(),
          holder_name: z.string().nullable(),
          holder_tax_id: z.string().nullable(),
          cbu: z.string().nullable(),
          cbu_end: z.string().nullable(),
          alias: z.string().nullable(),
        })
        .nullable(),
      check: z
        .object({
          number: z.string().nullable(),
          bank: z.string().nullable(),
          due_on: z.string().nullable(),
          third_party: z.boolean(),
          drawer_name: z.string().nullable(),
          drawer_tax_id: z.string().nullable(),
        })
        .nullable(),
    }),
  ),
  invoices: z.array(
    z.object({
      invoice_id: z.string(),
      label: z.string(),
      issued_on: z.string(),
      total: z.coerce.number(),
      applied: z.coerce.number(),
      notes: z.coerce.number(),
    }),
  ),
  unapplied: z.coerce.number(),
});
export type PaymentOrderDetail = z.infer<typeof detail>;

export async function getPaymentOrderDetail(id: string): Promise<PaymentOrderDetail | null> {
  const db = await createClient();
  const { data, error } = await db.schema("purchasing").rpc("payment_order_detail", { p_id: id });
  if (error) failed("la orden de pago");
  if (data === null) return null;
  const parsed = detail.safeParse(data);
  if (!parsed.success) failed("la orden de pago");
  return parsed.data;
}

const listRow = z.object({
  id: z.string(),
  number: z.string(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  payer_name: z.string().nullable(),
  paid_on: z.string(),
  total_amount: z.coerce.number(),
  methods: z.array(z.string()),
  status: z.enum(["registered", "voided"]),
  total: z.coerce.number(),
});
export type PaymentOrderRow = Omit<z.infer<typeof listRow>, "total">;

export async function getPaymentOrders(filter: {
  supplierId?: string;
  restaurantId?: string;
  page: number;
  size: number;
}): Promise<{ rows: PaymentOrderRow[]; total: number }> {
  const db = await createClient();
  const { data, error } = await db.schema("purchasing").rpc("payment_order_list", {
    p_supplier_id: filter.supplierId,
    p_restaurant_id: filter.restaurantId,
    p_limit: filter.size,
    p_offset: filter.page * filter.size,
  });
  if (error) failed("las órdenes de pago");
  const parsed = z.array(listRow).safeParse(data);
  if (!parsed.success) failed("las órdenes de pago");
  return {
    rows: parsed.data.map((r) => {
      const { total, ...row } = r;
      void total;
      return row;
    }),
    total: parsed.data[0]?.total ?? 0,
  };
}

export async function getPaymentOrderSupplierCounts(restaurantId?: string): Promise<GroupItem[]> {
  const db = await createClient();
  const { data, error } = await db
    .schema("purchasing")
    .rpc("payment_order_supplier_counts", { p_restaurant_id: restaurantId });
  if (error) failed("los proveedores de las órdenes de pago");
  const parsed = z
    .array(
      z.object({ supplier_id: z.string(), supplier_name: z.string(), total: z.coerce.number() }),
    )
    .safeParse(data);
  if (!parsed.success) failed("los proveedores de las órdenes de pago");
  return parsed.data.map((r) => ({ id: r.supplier_id, name: r.supplier_name, count: r.total }));
}

// Las cajas y cuentas de una razón social (para su ficha). Con la RLS: las ve quien administra el grupo o paga.
const accountRow = z.object({
  id: z.string(),
  kind: z.enum(["cash", "bank", "card"]),
  name: z.string(),
  bank: z.string().nullable(),
  account_number: z.string().nullable(),
  cbu: z.string().nullable(),
  alias: z.string().nullable(),
  card_last4: z.string().nullable(),
  is_active: z.boolean(),
});
export type CompanyAccount = z.infer<typeof accountRow>;

export async function getLegalEntityAccounts(legalEntityId: string): Promise<CompanyAccount[]> {
  const db = await createClient();
  const { data, error } = await db
    .schema("org")
    .from("legal_entity_accounts")
    .select("id, kind, name, bank, account_number, cbu, alias, card_last4, is_active")
    .eq("legal_entity_id", legalEntityId)
    .is("deleted_at", null)
    .order("kind")
    .order("name");
  if (error) failed("las cajas y cuentas");
  const parsed = z.array(accountRow).safeParse(data);
  if (!parsed.success) failed("las cajas y cuentas");
  return parsed.data;
}
