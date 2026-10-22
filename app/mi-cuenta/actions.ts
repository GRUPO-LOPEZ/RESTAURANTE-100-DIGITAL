"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { getMySession } from "@/lib/auth/session";
import { supabaseEnv } from "@/lib/supabase/env";
import { createClient } from "@/lib/supabase/server";

// Acciones de "Mi cuenta" (sección 9): datos propios, contraseña, doble verificación y sesiones.
// Todo sobre la propia cuenta: la base no deja tocar nada más desde acá.

// Lo mismo que validó el navegador (lib/forms/schemas.ts), con un error por campo.
function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

export async function updateMyProfileAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = schemas.profile.safeParse(formValues(formData));
  if (!parsed.success) return invalid(parsed.error);
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("update_my_profile", {
    p_first_name: parsed.data.first_name,
    p_last_name: parsed.data.last_name,
  });
  revalidatePath("/", "layout");
  return toActionState(data, error);
}

// Contraseña: mínimo 12 caracteres, con letras y números (P8; mismo criterio que Auth).

export async function changePasswordAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = schemas.changePassword.safeParse(formValues(formData));
  if (!parsed.success) return invalid(parsed.error);
  const session = await getMySession();
  if (!session.signed_in || !session.email)
    return { status: "bad", message: "Tu sesión venció. Volvé a ingresar." };

  // La contraseña actual se comprueba por el mismo camino que el ingreso: un error cuenta como
  // intento fallido (y 5 seguidos bloquean la cuenta), así no sirve para adivinarla.
  const { url, key } = supabaseEnv();
  const check = await fetch(`${url}/functions/v1/auth-login`, {
    method: "POST",
    headers: { apikey: key, "content-type": "application/json" },
    body: JSON.stringify({ email: session.email, password: parsed.data.current }),
    cache: "no-store",
  }).catch(() => null);
  if (!check) return { status: "bad", message: "No pudimos conectarnos. Probá de nuevo." };
  if (!check.ok) return { status: "bad", message: "La contraseña actual no es correcta." };
  // La comprobación abre una sesión que no se usa: se cierra en el momento.
  const checked = z
    .object({ session: z.object({ access_token: z.string() }) })
    .safeParse(await check.json().catch(() => null));
  if (checked.success) {
    await fetch(`${url}/auth/v1/logout?scope=local`, {
      method: "POST",
      headers: { apikey: key, authorization: `Bearer ${checked.data.session.access_token}` },
      cache: "no-store",
    }).catch(() => null);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error)
    return {
      status: "bad",
      message: "No pudimos cambiar la contraseña. Probá con otra que no hayas usado.",
    };
  return { status: "ok", message: "Listo: tu contraseña cambió." };
}

// Cierra todas las otras sesiones (otros navegadores o celulares); esta queda abierta.
export async function signOutOthersAction(): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut({ scope: "others" });
  revalidatePath("/mi-cuenta");
  if (error) return { status: "bad", message: "No pudimos cerrar las otras sesiones." };
  return { status: "ok", message: "Cerramos tus otras sesiones." };
}

// Cambiar de app de autenticación: se registra la nueva y, recién cuando su código es correcto,
// se dan de baja las anteriores. Así nunca queda la cuenta sin doble verificación.
export type FactorState = ActionState & { factorId?: string; qrCode?: string; secret?: string };

export async function startFactorChangeAction(): Promise<FactorState> {
  const supabase = await createClient();
  const { data: existing } = await supabase.auth.mfa.listFactors();
  for (const f of existing?.all ?? []) {
    if (f.status !== "verified") await supabase.auth.mfa.unenroll({ factorId: f.id });
  }
  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: `App de autenticación (${new Date().toISOString().slice(0, 10)})`,
  });
  if (error || !data)
    return { status: "bad", message: "No pudimos empezar el cambio. Probá de nuevo." };
  return { factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret };
}

const confirmSchema = z.object({
  factorId: z.string().uuid(),
  code: z
    .string()
    .trim()
    .regex(/^[0-9]{6}$/),
});

export async function confirmFactorChangeAction(
  prev: FactorState,
  formData: FormData,
): Promise<FactorState> {
  const parsed = confirmSchema.safeParse({
    factorId: formData.get("factorId"),
    code: formData.get("code"),
  });
  if (!parsed.success)
    return { ...prev, status: "bad", fieldErrors: { code: "El código tiene 6 números." } };
  const supabase = await createClient();
  const { error } = await supabase.auth.mfa.challengeAndVerify({
    factorId: parsed.data.factorId,
    code: parsed.data.code,
  });
  if (error)
    return { ...prev, status: "bad", message: "El código no es correcto. Probá con el próximo." };
  const { data: factors } = await supabase.auth.mfa.listFactors();
  for (const f of factors?.totp ?? []) {
    if (f.id !== parsed.data.factorId) await supabase.auth.mfa.unenroll({ factorId: f.id });
  }
  revalidatePath("/mi-cuenta");
  return { status: "ok", message: "Listo: ahora usás la app nueva." };
}
