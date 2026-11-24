import { z } from "zod";

import {
  IN_WORDS,
  SETTINGS_LISTS,
  inputNumber,
  type ListItem,
  EMPTY_FIELDS,
} from "@/lib/settings-lists";
import type { SettingsListCode } from "@/lib/settings-lists";
import { createClient } from "@/lib/supabase/server";

// Lecturas de Configuración del catálogo (ADR-0063): todo sale de dos funciones de la base, que controlan quién entra y
// dicen qué edita cada sesión.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

// Los grupos donde la sesión administra alguna lista. Hoy hay un solo grupo; si se suman otros, la pantalla va a tener
// que elegir cuál.
const SETTINGS_PERMISSIONS = [
  "catalog.manage",
  "recipes.manage_categories",
  "recipes.draft",
  "yields.approve",
];

export async function getSettingsGroup(): Promise<string | null> {
  const supabase = await createClient();
  const results = await Promise.all(
    SETTINGS_PERMISSIONS.map((p_permission) =>
      supabase.schema("core").rpc("permitted_group_ids", { p_permission }),
    ),
  );
  for (const { data, error } of results) {
    if (error) failed("los grupos");
    const group = Array.isArray(data) ? data.find((x): x is string => typeof x === "string") : null;
    if (group) return group;
  }
  return null;
}

const overviewSchema = z.array(
  z.object({ list: z.enum(SETTINGS_LISTS), can_edit: z.boolean(), active: z.number() }),
);
export type SettingsOverview = z.infer<typeof overviewSchema>;

export async function getSettingsLists(groupId: string): Promise<SettingsOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .rpc("settings_lists", { p_group_id: groupId });
  if (error) failed("las listas del catálogo");
  return overviewSchema.parse(data);
}

const text = z.string().nullish();
const rowSchema = z.object({
  id: z.string(),
  name: z.string(),
  active: z.boolean(),
  editable: z.boolean(),
  uses: z.number().nullish(),
  why: text,
  code: text,
  parent_id: text,
  capacity: z.number().nullish(),
  capacity_unit: text,
  capacity_label: text,
  content: z.number().nullish(),
  content_unit: text,
  usage_note: text,
  abbreviation: text,
  dimension: text,
  is_base: z.boolean().nullish(),
  factor: z.number().nullish(),
  base_unit: text,
});
const listSchema = z.object({
  can_edit: z.boolean(),
  stamp: z.string(),
  rows: z.array(rowSchema),
});

export type SettingsList = { canEdit: boolean; stamp: string; items: ListItem[] };

export async function getSettingsList(
  groupId: string,
  list: SettingsListCode,
): Promise<SettingsList> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .rpc("settings_list", { p_group_id: groupId, p_list: list });
  if (error) failed("la lista");
  const parsed = listSchema.parse(data);
  return {
    canEdit: parsed.can_edit,
    stamp: parsed.stamp,
    items: parsed.rows.map((r) => ({
      key: r.id,
      id: r.id,
      active: r.active,
      editable: r.editable,
      uses: r.uses ?? 0,
      why: r.why ?? null,
      isBase: r.is_base ?? false,
      baseUnit: r.base_unit ?? "",
      fields: {
        ...EMPTY_FIELDS,
        name: r.name,
        parentId: r.parent_id ?? "",
        code: r.code ?? "",
        capacity: inputNumber(r.capacity ?? null),
        capacityUnit: r.capacity_label ? IN_WORDS : (r.capacity_unit ?? ""),
        capacityLabel: r.capacity_label ?? "",
        content: inputNumber(r.content ?? null),
        contentUnit: r.content_unit ?? "ml",
        usageNote: r.usage_note ?? "",
        abbreviation: r.abbreviation ?? "",
        dimension: r.dimension ?? "",
        factor: inputNumber(r.factor ?? null),
      },
    })),
  };
}
