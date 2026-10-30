import { cache } from "react";
import { redirect } from "next/navigation";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";

// Capa de acceso a la sesión (Data Access Layer de Next): una sola lectura por pedido.
// La seguridad real está en la base; esto solo decide a qué pantalla mandar a la persona.
const mySessionSchema = z.object({
  signed_in: z.boolean(),
  session_active: z.boolean().optional(),
  user_id: z.string().uuid().optional(),
  has_profile: z.boolean().optional(),
  status: z.enum(["active", "suspended", "deactivated"]).nullable().optional(),
  deleted: z.boolean().optional(),
  locked: z.boolean().optional(),
  first_name: z.string().nullable().optional(),
  last_name: z.string().nullable().optional(),
  email: z.string().nullable().optional(),
  aal: z.string().nullable().optional(),
  requires_mfa: z.boolean().optional(),
  has_roles: z.boolean().optional(),
  can_operate: z.boolean().optional(),
});
export type MySession = z.infer<typeof mySessionSchema>;

export const getMySession = cache(async (): Promise<MySession> => {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("my_session");
  if (error || !data) return { signed_in: false };
  const parsed = mySessionSchema.safeParse(data);
  return parsed.success ? parsed.data : { signed_in: false };
});

export function displayName(session: MySession): string {
  const name = [session.first_name, session.last_name].filter(Boolean).join(" ");
  return name || session.email || "Persona";
}

// Exige una sesión que pueda operar; si no, manda a la pantalla que corresponde.
export async function requireOperable(): Promise<MySession> {
  const session = await getMySession();
  // Una sesión cerrada desde otro dispositivo (o por una baja) vuelve a ingresar.
  if (!session.signed_in || session.session_active === false) redirect("/ingresar");
  if (!session.has_profile || session.deleted || session.status !== "active" || session.locked)
    redirect("/sin-acceso");
  if (session.requires_mfa && session.aal !== "aal2") redirect("/ingresar/doble-verificacion");
  if (!session.has_roles || !session.can_operate) redirect("/sin-acceso");
  return session;
}

// Qué menús mostrar. SOLO para la interfaz: cada acción la vuelve a validar la base.
export const getMenus = cache(async () => {
  const supabase = await createClient();
  const check = async (permission: string) => {
    const { data } = await supabase
      .schema("core")
      .rpc("has_permission_anywhere", { p_permission: permission });
    return data === true;
  };
  // El catálogo es de todo el grupo: la base pide catalog.manage para el grupo entero, así que el
  // menú usa la misma regla (no basta tenerlo en una marca o un local).
  const groupWide = async (permission: string) => {
    const { data } = await supabase
      .schema("core")
      .rpc("permitted_group_ids", { p_permission: permission });
    return Array.isArray(data) && data.length > 0;
  };
  const [
    users,
    invite,
    approvals,
    audit,
    auditExport,
    roles,
    testDocuments,
    catalog,
    catalogManage,
    yieldsRecord,
    yieldsApprove,
  ] = await Promise.all([
    check("users.view"),
    check("users.invite"),
    check("approvals.view"),
    check("audit.view"),
    check("audit.export"),
    check("permissions.manage"),
    check("test_documents.view"),
    check("catalog.view"),
    groupWide("catalog.manage"),
    // Ensayos y propuestas de rendimiento: en su local o su marca (la base controla dónde).
    check("yields.record"),
    // Procesos de rendimiento: los administra quien aprueba estándares para todo el grupo.
    groupWide("yields.approve"),
  ]);
  return {
    users,
    invite,
    approvals,
    audit,
    auditExport,
    roles,
    testDocuments,
    catalog,
    catalogManage,
    yieldsRecord,
    yieldsApprove,
    // Configuración del catálogo: categorías (catalog.manage) o procesos (yields.approve).
    catalogSettings: catalogManage || yieldsApprove,
  };
});

export type Menus = Awaited<ReturnType<typeof getMenus>>;

// Pantallas con menú propio: si la persona no tiene ese menú, vuelve al inicio. Solo interfaz:
// los datos ya los filtra la base. Usa los mismos menús, sin repetir la lógica de permisos.
export async function requireMenu(menu: keyof Menus): Promise<MySession> {
  const session = await requireOperable();
  const menus = await getMenus();
  if (!menus[menu]) redirect("/");
  return session;
}
