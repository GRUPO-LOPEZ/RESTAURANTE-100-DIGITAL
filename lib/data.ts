import { z } from "zod";

import { createClient } from "@/lib/supabase/server";

// Lecturas para las pantallas. Todo pasa por la base con la sesión de la persona: lo que
// devuelve ya está filtrado por sus permisos (RLS y funciones de la Fase 1).
// Si una lectura falla, se corta con un error (lo muestra app/error.tsx): nunca se muestra
// "no hay datos" cuando en realidad no se pudo consultar.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuidOrUndefined(value: string | undefined): string | undefined {
  return value && UUID.test(value) ? value : undefined;
}

export function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

const accountStatus = z.enum(["active", "suspended", "deactivated"]);
export type AccountStatus = z.infer<typeof accountStatus>;

const roleChip = z.object({
  assignment_id: z.string(),
  role_code: z.string(),
  role_name: z.string(),
  scope_type: z.enum(["group", "brand", "restaurant"]),
  scope_name: z.string().nullable(),
});
export type RoleChip = z.infer<typeof roleChip>;

const userRow = z.object({
  id: z.string(),
  first_name: z.string().nullable(),
  last_name: z.string().nullable(),
  email: z.string(),
  status: accountStatus,
  locked: z.boolean(),
  roles: z.array(roleChip),
  sort_key: z.string(),
  job_title: z.string().nullable(),
  area_name: z.string().nullable(),
  last_seen_at: z.string().nullable(),
});
export type UserRow = z.infer<typeof userRow>;

export type UsersFilter = {
  search?: string;
  brandId?: string;
  restaurantId?: string;
  status?: string;
  roleCode?: string;
  areaId?: string;
  afterKey?: string;
  afterId?: string;
};

export async function getUsers(filter: UsersFilter, limit = 25): Promise<UserRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("users_dashboard", {
    p_search: filter.search || undefined,
    p_brand_id: filter.brandId || undefined,
    p_restaurant_id: filter.restaurantId || undefined,
    p_status: filter.status || undefined,
    p_role_code: filter.roleCode || undefined,
    p_area_id: filter.areaId || undefined,
    p_after_key: filter.afterKey || undefined,
    p_after_id: filter.afterId || undefined,
    p_limit: limit,
  });
  if (error) failed("las personas");
  const parsed = z.array(userRow).safeParse(data);
  return parsed.success ? parsed.data : failed("las personas");
}

export async function getUser(userId: string): Promise<UserRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .rpc("users_dashboard", { p_user_id: userId, p_limit: 1 });
  if (error) failed("la persona");
  const parsed = z.array(userRow).safeParse(data);
  return parsed.success ? (parsed.data[0] ?? null) : failed("la persona");
}

// Tablero de control de usuarios (sección 9 del documento de Soy).
const historyRow = z.object({
  sequence_number: z.number(),
  occurred_at: z.string(),
  actor_name: z.string(),
  actor_role_code: z.string().nullable(),
  action: z.string(),
  module: z.string().nullable(),
  table_schema: z.string(),
  table_name: z.string(),
  record_id: z.string(),
  changed_fields: z.array(z.string()).nullable(),
  old_values: z.record(z.string(), z.unknown()).nullable(),
  new_values: z.record(z.string(), z.unknown()).nullable(),
  reason: z.string().nullable(),
  source: z.string().nullable(),
  place_name: z.string().nullable(),
});
export type HistoryRow = z.infer<typeof historyRow>;

const controlPanel = z.object({
  as_of: z.string(),
  from: z.string(),
  to: z.string(),
  can_view_security: z.boolean(),
  active: z.number(),
  suspended: z.number(),
  deactivated: z.number(),
  locked: z.number(),
  pending_approvals: z.number(),
  rejected_7d: z.number().nullable(),
  rejected_prev_7d: z.number().nullable(),
  logins_by_day: z
    .array(z.object({ day: z.string(), succeeded: z.number(), failed: z.number() }))
    .nullable(),
  by_role: z.array(z.object({ role_code: z.string(), role_name: z.string(), people: z.number() })),
  by_restaurant: z.array(
    z.object({
      restaurant_id: z.string(),
      restaurant_name: z.string(),
      brand_name: z.string(),
      people: z.number(),
    }),
  ),
  group_wide_people: z.number(),
  critical_changes: z.array(historyRow),
});
export type ControlPanel = z.infer<typeof controlPanel>;

export type PanelFilter = {
  from?: string;
  to?: string;
  brandId?: string;
  restaurantId?: string;
  module?: string;
};

export async function getControlPanel(filter: PanelFilter): Promise<ControlPanel> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("users_control_panel", {
    p_from: filter.from || undefined,
    p_to: filter.to || undefined,
    p_brand_id: filter.brandId || undefined,
    p_restaurant_id: filter.restaurantId || undefined,
    p_module: filter.module || undefined,
  });
  if (error) failed("el tablero");
  const parsed = controlPanel.safeParse(data);
  return parsed.success ? parsed.data : failed("el tablero");
}

// Ficha de una persona.
const userDetail = z.object({
  id: z.string(),
  username: z.string().nullable(),
  job_title: z.string().nullable(),
  area_id: z.string().nullable(),
  area_name: z.string().nullable(),
  activated_at: z.string().nullable(),
  last_seen_at: z.string().nullable(),
  invited_by_name: z.string().nullable(),
  status: accountStatus,
  suspended_at: z.string().nullable(),
  suspension_reason: z.string().nullable(),
  suspended_by_name: z.string().nullable(),
  deactivated_at: z.string().nullable(),
  deactivation_reason: z.string().nullable(),
  deactivated_by_name: z.string().nullable(),
  workplaces: z.array(
    z.object({
      group_name: z.string(),
      brand_name: z.string().nullable(),
      restaurant_name: z.string().nullable(),
      starts_at: z.string(),
      ends_at: z.string().nullable(),
    }),
  ),
  can_view_activity: z.boolean(),
  recent_activity: z.array(
    z.object({
      occurred_at: z.string(),
      action: z.string(),
      table_name: z.string(),
      reason: z.string().nullable(),
      place_name: z.string().nullable(),
    }),
  ),
  can_view_security: z.boolean(),
  rejected_attempts: z
    .array(
      z.object({
        occurred_at: z.string(),
        event_type: z.string(),
        operation: z.string().nullable(),
        reason: z.string().nullable(),
      }),
    )
    .nullable(),
});
export type UserDetail = z.infer<typeof userDetail>;

export async function getUserDetail(userId: string): Promise<UserDetail | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("user_detail", { p_user_id: userId });
  if (error) failed("la ficha");
  if (data === null) return null;
  const parsed = userDetail.safeParse(data);
  return parsed.success ? parsed.data : failed("la ficha");
}

// Bandeja de aprobaciones, con el antes y el después.
const jsonObject = z.record(z.string(), z.unknown());
const inboxRow = z.object({
  id: z.string(),
  workflow_code: z.string(),
  workflow_name: z.string(),
  status: z.enum(["pending", "approved", "rejected", "cancelled"]),
  requested_at: z.string(),
  requested_by_name: z.string().nullable(),
  summary: z.string().nullable(),
  reason: z.string(),
  place_name: z.string().nullable(),
  can_decide: z.boolean(),
  resolved_at: z.string().nullable(),
  resolved_by_name: z.string().nullable(),
  resolution_comment: z.string().nullable(),
  entity_table: z.string().nullable(),
  previous_values: jsonObject.nullable(),
  proposed_changes: jsonObject.nullable(),
});
export type InboxRow = z.infer<typeof inboxRow>;

export async function getInbox(pending: boolean, limit = 50): Promise<InboxRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("workflow")
    .rpc("inbox", { p_pending: pending, p_limit: limit });
  if (error) failed("las solicitudes");
  const parsed = z.array(inboxRow).safeParse(data);
  return parsed.success ? parsed.data : failed("las solicitudes");
}

// Avisos sin leer de la sesión (la RLS deja ver solo los propios).
export async function getUnreadCount(): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .schema("core")
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .is("read_at", null)
    .is("deleted_at", null);
  if (error) return 0;
  return count ?? 0;
}

// Historial con filtros (sección 9).
export type HistoryFilter = {
  before?: number;
  recordId?: string;
  from?: string;
  to?: string;
  actorId?: string;
  brandId?: string;
  restaurantId?: string;
  module?: string;
};

export const HISTORY_PAGE = 50;

export async function getHistory(filter: HistoryFilter): Promise<HistoryRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("audit_history", {
    p_limit: HISTORY_PAGE,
    p_before: filter.before,
    p_record_id: filter.recordId,
    p_from: filter.from,
    p_to: filter.to,
    p_actor_id: filter.actorId,
    p_brand_id: filter.brandId,
    p_restaurant_id: filter.restaurantId,
    p_module: filter.module,
  });
  if (error) failed("el historial");
  const parsed = z.array(historyRow).safeParse(data);
  return parsed.success ? parsed.data : failed("el historial");
}

// Matriz de roles y permisos.
const matrix = z.object({
  can_manage: z.boolean(),
  roles: z.array(
    z.object({
      id: z.string(),
      code: z.string(),
      name: z.string(),
      level: z.number().nullable(),
      requires_mfa: z.boolean(),
      is_mine: z.boolean(),
    }),
  ),
  permissions: z.array(
    z.object({
      code: z.string(),
      module: z.string(),
      action: z.string(),
      description: z.string(),
      is_sensitive: z.boolean(),
    }),
  ),
  grants: z.array(z.object({ role_code: z.string(), permission_code: z.string() })),
  pending: z.array(
    z.object({
      request_id: z.string(),
      role_code: z.string(),
      permission_code: z.string(),
      grant: z.boolean(),
      requested_by_name: z.string().nullable(),
      requested_at: z.string(),
      reason: z.string(),
    }),
  ),
});
export type PermissionMatrix = z.infer<typeof matrix>;

export async function getPermissionMatrix(groupId: string): Promise<PermissionMatrix | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .rpc("permission_matrix", { p_group_id: groupId });
  if (error) failed("la matriz de permisos");
  if (data === null) return null;
  const parsed = matrix.safeParse(data);
  return parsed.success ? parsed.data : failed("la matriz de permisos");
}

// Mi cuenta.
const myAccount = z.object({
  first_name: z.string().nullable(),
  last_name: z.string().nullable(),
  email: z.string(),
  username: z.string().nullable(),
  job_title: z.string().nullable(),
  activated_at: z.string().nullable(),
  last_seen_at: z.string().nullable(),
  mfa_factors: z.array(
    z.object({
      id: z.string(),
      friendly_name: z.string().nullable(),
      factor_type: z.string(),
      status: z.string(),
      created_at: z.string(),
    }),
  ),
  sessions: z.array(
    z.object({
      id: z.string(),
      created_at: z.string(),
      last_used_at: z.string().nullable(),
      user_agent: z.string().nullable(),
      aal: z.string().nullable(),
      is_current: z.boolean(),
    }),
  ),
});
export type MyAccount = z.infer<typeof myAccount>;

export async function getMyAccount(): Promise<MyAccount | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("my_account");
  if (error) failed("tu cuenta");
  if (data === null) return null;
  const parsed = myAccount.safeParse(data);
  return parsed.success ? parsed.data : failed("tu cuenta");
}

// Mis marcas y locales, y el local elegido en el selector.
const scopeRow = z.object({
  brand_id: z.string(),
  brand_name: z.string(),
  brand_code: z.string(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  restaurant_code: z.string().nullable(),
});
export type ScopeRow = z.infer<typeof scopeRow>;

export async function getMyScopes(): Promise<ScopeRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("my_scopes");
  if (error) return [];
  const parsed = z.array(scopeRow).safeParse(data);
  return parsed.success ? parsed.data : [];
}

export async function getActiveRestaurantId(userId: string | undefined): Promise<string | null> {
  if (!userId) return null;
  const supabase = await createClient();
  const { data } = await supabase
    .schema("core")
    .from("user_profiles")
    .select("last_restaurant_id")
    .eq("id", userId)
    .maybeSingle();
  return data?.last_restaurant_id ?? null;
}

// Documentos de ensayo (la vista ya oculta el costo a quien no lo puede ver).
export type TestDocument = {
  id: string;
  brand_id: string;
  restaurant_id: string | null;
  document_key: string;
  version_number: number;
  title: string;
  content: string | null;
  cost: number | null;
  currency: string;
  status: "draft" | "in_review" | "approved" | "published" | "archived";
  updated_at: string;
};

export async function getTestDocuments(): Promise<TestDocument[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .from("v_test_documents")
    .select(
      "id, brand_id, restaurant_id, document_key, version_number, title, content, cost, currency, status, updated_at",
    )
    .neq("status", "archived")
    .order("title")
    .order("version_number", { ascending: false })
    .limit(100);
  if (error) failed("los documentos de ensayo");
  return (data ?? []).flatMap((d) =>
    d.id && d.brand_id && d.document_key && d.title && d.status && d.updated_at
      ? [
          {
            id: d.id,
            brand_id: d.brand_id,
            restaurant_id: d.restaurant_id,
            document_key: d.document_key,
            version_number: d.version_number ?? 1,
            title: d.title,
            content: d.content,
            cost: d.cost,
            currency: d.currency ?? "ARS",
            status: d.status,
            updated_at: d.updated_at,
          },
        ]
      : [],
  );
}

// Catálogo de roles y lugares visibles (para formularios y filtros).
export async function getRoles(): Promise<{ code: string; name: string; level: number | null }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .from("roles")
    .select("code, name, level")
    .is("deleted_at", null)
    .order("level");
  if (error) failed("los roles");
  return data ?? [];
}

export type Place = { value: string; label: string };

// Lugares en los que se puede asignar un rol, codificados como "scope:grupo:marca:local".
export async function getPlaces(): Promise<Place[]> {
  const supabase = await createClient();
  const [groups, brands, restaurants] = await Promise.all([
    supabase.schema("org").from("groups").select("id, name").is("deleted_at", null).order("name"),
    supabase
      .schema("org")
      .from("brands")
      .select("id, name, group_id")
      .is("deleted_at", null)
      .order("name"),
    supabase
      .schema("org")
      .from("restaurants")
      .select("id, name, group_id, brand_id")
      .is("deleted_at", null)
      .order("name"),
  ]);
  if (groups.error || brands.error || restaurants.error) failed("los lugares");
  const places: Place[] = [];
  for (const g of groups.data ?? [])
    places.push({ value: `group:${g.id}::`, label: `Todo el grupo · ${g.name}` });
  for (const b of brands.data ?? [])
    places.push({ value: `brand:${b.group_id}:${b.id}:`, label: `Marca · ${b.name}` });
  for (const r of restaurants.data ?? []) {
    places.push({
      value: `restaurant:${r.group_id}:${r.brand_id}:${r.id}`,
      label: `Local · ${r.name}`,
    });
  }
  return places;
}

export async function getBrandsAndRestaurants(): Promise<{
  groups: { id: string; name: string }[];
  brands: { id: string; name: string }[];
  restaurants: { id: string; name: string; brand_id: string }[];
}> {
  const supabase = await createClient();
  const [groups, brands, restaurants] = await Promise.all([
    supabase.schema("org").from("groups").select("id, name").is("deleted_at", null).order("name"),
    supabase.schema("org").from("brands").select("id, name").is("deleted_at", null).order("name"),
    supabase
      .schema("org")
      .from("restaurants")
      .select("id, name, brand_id")
      .is("deleted_at", null)
      .order("name"),
  ]);
  if (groups.error || brands.error || restaurants.error) failed("las marcas y los locales");
  return {
    groups: groups.data ?? [],
    brands: brands.data ?? [],
    restaurants: restaurants.data ?? [],
  };
}

export async function getAreas(): Promise<{ id: string; label: string }[]> {
  const supabase = await createClient();
  const [areas, restaurants] = await Promise.all([
    supabase
      .schema("org")
      .from("areas")
      .select("id, name, restaurant_id")
      .is("deleted_at", null)
      .order("name"),
    supabase.schema("org").from("restaurants").select("id, name").is("deleted_at", null),
  ]);
  if (areas.error || restaurants.error) failed("las áreas");
  const names = new Map((restaurants.data ?? []).map((r) => [r.id, r.name]));
  return (areas.data ?? []).map((a) => ({
    id: a.id,
    label: `${a.name} · ${names.get(a.restaurant_id) ?? ""}`,
  }));
}

const placeSchema = z
  .string()
  .regex(/^(group|brand|restaurant):[0-9a-f-]{36}:([0-9a-f-]{36})?:([0-9a-f-]{36})?$/)
  .transform((value) => {
    const [scope, group, brand, restaurant] = value.split(":") as [string, string, string, string];
    return {
      scope: scope as "group" | "brand" | "restaurant",
      groupId: group,
      brandId: brand || null,
      restaurantId: restaurant || null,
    };
  });

export function parsePlace(value: FormDataEntryValue | null) {
  return placeSchema.safeParse(value);
}

export const ACTION_LABELS: Record<string, string> = {
  insert: "Alta",
  update: "Cambio",
  soft_delete: "Borrado",
  restore: "Restauración",
  delete: "Borrado físico",
  approve: "Aprobación",
  reject: "Rechazo",
  publish: "Publicación",
};

export const TABLE_LABELS: Record<string, string> = {
  "org.groups": "Grupo",
  "org.brands": "Marca",
  "org.restaurants": "Local",
  "org.areas": "Área",
  "core.user_profiles": "Persona",
  "core.user_memberships": "Lugar de trabajo",
  "core.user_role_assignments": "Rol de una persona",
  "core.roles": "Rol",
  "core.permissions": "Permiso",
  "core.role_permissions": "Permiso de un rol",
  "core.notifications": "Aviso",
  "core.test_documents": "Documento de ensayo",
  "workflow.approval_requests": "Solicitud de aprobación",
  "workflow.approval_decisions": "Decisión de aprobación",
  "workflow.approval_workflows": "Tipo de aprobación",
};

// Módulos del historial (audit.module_for), con su nombre en español.
export const MODULE_LABELS: Record<string, string> = {
  org: "Estructura",
  users: "Personas",
  roles: "Roles y permisos",
  approvals: "Aprobaciones",
  notifications: "Avisos",
  test_documents: "Documentos de ensayo",
};

// Campos que se muestran en el historial y en el "antes y después", con su nombre en español.
// Los que no están acá (ids, datos técnicos) no se muestran: el historial completo queda en la base.
export const FIELD_LABELS: Record<string, string> = {
  name: "Nombre",
  status: "Estado",
  first_name: "Nombre",
  last_name: "Apellido",
  email: "Correo",
  code: "Código",
  address: "Dirección",
  locality: "Barrio o localidad",
  legal_name: "Razón social",
  tax_id: "CUIT",
  phone: "Teléfono",
  opened_on: "Fecha de apertura",
  time_zone: "Zona horaria",
  scope_type: "Alcance",
  valid_from: "Desde",
  valid_until: "Hasta",
  starts_at: "Desde",
  ends_at: "Hasta",
  deactivated_at: "Desactivada el",
  deactivation_reason: "Motivo de la baja",
  suspended_at: "Suspendida el",
  suspension_reason: "Motivo de la suspensión",
  job_title: "Puesto",
  username: "Usuario",
  locked_until: "Bloqueada hasta",
  decision: "Decisión",
  comment: "Comentario",
  reason: "Motivo",
  resolved_at: "Resuelta el",
  resolution_comment: "Comentario de la resolución",
  deleted_at: "Borrado el",
  description: "Descripción",
  title: "Título",
  content: "Contenido",
  version_number: "Versión",
  cost: "Costo",
  role_code: "Rol",
  roles: "Roles",
  permission_code: "Permiso",
  grant: "Lo tiene",
  new_name: "Nombre nuevo",
  deleted: "Quitado",
};

const VALUE_LABELS: Record<string, string> = {
  active: "Activa",
  inactive: "Cerrada",
  suspended: "Suspendida",
  deactivated: "Desactivada",
  pending: "Pendiente",
  approved: "Aprobada",
  rejected: "Rechazada",
  cancelled: "Retirada",
  group: "Todo el grupo",
  brand: "Marca",
  restaurant: "Local",
  draft: "Borrador",
  in_review: "En revisión",
  published: "Publicada",
  archived: "Archivada",
};

// Un valor del historial en lenguaje simple: fechas formateadas, estados traducidos, sin JSON.
export function formatValue(value: unknown, roleNames?: Record<string, string>): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Sí" : "No";
  if (typeof value === "number") return String(value);
  if (typeof value === "string") {
    if (roleNames?.[value]) return roleNames[value];
    if (VALUE_LABELS[value]) return VALUE_LABELS[value];
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)) return formatDateTime(value);
    return value;
  }
  if (Array.isArray(value) && value.every((v) => typeof v === "string"))
    return value.length === 0 ? "Ninguno" : value.map((v) => formatValue(v, roleNames)).join(", ");
  return "(dato técnico)";
}

export const SCOPE_LABELS = { group: "Grupo", brand: "Marca", restaurant: "Local" } as const;

export const STATUS_LABELS: Record<AccountStatus, string> = {
  active: "Activa",
  suspended: "Suspendida",
  deactivated: "Desactivada",
};

export function personName(row: {
  first_name: string | null;
  last_name: string | null;
  email: string;
}): string {
  return [row.first_name, row.last_name].filter(Boolean).join(" ") || row.email;
}

export function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("es-AR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Argentina/Buenos_Aires",
  }).format(new Date(value));
}

export function formatDate(value: string): string {
  return new Intl.DateTimeFormat("es-AR", {
    dateStyle: "short",
    timeZone: "America/Argentina/Buenos_Aires",
  }).format(new Date(value.length === 10 ? `${value}T12:00:00-03:00` : value));
}

export function formatMoney(value: number, currency: string): string {
  return new Intl.NumberFormat("es-AR", { style: "currency", currency }).format(value);
}
