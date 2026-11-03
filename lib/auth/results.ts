import { z } from "zod";

// Respuesta de las funciones críticas de la base (ADR-0009): nunca se confía en la pantalla.
const resultSchema = z.object({
  result: z.string(),
  message: z.string().optional(),
  request_id: z.string().optional(),
});

export type ActionState = {
  status?: "ok" | "info" | "warn" | "bad";
  message?: string;
  // Un error por campo, con el nombre del campo (ADR-0016): el formulario lo muestra debajo.
  fieldErrors?: Record<string, string>;
};

const MESSAGES: Record<string, { status: NonNullable<ActionState["status"]>; message: string }> = {
  applied: { status: "ok", message: "Listo." },
  pending_approval: {
    status: "info",
    message: "Queda pendiente: otra persona lo tiene que aprobar.",
  },
  approved: { status: "ok", message: "Aprobado y aplicado." },
  rejected: { status: "ok", message: "Rechazado. Quedó registrado." },
  cancelled: { status: "ok", message: "Solicitud retirada." },
  already_resolved: { status: "warn", message: "La solicitud ya estaba resuelta." },
  already_deactivated: { status: "warn", message: "La cuenta ya estaba desactivada." },
  not_locked: { status: "warn", message: "La cuenta no estaba bloqueada." },
  not_suspended: { status: "warn", message: "La cuenta no estaba suspendida." },
  not_active: { status: "warn", message: "La cuenta no está activa: no se puede suspender." },
  already_member: { status: "info", message: "La persona ya trabaja en ese lugar." },
  denied: {
    status: "bad",
    message: "No tenés permiso para hacer esto. El intento quedó registrado.",
  },
};

// Traduce la respuesta de la base a un mensaje para la persona.
export function toActionState(
  data: unknown,
  error: { message?: string; code?: string } | null,
): ActionState {
  if (error) {
    return { status: "bad", message: friendlyError(error) };
  }
  const parsed = resultSchema.safeParse(data);
  if (!parsed.success) return { status: "bad", message: "No pudimos completar la operación." };
  const known = MESSAGES[parsed.data.result];
  if (!known) return { status: "info", message: parsed.data.message ?? "Listo." };
  // Los mensajes de la base ya están en español y explican el motivo.
  return { status: known.status, message: parsed.data.message ?? known.message };
}

function friendlyError(error: { message?: string; code?: string }): string {
  // Las validaciones de la base (23514, 23505, 22023) ya traen un mensaje en español.
  // Un choque con una restricción sin traducir trae el nombre técnico ("violates ..."): no se muestra.
  if (
    error.code &&
    ["23514", "23505", "22023"].includes(error.code) &&
    error.message &&
    !error.message.includes("violates")
  )
    return error.message;
  if (error.code === "42501") return "No tenés permiso para hacer esto.";
  return "No pudimos completar la operación. Probá de nuevo.";
}
