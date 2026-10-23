"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { parsePlace } from "@/lib/data";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { supabaseEnv } from "@/lib/supabase/env";
import { createClient } from "@/lib/supabase/server";

// Acciones sobre personas. Cada una llama a una función de la base que valida el permiso y
// registra lo rechazado (ADR-0009): la pantalla solo traduce la respuesta.
const uuid = z.string().uuid();

// Lo mismo que validó el navegador (lib/forms/schemas.ts), con un error por campo.
function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

function reasonError(formData: FormData): ActionState | null {
  const parsed = schemas.reason.safeParse(formValues(formData));
  return parsed.success ? null : invalid(parsed.error);
}

export async function assignRoleAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.assignRole.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const userId = uuid.safeParse(formData.get("userId"));
  const place = parsePlace(formData.get("place"));
  if (!userId.success) return { status: "bad", message: "Falta la persona." };
  if (!place.success) return { status: "bad", fieldErrors: { place: "Elegí el lugar." } };

  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("assign_role", {
    p_user_id: userId.data,
    p_role_code: fields.data.role,
    p_scope_type: place.data.scope,
    p_group_id: place.data.groupId,
    p_brand_id: place.data.brandId ?? undefined,
    p_restaurant_id: place.data.restaurantId ?? undefined,
    p_reason: fields.data.reason,
  });
  revalidatePath(`/usuarios/${userId.data}`);
  return toActionState(data, error);
}

export async function revokeRoleAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const assignmentId = uuid.safeParse(formData.get("assignmentId"));
  const missing = reasonError(formData);
  if (!assignmentId.success) return { status: "bad", message: "Elegí el rol que querés quitar." };
  if (missing) return missing;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("revoke_role", {
    p_assignment_id: assignmentId.data,
    p_reason: String(formData.get("reason")).trim(),
  });
  revalidatePath("/usuarios", "layout");
  return toActionState(data, error);
}

type AccountRpc =
  "disable_user" | "request_reactivation" | "unlock_user" | "suspend_user" | "lift_suspension";

async function accountAction(fn: AccountRpc, formData: FormData): Promise<ActionState> {
  const userId = uuid.safeParse(formData.get("userId"));
  const missing = reasonError(formData);
  if (!userId.success) return { status: "bad", message: "Falta la persona." };
  if (missing) return missing;
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .rpc(fn, { p_user_id: userId.data, p_reason: String(formData.get("reason")).trim() });
  revalidatePath(`/usuarios/${userId.data}`);
  return toActionState(data, error);
}

export async function disableUserAction(_prev: ActionState, formData: FormData) {
  return accountAction("disable_user", formData);
}
export async function requestReactivationAction(_prev: ActionState, formData: FormData) {
  return accountAction("request_reactivation", formData);
}
export async function unlockUserAction(_prev: ActionState, formData: FormData) {
  return accountAction("unlock_user", formData);
}
// Suspender es una pausa: se levanta sin aprobación (decisión de Joaco, 2026-10-21).
export async function suspendUserAction(_prev: ActionState, formData: FormData) {
  return accountAction("suspend_user", formData);
}
export async function liftSuspensionAction(_prev: ActionState, formData: FormData) {
  return accountAction("lift_suspension", formData);
}

// Invitación: va a la Edge Function invite-user con la sesión de quien invita, que valida
// todo en la base con su identidad.
const inviteResponse = z.object({ message: z.string().optional(), role: z.unknown().optional() });

export async function inviteAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = schemas.invite.safeParse(formValues(formData));
  const place = parsePlace(formData.get("place"));
  if (!parsed.success) return invalid(parsed.error);
  if (!place.success) return { status: "bad", fieldErrors: { place: "Elegí el lugar." } };

  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getSession();
  const token = auth.session?.access_token;
  if (!token) return { status: "bad", message: "Tu sesión venció. Volvé a ingresar." };

  const { url, key } = supabaseEnv();
  const h = await headers();
  const origin = `${h.get("x-forwarded-proto") ?? "http"}://${h.get("host") ?? "127.0.0.1:3000"}`;
  const res = await fetch(`${url}/functions/v1/invite-user`, {
    method: "POST",
    headers: { apikey: key, authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({
      ...parsed.data,
      place: undefined, // el lugar va desarmado abajo
      scope_type: place.data.scope,
      group_id: place.data.groupId,
      brand_id: place.data.brandId,
      restaurant_id: place.data.restaurantId,
      redirect_to: `${origin}/ingresar/invitacion`,
    }),
    cache: "no-store",
  }).catch(() => null);
  if (!res) return { status: "bad", message: "No pudimos conectarnos. Probá de nuevo." };
  const body = inviteResponse.safeParse(await res.json().catch(() => ({})));
  if (!res.ok)
    return {
      status: "bad",
      message: (body.success && body.data.message) || "No se pudo enviar la invitación.",
    };

  const roleState = body.success
    ? toActionState(body.data.role, null)
    : { status: "info" as const };
  revalidatePath("/usuarios");
  return {
    status: roleState.status === "bad" ? "warn" : "ok",
    message:
      roleState.status === "info"
        ? "Invitación enviada. El rol queda pendiente de aprobación."
        : roleState.status === "bad"
          ? `Invitación enviada, pero el rol no se pudo dar: ${roleState.message ?? ""}`
          : "Invitación enviada. La persona va a recibir un correo para elegir su contraseña.",
  };
}

// Aprobaciones.
const decisionSchema = z.object({
  requestId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  comment: z.string().trim().max(500).optional(),
});

export async function decideAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = decisionSchema.safeParse({
    requestId: formData.get("requestId"),
    decision: formData.get("decision"),
    comment: formData.get("comment") ?? undefined,
  });
  if (!parsed.success) return { status: "bad", message: "Elegí aprobar o rechazar." };
  if (parsed.data.decision === "rejected" && !parsed.data.comment) {
    return { status: "bad", fieldErrors: { comment: "Para rechazar, escribí el motivo." } };
  }
  const supabase = await createClient();
  const { data, error } = await supabase.schema("workflow").rpc("decide_approval", {
    p_request_id: parsed.data.requestId,
    p_decision: parsed.data.decision,
    p_comment: parsed.data.comment || undefined,
  });
  revalidatePath("/aprobaciones");
  return toActionState(data, error);
}
