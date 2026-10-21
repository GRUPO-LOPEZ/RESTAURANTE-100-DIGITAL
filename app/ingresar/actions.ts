"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";

import { supabaseEnv } from "@/lib/supabase/env";
import { createClient } from "@/lib/supabase/server";

export type FormState = { status?: "ok" | "info" | "warn" | "bad"; message?: string };

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
    const supabase = await createClient();
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
  redirect("/");
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
  redirect("/");
}
