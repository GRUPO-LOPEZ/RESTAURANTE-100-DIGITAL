import { z } from "zod";

import { createClient } from "@/lib/supabase/server";

// Lecturas para las pantallas. Todo pasa por la base con la sesión de la persona: lo que
// devuelve ya está filtrado por sus permisos (RLS y funciones de M5 a M8).

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
  restaurantId?: string;
  status?: string;
  afterKey?: string;
  afterId?: string;
};

export async function getUsers(filter: UsersFilter, limit = 25): Promise<UserRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("users_dashboard", {
    p_search: filter.search || undefined,
    p_restaurant_id: filter.restaurantId || undefined,
    p_status: filter.status || undefined,
    p_after_key: filter.afterKey || undefined,
    p_after_id: filter.afterId || undefined,
    p_limit: limit,
  });
  if (error) return [];
  return z.array(userRow).catch([]).parse(data);
}

export async function getUser(userId: string): Promise<UserRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .rpc("users_dashboard", { p_user_id: userId, p_limit: 1 });
  if (error) return null;
  return z.array(userRow).catch([]).parse(data)[0] ?? null;
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

export async function getUsersOverview(): Promise<UsersOverview | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("core").rpc("users_overview");
  if (error || !data) return null;
  const parsed = overview.safeParse(data);
  return parsed.success ? parsed.data : null;
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

export async function getInbox(): Promise<InboxRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("workflow").rpc("inbox", { p_limit: 100 });
  if (error) return [];
  return z.array(inboxRow).catch([]).parse(data);
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
  if (error) return [];
  return z.array(historyRow).catch([]).parse(data);
}

// Catálogo de roles y lugares visibles (para formularios).
export async function getRoles(): Promise<{ code: string; name: string; level: number | null }[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .schema("core")
    .from("roles")
    .select("code, name, level")
    .is("deleted_at", null)
    .order("level");
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

export async function getRestaurants(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .schema("org")
    .from("restaurants")
    .select("id, name")
    .is("deleted_at", null)
    .order("name");
  return data ?? [];
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
