import { z } from "zod";

import { createClient } from "@/lib/supabase/server";

// Lecturas para las pantallas. Todo pasa por la base con la sesión de la persona: lo que
// devuelve ya está filtrado por sus permisos (RLS y funciones de M5 a M8).
// Si una lectura falla, se corta con un error (lo muestra app/error.tsx): nunca se muestra
// "no hay datos" cuando en realidad no se pudo consultar.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

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
  status: z.enum(["active", "disabled"]),
  locked: z.boolean(),
  roles: z.array(roleChip),
  sort_key: z.string(),
});
export type UserRow = z.infer<typeof userRow>;

export type UsersFilter = {
  search?: string;
  brandId?: string;
  restaurantId?: string;
  status?: string;
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

const overview = z.object({
  as_of: z.string(),
  active: z.number(),
  disabled: z.number(),
  locked: z.number(),
  without_mfa: z.number(),
  pending_approvals: z.number(),
  by_role: z.array(z.object({ role_code: z.string(), role_name: z.string(), people: z.number() })),
});
export type UsersOverview = z.infer<typeof overview>;

export async function getUsersOverview(
  filter: Pick<UsersFilter, "brandId" | "restaurantId">,
): Promise<UsersOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("users_overview", {
    p_brand_id: filter.brandId || undefined,
    p_restaurant_id: filter.restaurantId || undefined,
  });
  if (error) failed("los indicadores");
  const parsed = overview.safeParse(data);
  return parsed.success ? parsed.data : failed("los indicadores");
}

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

const historyRow = z.object({
  sequence_number: z.number(),
  occurred_at: z.string(),
  actor_name: z.string(),
  action: z.string(),
  schema_name: z.string(),
  table_name: z.string(),
  record_id: z.string(),
  changed_fields: z.array(z.string()).nullable(),
  old_values: z.record(z.string(), z.unknown()).nullable(),
  new_values: z.record(z.string(), z.unknown()).nullable(),
  reason: z.string().nullable(),
  origin: z.string().nullable(),
  place_name: z.string().nullable(),
});
export type HistoryRow = z.infer<typeof historyRow>;

export async function getHistory(before?: number): Promise<HistoryRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .rpc("audit_history", { p_limit: 50, p_before: before });
  if (error) failed("el historial");
  const parsed = z.array(historyRow).safeParse(data);
  return parsed.success ? parsed.data : failed("el historial");
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
  brands: { id: string; name: string }[];
  restaurants: { id: string; name: string; brand_id: string }[];
}> {
  const supabase = await createClient();
  const [brands, restaurants] = await Promise.all([
    supabase.schema("org").from("brands").select("id, name").is("deleted_at", null).order("name"),
    supabase
      .schema("org")
      .from("restaurants")
      .select("id, name, brand_id")
      .is("deleted_at", null)
      .order("name"),
  ]);
  if (brands.error || restaurants.error) failed("las marcas y los locales");
  return { brands: brands.data ?? [], restaurants: restaurants.data ?? [] };
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
};

export const TABLE_LABELS: Record<string, string> = {
  "org.groups": "Grupo",
  "org.brands": "Marca",
  "org.restaurants": "Local",
  "org.areas": "Área",
  "core.user_profiles": "Persona",
  "core.user_memberships": "Membresía",
  "core.user_role_assignments": "Rol de una persona",
  "core.roles": "Rol",
  "core.permissions": "Permiso",
  "core.role_permissions": "Permiso de un rol",
  "workflow.approval_requests": "Solicitud de aprobación",
  "workflow.approval_decisions": "Decisión de aprobación",
  "workflow.approval_workflows": "Tipo de aprobación",
};

// Campos que se muestran en el historial, con su nombre en español. Los que no están acá
// (ids, datos técnicos) no se muestran: el historial completo queda en la base.
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
  disabled_at: "Desactivada el",
  disabled_reason: "Motivo de la baja",
  locked_until: "Bloqueada hasta",
  decision: "Decisión",
  comment: "Comentario",
  reason: "Motivo",
  resolved_at: "Resuelta el",
  resolution_comment: "Comentario de la resolución",
  deleted_at: "Borrado el",
  description: "Descripción",
};

const VALUE_LABELS: Record<string, string> = {
  active: "Activa",
  inactive: "Cerrada",
  disabled: "Desactivada",
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
export function formatValue(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Sí" : "No";
  if (typeof value === "number") return String(value);
  if (typeof value === "string") {
    if (VALUE_LABELS[value]) return VALUE_LABELS[value];
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)) return formatDateTime(value);
    return value;
  }
  return "(dato técnico)";
}

export const SCOPE_LABELS = { group: "Grupo", brand: "Marca", restaurant: "Local" } as const;

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
