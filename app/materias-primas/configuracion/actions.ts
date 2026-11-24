"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { reasonField } from "@/lib/forms/schemas";
import { SETTINGS_LISTS } from "@/lib/settings-lists";
import { createClient } from "@/lib/supabase/server";

// Guardar una lista de Configuración del catálogo (ADR-0063): todos los cambios juntos, con motivo. La base
// (catalog.save_settings_list) controla el permiso de cada lista, el sello y cada dato.
const saveSchema = z.object({
  groupId: z.string().uuid(),
  list: z.enum(SETTINGS_LISTS),
  expectedStamp: z.string().min(1, "Recargá la página."),
  items: z
    .array(z.record(z.string().max(40), z.union([z.string().max(200), z.boolean()])))
    .min(1, "No hay cambios para guardar.")
    .max(100, "Son demasiados cambios juntos: guardá hasta 100 por vez."),
  reason: reasonField,
});

export async function saveSettingsListAction(
  payload: z.input<typeof saveSchema>,
): Promise<ActionState> {
  const parsed = saveSchema.safeParse(payload);
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  const p = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("catalog").rpc("save_settings_list", {
    p_group_id: p.groupId,
    p_list: p.list,
    p_expected_stamp: p.expectedStamp,
    p_items: p.items,
    p_reason: p.reason,
  });
  // Estas listas se eligen al cargar materias primas y recetas: esas pantallas también cambian.
  revalidatePath("/materias-primas", "layout");
  revalidatePath("/recetas", "layout");
  revalidatePath("/rubros");
  return toActionState(data, error);
}
