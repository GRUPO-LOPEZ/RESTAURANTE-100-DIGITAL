import { z } from "zod";

import type { InvoiceClass } from "@/lib/invoices";
import { createClient } from "@/lib/supabase/server";

// Lecturas de pagos, cuenta corriente y tablero de compras (Fase 3, Prompt 6, ADR-0060). Todo con la sesión de la
// persona: las funciones de la base controlan el permiso y filtran por los locales que ve (purchasing.view_payments y
// purchasing.view_dashboard). Los importes los esconde la base a quien no ve pagos.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export type DueState = "ok" | "warn" | "bad" | "none";

// ---------------------------------------------------------------------------
// La agenda (pestañas de /compras/pagos)
// ---------------------------------------------------------------------------
const scheduleRow = z.object({
  invoice_id: z.string(),
  invoice_class: z.string(),
  point_of_sale: z.number().nullable(),
  number: z.coerce.number(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  issued_on: z.string(),
  due_on: z.string(),
  total_amount: z.coerce.number(),
  balance_amount: z.coerce.number(),
  days_left: z.number(),
  due_state: z.enum(["ok", "warn", "bad", "none"]),
  total: z.coerce.number(),
});
export type ScheduleRow = Omit<z.infer<typeof scheduleRow>, "total" | "invoice_class"> & {
  invoice_class: InvoiceClass;
};

export async function getPaymentSchedule(filter: {
  tab: "due" | "overdue" | "paid";
  supplierId?: string;
  restaurantId?: string;
  page: number;
  size: number;
}): Promise<{ rows: ScheduleRow[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("payment_schedule_list", {
    p_tab: filter.tab,
    p_supplier_id: filter.supplierId,
    p_restaurant_id: filter.restaurantId,
    p_limit: filter.size,
    p_offset: filter.page * filter.size,
  });
  if (error) failed("los pagos");
  const parsed = z.array(scheduleRow).safeParse(data);
  if (!parsed.success) failed("los pagos");
  return {
    rows: parsed.data.map((r) => {
      const { total, ...row } = r;
      void total;
      return { ...row, invoice_class: row.invoice_class as InvoiceClass };
    }),
    total: parsed.data[0]?.total ?? 0,
  };
}

// El efectivo pagado al recibir que falta confirmar.
const cashRow = z.object({
  payment_id: z.string(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  paid_on: z.string(),
  payment_amount: z.coerce.number(),
  receipt_id: z.string(),
  purchase_order_id: z.string().nullable(),
  order_number: z.string().nullable(),
});
export type CashRow = z.infer<typeof cashRow>;

export async function getCashToConfirm(restaurantId?: string): Promise<CashRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("cash_to_confirm", { p_restaurant_id: restaurantId });
  if (error) failed("el efectivo para confirmar");
  const parsed = z.array(cashRow).safeParse(data);
  if (!parsed.success) failed("el efectivo para confirmar");
  return parsed.data;
}

// ---------------------------------------------------------------------------
// «Registrar pago»: lo que se puede pagar de un proveedor en un local
// ---------------------------------------------------------------------------
const payable = z.object({
  invoice_count: z.coerce.number(),
  invoices: z.array(
    z.object({
      invoice_id: z.string(),
      label: z.string(),
      issued_on: z.string(),
      due_on: z.string(),
      balance: z.coerce.number(),
      due_state: z.enum(["ok", "warn", "bad", "none"]),
    }),
  ),
  credits: z.array(
    z.object({
      payment_id: z.string(),
      paid_on: z.string(),
      reference: z.string().nullable(),
      unapplied: z.coerce.number(),
    }),
  ),
  accounts: z.array(
    z.object({
      id: z.string(),
      method: z.enum(["cash", "transfer", "check", "echeq", "card", "electronic_code"]),
      bank: z.string().nullable(),
      alias: z.string().nullable(),
      cbu_end: z.string().nullable(),
      electronic_code: z.string().nullable(),
    }),
  ),
});
export type Payable = z.infer<typeof payable>;

export async function getPayable(
  restaurantId: string,
  supplierId: string,
): Promise<Payable | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("payable_invoices", { p_restaurant_id: restaurantId, p_supplier_id: supplierId });
  if (error) failed("lo que se le debe al proveedor");
  if (data === null) return null;
  const parsed = payable.safeParse(data);
  if (!parsed.success) failed("lo que se le debe al proveedor");
  return parsed.data;
}

// Los proveedores con algo para pagar en un local (para el panel: primero los que tienen saldo).
export async function getSuppliersToPay(
  restaurantId: string,
): Promise<{ id: string; name: string; balance: number }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("payment_schedule_list", {
    p_tab: "due",
    p_restaurant_id: restaurantId,
    p_limit: 50,
  });
  const overdue = await supabase.schema("purchasing").rpc("payment_schedule_list", {
    p_tab: "overdue",
    p_restaurant_id: restaurantId,
    p_limit: 50,
  });
  if (error || overdue.error) failed("los proveedores para pagar");
  const rows = z.array(scheduleRow).parse([...(data ?? []), ...(overdue.data ?? [])]);
  const bySupplier = new Map<string, { id: string; name: string; balance: number }>();
  for (const r of rows) {
    const prior = bySupplier.get(r.supplier_id);
    bySupplier.set(r.supplier_id, {
      id: r.supplier_id,
      name: r.supplier_name,
      balance: (prior?.balance ?? 0) + r.balance_amount,
    });
  }
  return [...bySupplier.values()].sort((a, b) => a.name.localeCompare(b.name, "es"));
}

// ---------------------------------------------------------------------------
// Cuenta corriente de un proveedor
// ---------------------------------------------------------------------------
const account = z.object({
  invoiced: z.coerce.number(),
  credits: z.coerce.number(),
  paid: z.coerce.number(),
  unapplied: z.coerce.number(),
  balance: z.coerce.number(),
  overdue: z.coerce.number(),
  last_invoice_on: z.string().nullable(),
  last_payment_on: z.string().nullable(),
  supplier_balance: z.coerce.number().nullable(),
  supplier_balance_on: z.string().nullable(),
  movements: z.array(
    z.object({
      kind: z.enum(["invoice", "credit_note", "debit_note", "discount", "payment"]),
      moved_on: z.string(),
      label: z.string(),
      amount: z.coerce.number(),
      balance: z.coerce.number(),
      source_id: z.string(),
      restaurant_id: z.string(),
    }),
  ),
  movement_count: z.coerce.number(),
});
export type SupplierAccount = z.infer<typeof account>;

export async function getSupplierAccount(
  supplierId: string,
  restaurantId?: string,
  movements = 5,
): Promise<SupplierAccount | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("supplier_account", {
    p_supplier_id: supplierId,
    p_restaurant_id: restaurantId,
    p_movements: movements,
  });
  if (error) failed("la cuenta corriente");
  if (data === null) return null;
  const parsed = account.safeParse(data);
  if (!parsed.success) failed("la cuenta corriente");
  return parsed.data;
}

// ---------------------------------------------------------------------------
// Tablero de compras
// ---------------------------------------------------------------------------
const board = z.object({
  can_see_amounts: z.boolean(),
  alerts: z.array(
    z.object({
      kind: z.string(),
      severity: z.enum(["bad", "warn", "info"]),
      title: z.string(),
      link: z.string(),
      since: z.string().nullable(),
    }),
  ),
  alert_count: z.coerce.number(),
  alert_kinds: z.record(z.string(), z.coerce.number()),
  observed: z.coerce.number(),
  open_orders: z.coerce.number(),
  expired_lists: z.coerce.number(),
  due_week: z.coerce.number(),
  due_week_amount: z.coerce.number().nullable(),
  unmapped: z.coerce.number(),
  spend: z
    .array(
      z.object({
        label: z.string(),
        kind: z.enum(["recipes", "other", "freight", "perception"]),
        amount: z.coerce.number(),
      }),
    )
    .nullable(),
  cost_history: z
    .array(
      z.object({
        ingredient_id: z.string(),
        name: z.string(),
        points: z
          .array(z.object({ on: z.string(), change_pct: z.coerce.number().nullable() }))
          .nullable(),
      }),
    )
    .nullable(),
  next_payments: z.array(
    z.object({
      invoice_id: z.string(),
      label: z.string(),
      supplier: z.string(),
      due_on: z.string(),
      due_state: z.enum(["ok", "warn", "bad", "none"]),
      balance: z.coerce.number().nullable(),
    }),
  ),
});
export type PurchasingBoard = z.infer<typeof board>;

export async function getPurchasingBoard(restaurantId?: string): Promise<PurchasingBoard | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("purchasing_dashboard", { p_restaurant_id: restaurantId });
  if (error) failed("el tablero de compras");
  if (data === null) return null;
  const parsed = board.safeParse(data);
  if (!parsed.success) failed("el tablero de compras");
  return parsed.data;
}
