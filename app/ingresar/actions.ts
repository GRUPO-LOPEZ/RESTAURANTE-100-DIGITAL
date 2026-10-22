"use server";

import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";

import { supabaseEnv } from "@/lib/supabase/env";
import { REMEMBER_COOKIE } from "@/lib/supabase/remember";
import { createClient } from "@/lib/supabase/server";

export type FormState = { status?: "ok" | "info" | "warn" | "bad"; message?: string };

// Contraseña: mínimo 12 caracteres, con letras y números (P8; mismo criterio que Auth).
const passwordRules = z
  .string()
  .min(12, "La contraseña tiene que tener al menos 12 caracteres.")
  .max(200)
  .regex(/[A-Za-z]/, "La contraseña tiene que tener letras.")
  .regex(/[0-9]/, "La contraseña tiene que tener números.");

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(320),
  password: z.string().min(1).max(200),
});

const sessionSchema = z.object({
  session: z.object({ access_token: z.string(), refresh_token: z.string() }),
});
const messageSchema = z.object({ message: z.string() });

// Ingreso: pasa por la Edge Function auth-login, que cuenta los intentos y bloquea al quinto
// fallo (ADR-0010). Si sale bien, la sesión queda en cookies.
export async function signIn(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = loginSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });
  if (!parsed.success) return { status: "bad", message: "Ingresá tu correo y tu contraseña." };

  const { url, key } = supabaseEnv();
  const h = await headers();
  let res: Response;
  try {
    res = await fetch(`${url}/functions/v1/auth-login`, {
      method: "POST",
      headers: {
        apikey: key,
        "content-type": "application/json",
        "x-client-ip": h.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "",
        "x-client-user-agent": (h.get("user-agent") ?? "").slice(0, 300),
      },
      body: JSON.stringify(parsed.data),
      cache: "no-store",
    });
  } catch {
    return { status: "bad", message: "No pudimos conectarnos. Probá de nuevo en un momento." };
  }
  const body: unknown = await res.json().catch(() => null);

  if (res.ok) {
    const ok = sessionSchema.safeParse(body);
    if (!ok.success) return { status: "bad", message: "No pudimos ingresar. Probá de nuevo." };
    // "Recordar sesión": sin marcar, la sesión se borra al cerrar el navegador.
    const remember = formData.get("remember") === "on";
    const cookieStore = await cookies();
    cookieStore.set(REMEMBER_COOKIE, remember ? "1" : "0", {
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      path: "/",
      ...(remember ? { maxAge: 60 * 60 * 24 * 400 } : {}),
    });
    const supabase = await createClient({ remember });
    const { error } = await supabase.auth.setSession(ok.data.session);
    if (error) return { status: "bad", message: "No pudimos ingresar. Probá de nuevo." };
    redirect("/");
  }

  const msg = messageSchema.safeParse(body);
  return {
    status: res.status === 423 ? "warn" : "bad",
    message: msg.success ? msg.data.message : "No pudimos ingresar. Probá de nuevo.",
  };
}

export async function signOut(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/ingresar");
}

// Doble verificación (MFA): verifica el código de la app de autenticación.
const codeSchema = z.object({
  code: z
    .string()
    .trim()
    .regex(/^[0-9]{6}$/),
});

// Solo una ruta interna de la app: nunca otro sitio.
function safeNext(value: FormDataEntryValue | null): string {
  const next = typeof value === "string" ? value : "";
  return /^\/[a-z0-9/-]*$/.test(next) && !next.startsWith("//") ? next : "/";
}

export async function verifyCode(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = codeSchema.safeParse({ code: formData.get("code") });
  if (!parsed.success) return { status: "bad", message: "El código tiene 6 números." };
  const supabase = await createClient();
  const { data: factors } = await supabase.auth.mfa.listFactors();
  const factor = factors?.totp.find((f) => f.status === "verified");
  if (!factor) return { status: "bad", message: "Todavía no registraste la doble verificación." };
  const { error } = await supabase.auth.mfa.challengeAndVerify({
    factorId: factor.id,
    code: parsed.data.code,
  });
  if (error)
    return { status: "bad", message: "El código no es correcto o venció. Probá con el próximo." };
  redirect(safeNext(formData.get("next")));
}

export type EnrollState = FormState & { factorId?: string; qrCode?: string; secret?: string };

// Primer ingreso de un rol con MFA obligatorio: registra la app de autenticación.
export async function startEnrollment(): Promise<EnrollState> {
  const supabase = await createClient();
  const { data: existing } = await supabase.auth.mfa.listFactors();
  if (existing?.totp.some((f) => f.status === "verified")) {
    return { status: "warn", message: "Ya tenés la doble verificación registrada." };
  }
  // Limpia registros a medio hacer, para no acumularlos.
  for (const f of existing?.all ?? []) {
    if (f.status !== "verified") await supabase.auth.mfa.unenroll({ factorId: f.id });
  }
  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: "App de autenticación",
  });
  if (error || !data)
    return { status: "bad", message: "No pudimos empezar el registro. Probá de nuevo." };
  return { factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret };
}

const enrollSchema = z.object({
  factorId: z.string().uuid(),
  code: z
    .string()
    .trim()
    .regex(/^[0-9]{6}$/),
});

export async function confirmEnrollment(
  prev: EnrollState,
  formData: FormData,
): Promise<EnrollState> {
  const parsed = enrollSchema.safeParse({
    factorId: formData.get("factorId"),
    code: formData.get("code"),
  });
  if (!parsed.success) return { ...prev, status: "bad", message: "El código tiene 6 números." };
  const supabase = await createClient();
  const { error } = await supabase.auth.mfa.challengeAndVerify({
    factorId: parsed.data.factorId,
    code: parsed.data.code,
  });
  if (error)
    return {
      ...prev,
      status: "bad",
      message: "El código no es correcto. Revisá la hora del celular y probá de nuevo.",
    };
  redirect(safeNext(formData.get("next")));
}

// Recuperar la contraseña (sección 9). El mensaje es siempre el mismo: nunca dice si el correo
// existe. El enlace del correo vuelve a /ingresar/confirmar, que abre una sesión de recuperación.
const recoverSchema = z.object({ email: z.string().trim().toLowerCase().email().max(320) });

export async function requestRecovery(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = recoverSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return { status: "bad", message: "Revisá el correo." };
  const h = await headers();
  const origin = `${h.get("x-forwarded-proto") ?? "http"}://${h.get("host") ?? "127.0.0.1:3000"}`;
  const supabase = await createClient({ remember: false });
  await supabase.auth.resetPasswordForEmail(parsed.data.email, {
    redirectTo: `${origin}/ingresar/confirmar`,
  });
  return {
    status: "info",
    message:
      "Si el correo es de una cuenta, te llegó un enlace para elegir una contraseña nueva. Revisá también el correo no deseado.",
  };
}

const newPasswordSchema = z
  .object({ password: passwordRules, repeat: z.string() })
  .refine((v) => v.password === v.repeat, { message: "Las dos contraseñas no coinciden." });

// Guarda la contraseña nueva con la sesión de recuperación. Si la cuenta usa doble verificación,
// Auth pide primero el código (aal2): la pantalla de doble verificación vuelve acá.
export async function setNewPassword(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = newPasswordSchema.safeParse({
    password: formData.get("password"),
    repeat: formData.get("repeat"),
  });
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá la contraseña." };
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return { status: "bad", message: "El enlace venció. Pedí uno nuevo." };
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.nextLevel === "aal2" && aal.currentLevel !== "aal2")
    redirect("/ingresar/doble-verificacion?siguiente=/ingresar/nueva-contrasena");
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error)
    return {
      status: "bad",
      message: "No pudimos guardar la contraseña. Probá con otra que no hayas usado.",
    };
  redirect("/");
}
