"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { createClient } from "@/lib/supabase/server";

// Pedir un cambio en la matriz (sección 9): queda pendiente hasta que lo apruebe Dirección
// General. La base valida permissions.manage, la separación de funciones y que nadie cambie un
// rol que tiene él mismo.
const schema = z.object({
  groupId: z.string().uuid(),
  role: z.string().regex(/^[a-z_]{1,60}$/),
  permission: z.string().regex(/^[a-z_]+\.[a-z_]+$/),
  grant: z.enum(["true", "false"]),
  reason: z.string().trim().min(1).max(500),
});

export async function requestMatrixChangeAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success)
    return { status: "bad", message: "Escribí el motivo (hasta 500 caracteres)." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("request_role_permission_change", {
    p_group_id: parsed.data.groupId,
    p_role_code: parsed.data.role,
    p_permission_code: parsed.data.permission,
    p_grant: parsed.data.grant === "true",
    p_reason: parsed.data.reason,
  });
  revalidatePath("/roles");
  return toActionState(data, error);
}
