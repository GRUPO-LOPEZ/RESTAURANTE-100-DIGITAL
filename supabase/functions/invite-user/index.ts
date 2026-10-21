// Invitar a una persona (alta solo por invitación, plan M8).
// Las validaciones de permisos corren con la identidad de quien invita (su JWT):
//   1) core.can_invite: puede invitar a ese lugar (si no, queda registrado);
//   2) invitación con la Admin API de Auth (clave de servidor, solo acá);
//   3) core.add_member y core.assign_role, con las reglas de M6 (sin escalada, aprobación si
//      el rol aprueba cosas).
import { SUPABASE_URL, json, rpc, serviceHeaders, text } from "../_shared/http.ts";

const SCOPES = new Set(["group", "brand", "restaurant"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const optionalUuid = (value: unknown) =>
  typeof value === "string" && UUID.test(value) ? value : null;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  if (!token)
    return json(401, { error: "unauthorized", message: "Tenés que ingresar para invitar." });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_request", message: "Datos inválidos." });
  }

  const email = text(body.email, 320)?.toLowerCase() ?? null;
  const firstName = text(body.first_name, 80);
  const lastName = text(body.last_name, 80);
  const roleCode = text(body.role_code, 60);
  const scopeType =
    typeof body.scope_type === "string" && SCOPES.has(body.scope_type) ? body.scope_type : null;
  const groupId = optionalUuid(body.group_id);
  const brandId = optionalUuid(body.brand_id);
  const restaurantId = optionalUuid(body.restaurant_id);
  const reason = text(body.reason, 500);
  const redirectTo = text(body.redirect_to, 500);
  if (
    !email ||
    !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ||
    !firstName ||
    !lastName ||
    !roleCode ||
    !scopeType ||
    !groupId ||
    !reason
  ) {
    return json(400, {
      error: "invalid_request",
      message: "Faltan datos: correo, nombre, apellido, rol, lugar y motivo.",
    });
  }

  const scope = {
    p_scope_type: scopeType,
    p_group_id: groupId,
    p_brand_id: brandId,
    p_restaurant_id: restaurantId,
  };
  const allowed = await rpc("can_invite", { ...scope, p_email: email }, token);
  if (!allowed.ok)
    return json(allowed.status === 401 ? 401 : 400, {
      error: "invalid_request",
      message: "No se pudo validar la invitación.",
    });
  if ((allowed.data as { result?: string })?.result !== "allowed") {
    return json(403, {
      error: "denied",
      message: "No tenés permiso para invitar personas a ese lugar.",
    });
  }

  const inviteUrl = new URL(`${SUPABASE_URL}/auth/v1/invite`);
  if (redirectTo) inviteUrl.searchParams.set("redirect_to", redirectTo);
  const invite = await fetch(inviteUrl, {
    method: "POST",
    headers: { ...serviceHeaders(), "content-type": "application/json" },
    body: JSON.stringify({ email, data: { first_name: firstName, last_name: lastName } }),
  });
  const invited = (await invite.json().catch(() => ({}))) as { id?: string; error_code?: string };
  if (!invite.ok || !invited.id) {
    const exists = invite.status === 422 || invited.error_code === "email_exists";
    return json(exists ? 409 : 502, {
      error: exists ? "already_exists" : "invite_failed",
      message: exists ? "Ya hay una cuenta con ese correo." : "No se pudo enviar la invitación.",
    });
  }

  const member = await rpc(
    "add_member",
    { p_user_id: invited.id, p_group_id: groupId, p_reason: reason },
    token,
  );
  const role = await rpc(
    "assign_role",
    {
      p_user_id: invited.id,
      p_role_code: roleCode,
      ...scope,
      p_valid_until: null,
      p_reason: reason,
    },
    token,
  );
  return json(200, {
    result: "invited",
    user_id: invited.id,
    membership: member.data,
    role: role.ok
      ? role.data
      : { result: "error", message: "La invitación salió, pero no se pudo asignar el rol." },
  });
});
