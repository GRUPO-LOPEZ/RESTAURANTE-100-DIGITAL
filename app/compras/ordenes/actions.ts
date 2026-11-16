"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { NEWS_KINDS, orderSchema } from "@/lib/purchase-orders";
import {
  getExpectedDelivery,
  getSupplierRanking,
  searchOrderIngredients,
} from "@/lib/purchase-orders-data";
import { createClient } from "@/lib/supabase/server";

// Acciones de órdenes de compra (Fase 3, Prompt 3, ADR-0053). Cada una llama a una función de la base, que controla el
// permiso en el local, pide el motivo y deja la auditoría. «Mandar OC» guarda el borrador y lo manda: si el proveedor
// requiere aprobación, va a Compras.

const uuid = z.string().uuid();

function revalidate(id?: string) {
  revalidatePath("/compras/ordenes");
  revalidatePath("/aprobaciones");
  if (id) revalidatePath(`/compras/ordenes/${id}`);
}

export type OrderState = ActionState & { orderId?: string };

// mode = "draft" (guardar el borrador) o "send" (guardarlo y mandarlo). El pedido viaja como JSON.
export async function saveOrderAction(_prev: OrderState, formData: FormData): Promise<OrderState> {
  let input: unknown;
  try {
    input = JSON.parse(String(formData.get("order") ?? "{}"));
  } catch {
    return { status: "bad", message: "Revisá la orden." };
  }
  const parsed = orderSchema.safeParse(input);
  if (!parsed.success) {
    const fieldErrors: Record<string, string> = {};
    for (const issue of parsed.error.issues) {
      const key = String(issue.path[0] ?? "order");
      if (!fieldErrors[key]) fieldErrors[key] = issue.message;
    }
    return {
      status: "bad",
      message: Object.values(fieldErrors)[0] ?? "Revisá la orden.",
      fieldErrors,
    };
  }
  const send = formData.get("mode") === "send";
  const o = parsed.data;
  const supabase = await createClient();
  const reason = send ? "Pedido desde la app" : "Borrador desde la app";
  const saved = await supabase.schema("purchasing").rpc("save_order_draft", {
    // Vacío = una orden nueva; los tipos generados no saben que la base acepta null.
    p_order_id: o.order_id ?? (null as unknown as string),
    p_restaurant_id: o.restaurant_id,
    p_supplier_id: o.supplier_id,
    p_lines: o.lines.map((l) => ({
      ...(l.purchase_product_id ? { purchase_product_id: l.purchase_product_id } : {}),
      ...(l.ingredient_id ? { ingredient_id: l.ingredient_id } : {}),
      quantity: l.quantity,
      ...(l.note ? { note: l.note } : {}),
    })),
    p_notes: o.notes ?? "",
    // Vacío = la calcula la base con los días de entrega del proveedor.
    p_expected_on: o.expected_on ?? (null as unknown as string),
    p_reason: reason,
  });
  const savedState = toActionState(saved.data, saved.error);
  if (savedState.status !== "ok") return savedState;
  const orderId = z.object({ purchase_order_id: z.string() }).safeParse(saved.data);
  if (!orderId.success) return { status: "bad", message: "No pudimos guardar la orden." };
  const id = orderId.data.purchase_order_id;
  if (!send) {
    revalidate(id);
    redirect(`/compras/ordenes/${id}?aviso=borrador`);
  }
  const sent = await supabase
    .schema("purchasing")
    .rpc("submit_order", { p_id: id, p_reason: reason });
  revalidate(id);
  const sentState = toActionState(sent.data, sent.error);
  if (sentState.status === "bad")
    // El borrador quedó guardado: se puede mandar desde su ficha.
    return {
      status: "bad",
      orderId: id,
      message: `${sentState.message ?? "No pudimos mandar la orden."} La orden quedó guardada como borrador.`,
    };
  redirect(
    `/compras/ordenes/${id}?aviso=${sentState.status === "info" ? "aprobacion" : "enviada"}`,
  );
}

// Mandar un borrador desde su ficha.
export async function submitOrderAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("orderId"));
  if (!id.success) return { status: "bad", message: "Falta la orden." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("submit_order", { p_id: id.data, p_reason: "Pedido desde la app" });
  revalidate(id.data);
  const state = toActionState(data, error);
  if (state.status === "bad") return state;
  redirect(
    `/compras/ordenes/${id.data}?aviso=${state.status === "info" ? "aprobacion" : "enviada"}`,
  );
}

export async function recordNewsAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("orderId"));
  const kind = z.enum(NEWS_KINDS).safeParse(formData.get("kind"));
  const message = z.string().trim().min(3).max(1000).safeParse(formData.get("reason"));
  if (!id.success) return { status: "bad", message: "Falta la orden." };
  if (!kind.success || !message.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: {
        ...(kind.success ? {} : { kind: "Elegí el tipo de novedad." }),
        ...(message.success ? {} : { reason: "Escribí la novedad (al menos 3 letras)." }),
      },
    };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("record_order_news", {
    p_id: id.data,
    p_kind: kind.data,
    p_message: message.data,
  });
  revalidate(id.data);
  const state = toActionState(data, error);
  if (state.status === "bad") return state;
  redirect(`/compras/ordenes/${id.data}?aviso=novedad`);
}

export async function cancelOrderAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("orderId"));
  const reason = z.string().trim().min(3).max(500).safeParse(formData.get("reason"));
  if (!id.success) return { status: "bad", message: "Falta la orden." };
  if (!reason.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { reason: "Escribí el motivo (al menos 3 letras)." },
    };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("cancel_order", { p_id: id.data, p_reason: reason.data });
  revalidate(id.data);
  const state = toActionState(data, error);
  if (state.status === "bad") return state;
  redirect(`/compras/ordenes/${id.data}?aviso=cancelada`);
}

// Marcar como leídas las novedades de mis órdenes (solo las propias: lo controla la base).
export async function markOrderNoticesReadAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ids = z.array(uuid).max(50).safeParse(formData.getAll("noticeId"));
  if (!ids.success || ids.data.length === 0)
    return { status: "bad", message: "No hay novedades para marcar." };
  const supabase = await createClient();
  const { error } = await supabase
    .schema("core")
    .rpc("mark_notifications_read", { p_ids: ids.data });
  revalidatePath("/compras/ordenes");
  return error
    ? toActionState(null, error)
    : { status: "ok", message: "Novedades marcadas como leídas." };
}

// Lecturas del armado (con la sesión de la persona: la base decide qué ve).
export async function rankingAction(supplierId: unknown, restaurantId: unknown) {
  const s = uuid.safeParse(supplierId);
  const r = uuid.safeParse(restaurantId);
  if (!s.success || !r.success) return [];
  return getSupplierRanking(s.data, r.data);
}

export async function ingredientSearchAction(restaurantId: unknown, query: unknown) {
  const r = uuid.safeParse(restaurantId);
  const q = z.string().max(80).safeParse(query);
  if (!r.success || !q.success) return [];
  return searchOrderIngredients(r.data, q.data);
}

export async function expectedDeliveryAction(supplierId: unknown, from: unknown) {
  const s = uuid.safeParse(supplierId);
  const d = z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .safeParse(from);
  if (!s.success || !d.success) return null;
  return getExpectedDelivery(s.data, d.data);
}
