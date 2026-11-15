import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import {
  type BillingMode,
  type Channel,
  type ListFrequency,
  type PaymentMethod,
  type PaymentTerms,
  type SheetAccount,
  type SupplierSheetDraft,
  type VatCondition,
} from "@/lib/suppliers";

// Lecturas de proveedores (Fase 3, ADR-0050). Todo pasa por la base con la sesión de la persona: la RLS decide qué ve
// (el pago y las cuentas, solo quien los administra o el Controller). Si una lectura falla, se corta con un error en
// lugar de mostrar «no hay datos».

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export const SUPPLIER_SORT_KEYS = ["name", "code"] as const;

const listRow = z.object({
  id: z.string(),
  code: z.string(),
  name: z.string(),
  trade_name: z.string().nullable(),
  tax_id: z.string().nullable(),
  is_active: z.boolean(),
  delivery_days: z.array(z.number()).nullable(),
  po_channel: z.string().nullable(),
  requires_po_approval: z.boolean().nullable(),
  payment_terms: z.string().nullable(),
  payment_days: z.number().nullable(),
  categories: z.array(z.string()),
});
export type SupplierListRow = z.infer<typeof listRow>;

export type SupplierListFilter = {
  search?: string;
  active: boolean;
  categoryId?: string;
  channel?: Channel;
  sort: (typeof SUPPLIER_SORT_KEYS)[number];
  desc: boolean;
  page: number;
  size: number;
};

export async function getSupplierList(
  filter: SupplierListFilter,
): Promise<{ rows: SupplierListRow[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("supplier_list", {
    p_search: filter.search ?? "",
    p_active: filter.active,
    p_category_id: filter.categoryId,
    p_channel: filter.channel,
    p_sort: filter.sort,
    p_desc: filter.desc,
    p_limit: filter.size,
    p_offset: filter.page * filter.size,
  });
  if (error) failed("los proveedores");
  const parsed = z.object({ total: z.number(), rows: z.array(listRow) }).safeParse(data);
  if (!parsed.success) failed("los proveedores");
  return parsed.data;
}

// Rubros de compra de primer nivel (para filtrar y para «Rubros que provee»). Los lee quien ve materias primas.
export async function getPurchaseRubros(): Promise<
  { id: string; name: string; code: string | null }[]
> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("ingredient_categories")
    .select("id, name, code")
    .is("parent_id", null)
    .eq("is_active", true)
    .order("name");
  if (error) failed("los rubros");
  return data;
}

// Los locales del grupo que la persona ve, para los números de cliente.
export async function getGroupRestaurants(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("org")
    .from("restaurants")
    .select("id, name")
    .eq("status", "active")
    .order("name");
  if (error) failed("los locales");
  return data;
}

export type SupplierSheet = {
  id: string;
  groupId: string;
  code: string;
  name: string;
  tradeName: string | null;
  taxId: string | null;
  vatCondition: VatCondition | null;
  isActive: boolean;
  isInternal: boolean;
  stamp: string | null;
  canManage: boolean;
  canSeePayment: boolean;
  // Un CUIT cargado antes de la Fase 3 con el verificador mal: la ficha lo avisa.
  taxIdInvalid: boolean;
  draft: SupplierSheetDraft;
};

const text = (v: string | null | undefined) => v ?? "";
const time = (v: string | null | undefined) => (v ? v.slice(0, 5) : "");

export async function getSupplierSheet(id: string): Promise<SupplierSheet | null> {
  const supabase = await createClient();
  const purchasing = supabase.schema("purchasing");
  const [supplier, state, terms, payment, accounts, categories, numbers] = await Promise.all([
    supabase
      .schema("catalog")
      .from("suppliers")
      .select(
        "id, group_id, code, name, trade_name, tax_id, vat_condition, address, city, phone, whatsapp, email, sales_contact, admin_contact, notes, is_active, is_internal",
      )
      .eq("id", id)
      .maybeSingle(),
    purchasing.rpc("supplier_sheet_state", { p_id: id }),
    purchasing
      .from("supplier_terms")
      .select(
        "order_days, delivery_days, receiving_from, receiving_to, po_channel, po_channel_target, billing_modes, price_list_frequency, requires_po_approval",
      )
      .eq("supplier_id", id)
      .maybeSingle(),
    purchasing
      .from("supplier_payment_terms")
      .select("payment_terms, payment_days, minimum_order_amount")
      .eq("supplier_id", id)
      .maybeSingle(),
    purchasing
      .from("supplier_payment_accounts")
      .select(
        "id, method, cbu, alias, bank, holder_name, holder_tax_id, electronic_code, is_active",
      )
      .eq("supplier_id", id)
      .order("created_at"),
    purchasing.from("supplier_categories").select("category_id").eq("supplier_id", id),
    purchasing
      .from("supplier_customer_numbers")
      .select("restaurant_id, customer_number")
      .eq("supplier_id", id),
  ]);
  for (const r of [supplier, state, terms, payment, accounts, categories, numbers]) {
    if (r.error) failed("el proveedor");
  }
  const s = supplier.data;
  if (!s) return null;
  const st = z
    .object({
      stamp: z.string().nullable(),
      can_manage: z.boolean(),
      can_see_payment: z.boolean(),
      tax_id_invalid: z.boolean().nullable().optional(),
    })
    .nullable()
    .parse(state.data);
  const canSeePayment = st?.can_see_payment ?? false;
  const t = terms.data;
  const p = payment.data;
  const draft: SupplierSheetDraft = {
    supplier: {
      name: s.name,
      trade_name: text(s.trade_name),
      tax_id: text(s.tax_id),
      vat_condition: text(s.vat_condition),
      address: text(s.address),
      city: text(s.city),
      phone: text(s.phone),
      whatsapp: text(s.whatsapp),
      email: text(s.email),
      sales_contact: text(s.sales_contact),
      admin_contact: text(s.admin_contact),
      notes: text(s.notes),
    },
    terms: {
      orderDays: t?.order_days ?? [],
      deliveryDays: t?.delivery_days ?? [],
      receivingFrom: time(t?.receiving_from),
      receivingTo: time(t?.receiving_to),
      poChannel: (t?.po_channel ?? "") as Channel | "",
      poChannelTarget: text(t?.po_channel_target),
      billingModes: (t?.billing_modes ?? []) as BillingMode[],
      priceListFrequency: (t?.price_list_frequency ?? "") as ListFrequency | "",
      requiresPoApproval: t?.requires_po_approval ?? false,
    },
    payment: canSeePayment
      ? {
          paymentTerms: (p?.payment_terms ?? "") as PaymentTerms | "",
          paymentDays: p ? String(p.payment_days) : "0",
          minimumOrderAmount:
            p?.minimum_order_amount != null ? String(Number(p.minimum_order_amount)) : "",
        }
      : null,
    accounts: canSeePayment
      ? (accounts.data ?? []).map((a): SheetAccount => ({
          id: a.id,
          key: a.id,
          method: a.method as PaymentMethod,
          cbu: text(a.cbu),
          alias: text(a.alias),
          bank: text(a.bank),
          holderName: text(a.holder_name),
          holderTaxId: text(a.holder_tax_id),
          electronicCode: text(a.electronic_code),
          isActive: a.is_active,
          remove: false,
        }))
      : null,
    categories: (categories.data ?? []).map((c) => c.category_id),
    customerNumbers: (numbers.data ?? []).map((n) => ({
      restaurantId: n.restaurant_id,
      number: n.customer_number,
    })),
  };
  return {
    id: s.id,
    groupId: s.group_id,
    code: s.code,
    name: s.name,
    tradeName: s.trade_name,
    taxId: s.tax_id,
    vatCondition: s.vat_condition,
    isActive: s.is_active,
    isInternal: s.is_internal,
    stamp: st?.stamp ?? null,
    canManage: st?.can_manage ?? false,
    canSeePayment,
    taxIdInvalid: st?.tax_id_invalid ?? false,
    draft,
  };
}
