// Ayudas comunes de las Edge Functions de Grupo LF.
// La clave de servidor la pone Supabase en el entorno de la función: nunca llega a la app,
// al navegador ni al repositorio.

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
export const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

export function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

// Encabezados para hablar con la API con una clave. Las claves nuevas (sb_...) no son JWT:
// van solo en apikey.
function keyHeaders(key: string): Record<string, string> {
  const headers: Record<string, string> = { apikey: key };
  if (key.split(".").length === 3) headers.authorization = `Bearer ${key}`;
  return headers;
}

export const serviceHeaders = () => keyHeaders(SERVICE_KEY);

// Llama a una función del esquema core. Con `userToken`, corre con la identidad de esa persona
// (las reglas de permisos se aplican a ella); sin token, con la clave de servidor.
export async function rpc(
  fn: string,
  args: Record<string, unknown>,
  userToken?: string,
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const headers: Record<string, string> = userToken
    ? { apikey: ANON_KEY, authorization: `Bearer ${userToken}` }
    : serviceHeaders();
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { ...headers, "content-type": "application/json", "content-profile": "core" },
    body: JSON.stringify(args),
  });
  const data = await res.json().catch(() => null);
  return { ok: res.ok, status: res.status, data };
}

export function clientIp(req: Request): string | null {
  const raw =
    req.headers.get("x-client-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0] ?? "";
  const ip = raw.trim().slice(0, 64);
  return ip.length > 0 ? ip : null;
}

export function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= max ? trimmed : null;
}
