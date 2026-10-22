"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import type { ActionState } from "@/lib/auth/results";
import { createClient } from "@/lib/supabase/server";

// Selector de local (sección 9): guarda en la base el local elegido (o "todos", con vacío).
// La base valida que sea uno de los locales de la persona.
export async function setActiveRestaurantAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = z.union([z.literal(""), z.string().uuid()]).safeParse(formData.get("restaurant"));
  if (!parsed.success) return { status: "bad", message: "Elegí un local de la lista." };
  const supabase = await createClient();
  const { error } = await supabase
    .schema("core")
    .rpc("set_active_restaurant", { p_restaurant_id: parsed.data || undefined });
  if (error) return { status: "bad", message: "No pudimos cambiar el local. Probá de nuevo." };
  revalidatePath("/", "layout");
  return { status: "ok", message: "Local cambiado." };
}

// Marca como leídos los avisos propios.
export async function markNotificationsReadAction(): Promise<void> {
  const supabase = await createClient();
  await supabase.schema("core").rpc("mark_notifications_read");
  revalidatePath("/", "layout");
}
