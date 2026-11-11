"use server";

import { revalidatePath } from "next/cache";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, schemas } from "@/lib/forms/schemas";
import type { MatrixChange } from "@/lib/permission-matrix";
import { createClient } from "@/lib/supabase/server";

// Guardar la matriz de permisos (ADR-0039): el lote de cambios va en una sola transacción, todo o nada, y se
// aplica en el momento. La base controla permissions.manage, que nadie cambie un rol propio, la separación de
// funciones y que el sistema no se quede sin quien cambie la matriz ni sin quien apruebe.
export async function saveMatrixAction(input: {
  group_id: string;
  changes: MatrixChange[];
  reason: string;
}): Promise<ActionState> {
  const parsed = schemas.permissionMatrix.safeParse(input);
  if (!parsed.success) {
    const errors = fieldErrors(parsed.error);
    if (errors.reason) return { status: "bad", fieldErrors: { reason: errors.reason } };
    return { status: "bad", message: "No pudimos leer los cambios. Recargá la página." };
  }
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("apply_permission_matrix", {
    p_group_id: parsed.data.group_id,
    p_changes: parsed.data.changes,
    p_reason: parsed.data.reason,
  });
  revalidatePath("/roles");
  return toActionState(data, error);
}
