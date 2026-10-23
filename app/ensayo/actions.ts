"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { createClient } from "@/lib/supabase/server";

// Documentos de ensayo (sección 10 del documento de Soy): imitan una receta para probar permisos,
// costos ocultos, versiones e historia. La base valida cada paso y registra lo rechazado.
const reason = schemas.reason.shape.reason;

const draftSchema = z.object({
  place: z.string().regex(/^[0-9a-f-]{36}:([0-9a-f-]{36})?$/),
  title: z.string().trim().min(1, "Escribí el título.").max(120),
  content: z.string().trim().max(4000).optional(),
  cost: z
    .string()
    .trim()
    .regex(/^(\d{1,10}([.,]\d{1,4})?)?$/, "El costo es un número, por ejemplo 1520,50.")
    .optional(),
  documentKey: z.string().uuid().optional(),
  reason,
});

export async function createDraftAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = draftSchema.safeParse({
    place: formData.get("place"),
    title: formData.get("title"),
    content: formData.get("content") ?? undefined,
    cost: formData.get("cost") ?? undefined,
    documentKey: formData.get("documentKey") || undefined,
    reason: formData.get("reason"),
  });
  if (!parsed.success) {
    // En la corrección, el lugar y el título van ocultos: si fallan, no hay campo que marcar.
    const errors = fieldErrors(parsed.error);
    const hidden = formData.has("documentKey")
      ? ["place", "title", "documentKey"]
      : ["documentKey"];
    return Object.keys(errors).some((k) => hidden.includes(k))
      ? { status: "bad", message: "No pudimos leer el documento. Recargá la página." }
      : { status: "bad", message: "Revisá los campos marcados.", fieldErrors: errors };
  }
  const [brandId, restaurantId] = parsed.data.place.split(":") as [string, string];
  const cost = parsed.data.cost ? Number(parsed.data.cost.replace(",", ".")) : undefined;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("create_test_document_draft", {
    p_brand_id: brandId,
    p_restaurant_id: restaurantId || undefined,
    p_title: parsed.data.title,
    p_content: parsed.data.content || undefined,
    p_cost: cost,
    p_reason: parsed.data.reason,
    p_document_key: parsed.data.documentKey,
  });
  revalidatePath("/ensayo");
  return toActionState(data, error);
}

// "documentId" y no "id": un campo "id" pisa la propiedad id del formulario en el navegador.
const stepSchema = z.object({ documentId: z.string().uuid(), reason });

async function step(
  fn: "request_test_document_review" | "publish_test_document",
  formData: FormData,
): Promise<ActionState> {
  const parsed = stepSchema.safeParse({
    documentId: formData.get("documentId"),
    reason: formData.get("reason"),
  });
  if (!parsed.success) {
    const fields = schemas.reason.safeParse(formValues(formData));
    return fields.success
      ? { status: "bad", message: "No pudimos leer el documento. Recargá la página." }
      : { status: "bad", fieldErrors: fieldErrors(fields.error) };
  }
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .rpc(fn, { p_id: parsed.data.documentId, p_reason: parsed.data.reason });
  revalidatePath("/ensayo");
  return toActionState(data, error);
}

export async function requestReviewAction(_prev: ActionState, formData: FormData) {
  return step("request_test_document_review", formData);
}
export async function publishAction(_prev: ActionState, formData: FormData) {
  return step("publish_test_document", formData);
}
