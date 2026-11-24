// Ficha de la persona en una pantalla (ADR-0062): el borrador, qué cambió y lo que viaja a la base para guardarlo todo
// junto (core.save_user_sheet). Sin React ni Supabase, para probarlo con Vitest.

export type UserField = "first_name" | "last_name" | "job_title" | "area_id";
export const USER_FIELDS: UserField[] = ["first_name", "last_name", "job_title", "area_id"];

export type SheetRole = {
  // Clave de la pantalla: el id de la asignación, o «nuevo-N» para un rol sin guardar.
  key: string;
  assignmentId: string | null;
  roleCode: string;
  roleName: string;
  // El lugar codificado (lib/data.ts, getPlaces), solo en los nuevos.
  place: string;
  placeLabel: string;
  removed: boolean;
};

export type UserDraft = { fields: Record<UserField, string>; roles: SheetRole[] };

export type UserChanges = { fields: UserField[]; roles: string[] };

export function userChanges(saved: UserDraft, draft: UserDraft): UserChanges {
  return {
    fields: USER_FIELDS.filter((f) => saved.fields[f].trim() !== draft.fields[f].trim()),
    roles: draft.roles.filter((r) => (r.assignmentId ? r.removed : !r.removed)).map((r) => r.key),
  };
}

export function countUserChanges(c: UserChanges): number {
  return c.fields.length + c.roles.length;
}

export type UserPayload = {
  profile?: Partial<Record<UserField, string>>;
  roles_add?: { role_code: string; place: string }[];
  roles_remove?: string[];
};

/** Lo que viaja al guardar: solo lo que cambió. */
export function userPayload(saved: UserDraft, draft: UserDraft): UserPayload {
  const c = userChanges(saved, draft);
  const out: UserPayload = {};
  if (c.fields.length > 0)
    out.profile = Object.fromEntries(c.fields.map((f) => [f, draft.fields[f].trim()]));
  const removed = draft.roles.flatMap((r) => (r.assignmentId && r.removed ? [r.assignmentId] : []));
  const added = draft.roles.filter((r) => !r.assignmentId && !r.removed);
  if (removed.length > 0) out.roles_remove = removed;
  if (added.length > 0)
    out.roles_add = added.map((r) => ({ role_code: r.roleCode, place: r.place }));
  return out;
}

/** «En 1 marca y 1 local», «En todo el grupo»: dónde usa sus roles. */
export function rolePlaces(
  roles: { scope_type: "group" | "brand" | "restaurant"; scope_name: string | null }[],
): string {
  const distinct = (type: string) =>
    new Set(roles.filter((r) => r.scope_type === type).map((r) => r.scope_name ?? "")).size;
  const brands = distinct("brand");
  const places = distinct("restaurant");
  const parts = [
    distinct("group") > 0 ? "todo el grupo" : "",
    brands > 0 ? (brands === 1 ? "1 marca" : `${brands} marcas`) : "",
    places > 0 ? (places === 1 ? "1 local" : `${places} locales`) : "",
  ].filter(Boolean);
  if (parts.length === 0) return "Sin roles";
  if (parts.length === 1) return `En ${parts[0]}`;
  return `En ${parts.slice(0, -1).join(", ")} y ${parts[parts.length - 1]}`;
}

/** Un rol que ya tiene, o que ya se agregó, en el mismo lugar: no se agrega dos veces. */
export function hasRole(draft: UserDraft, roleCode: string, placeLabel: string): boolean {
  return draft.roles.some(
    (r) => !r.removed && r.roleCode === roleCode && r.placeLabel === placeLabel,
  );
}
