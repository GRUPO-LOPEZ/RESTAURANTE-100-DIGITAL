// Ingreso con correo y contraseña (ADR-0010).
// 1) Si la cuenta está bloqueada por intentos fallidos, no intenta.
// 2) Pide el token a Supabase Auth (el Custom Access Token hook niega cuentas desactivadas).
// 3) Si la contraseña es incorrecta, anota el fallo; al quinto seguido bloquea 10 minutos (P18).
// Los mensajes nunca dicen si el correo existe.
import { ANON_KEY, SUPABASE_URL, clientIp, json, rpc, text } from "../_shared/http.ts";

const WRONG = "Correo o contraseña incorrectos.";
const LOCKED =
  "Por seguridad, tu cuenta quedó bloqueada unos minutos por varios intentos fallidos. Probá más tarde o pedile a quien administra tu local que la libere.";
const UNAVAILABLE =
  "Tu cuenta no puede ingresar en este momento. Si creés que es un error, hablá con quien administra tu local.";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_request", message: WRONG });
  }
  const email = text(body.email, 320)?.toLowerCase() ?? null;
  const password =
    typeof body.password === "string" && body.password.length <= 200 ? body.password : null;
  if (!email || !password) return json(400, { error: "invalid_request", message: WRONG });

  const ip = clientIp(req);
  const userAgent = text(
    req.headers.get("x-client-user-agent") ?? req.headers.get("user-agent"),
    300,
  );

  const status = await rpc("login_status", { p_email: email });
  if (!status.ok) return json(502, { error: "unavailable", message: UNAVAILABLE });
  if ((status.data as { locked?: boolean })?.locked)
    return json(423, { error: "locked", message: LOCKED });

  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    // La IP que manda el cliente NO se reenvía a Auth: se puede falsificar y serviría para
    // esquivar su límite por IP. Queda solo como dato informativo en el registro (ADR-0014).
    headers: {
      apikey: ANON_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  });
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;

  if (res.ok) {
    return json(200, {
      session: {
        access_token: data.access_token,
        refresh_token: data.refresh_token,
        expires_in: data.expires_in,
        expires_at: data.expires_at,
        token_type: data.token_type,
      },
    });
  }

  if (data.error_code === "invalid_credentials") {
    const failed = await rpc("record_failed_login", {
      p_email: email,
      p_ip: ip,
      p_user_agent: userAgent,
    });
    const locked = (failed.data as { locked?: boolean })?.locked === true;
    return json(
      locked ? 423 : 401,
      locked
        ? { error: "locked", message: LOCKED }
        : { error: "invalid_credentials", message: WRONG },
    );
  }
  if (res.status === 429)
    return json(429, { error: "rate_limited", message: "Demasiados intentos. Esperá un momento." });
  // El hook negó el token: la contraseña era correcta pero la cuenta está desactivada o bloqueada.
  if (res.status === 403 || res.status === 422 || res.status === 500) {
    return json(403, { error: "account_unavailable", message: UNAVAILABLE });
  }
  return json(502, { error: "unavailable", message: UNAVAILABLE });
});
