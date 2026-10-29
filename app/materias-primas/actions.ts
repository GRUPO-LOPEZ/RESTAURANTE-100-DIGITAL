"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import type { AllergenStatus, ConversionKind, DataSource } from "@/lib/catalog";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { createClient } from "@/lib/supabase/server";

// Acciones del catálogo. Cada una llama a una función de la base que valida catalog.manage, pide
// el motivo y deja la auditoría (ADR-0012): la pantalla solo valida la forma y traduce la respuesta.
const uuid = z.string().uuid();
const SOURCES = [
  "manual",
  "excel_import",
  "measured",
  "supplier",
  "calculated",
  "estimated",
  "verified",
] as const;
const source = z.enum(SOURCES);

function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

// Las funciones del catálogo devuelven un id o nada: si no hay error, salió bien.
function done(error: { message?: string; code?: string } | null, message: string): ActionState {
  return error ? toActionState(null, error) : { status: "ok", message };
}

const decimal = (value: string) => Number(value.replace(",", "."));

function ingredientId(formData: FormData) {
  return uuid.safeParse(formData.get("ingredientId"));
}

export async function createIngredientAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.ingredient.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const categoryId = uuid.safeParse(fields.data.category_id);
  if (!categoryId.success)
    return { status: "bad", fieldErrors: { category_id: "Elegí la categoría." } };
  const supabase = await createClient();
  // El grupo es el de la categoría elegida (la base vuelve a controlar que coincidan).
  const { data: category } = await supabase
    .schema("catalog")
    .from("ingredient_categories")
    .select("group_id")
    .eq("id", categoryId.data)
    .maybeSingle();
  if (!category) return { status: "bad", fieldErrors: { category_id: "Elegí la categoría." } };
  const { data, error } = await supabase.schema("catalog").rpc("create_ingredient", {
    p_group_id: category.group_id,
    p_code: fields.data.code,
    p_name: fields.data.name,
    p_category_id: fields.data.category_id,
    p_recipe_unit: fields.data.recipe_unit,
    p_details: {},
    p_reason: fields.data.reason,
  });
  if (error) return toActionState(null, error);
  revalidatePath("/materias-primas");
  redirect(`/materias-primas/${data}`);
}

export async function updateIngredientAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.ingredientEdit.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("update_ingredient", {
    p_id: id.data,
    p_changes: {
      name: fields.data.name,
      category_id: fields.data.category_id,
      notes: fields.data.notes ?? "",
    },
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return done(error, "Datos guardados.");
}

export async function setActiveAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  const active = formData.get("active");
  if (!id.success || (active !== "true" && active !== "false"))
    return { status: "bad", message: "Falta la materia prima." };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("set_ingredient_active", {
    p_id: id.data,
    p_active: active === "true",
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  revalidatePath("/materias-primas");
  return done(
    error,
    active === "true" ? "Se puede volver a usar." : "Desactivada. No se borró nada.",
  );
}

export async function setAliasesAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.aliases.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  // Uno por línea o separados por coma.
  const aliases = (fields.data.aliases ?? "")
    .split(/[\n,]/)
    .map((a) => a.trim())
    .filter(Boolean);
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("set_aliases", {
    p_ingredient_id: id.data,
    p_aliases: aliases,
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return done(error, "Otros nombres guardados.");
}

export async function setConversionAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.conversion.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  const parsedSource = source.safeParse(fields.data.source);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  if (!parsedSource.success)
    return { status: "bad", fieldErrors: { source: "Elegí de dónde sale el dato." } };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("set_unit_conversion", {
    p_ingredient_id: id.data,
    p_kind: fields.data.kind satisfies ConversionKind,
    p_factor: decimal(fields.data.factor),
    p_source: parsedSource.data satisfies DataSource,
    p_measured_on: fields.data.measured_on,
    p_measured_by: fields.data.measured_by ?? "",
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return done(error, "Conversión guardada.");
}

export async function setAllergenAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.allergen.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  const allergenId = uuid.safeParse(fields.data.allergen_id);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  if (!allergenId.success)
    return { status: "bad", fieldErrors: { allergen_id: "Elegí el alérgeno." } };
  const status = fields.data.status === "" ? null : (fields.data.status satisfies AllergenStatus);
  const parsedSource = source.safeParse(fields.data.source);
  if (status && !parsedSource.success)
    return { status: "bad", fieldErrors: { source: "Elegí de dónde sale el dato." } };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("set_allergen_status", {
    p_ingredient_id: id.data,
    p_allergen_id: allergenId.data,
    // "Sin dato" vuelve a dejar la fila vacía: la función acepta null en estado y fuente.
    p_status: status as AllergenStatus,
    p_source: (status ? parsedSource.data : null) as DataSource,
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return done(error, "Alérgeno guardado.");
}

export async function createProductAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.product.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  const supplierId = fields.data.supplier_id ? uuid.safeParse(fields.data.supplier_id) : null;
  if (supplierId && !supplierId.success)
    return { status: "bad", fieldErrors: { supplier_id: "Elegí un proveedor de la lista." } };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("create_purchase_product", {
    p_ingredient_id: id.data,
    p_code: fields.data.code,
    p_description: fields.data.description,
    p_package_unit: fields.data.package_unit,
    p_units_per_package: Number(fields.data.units_per_package),
    p_content_per_unit: decimal(fields.data.content_per_unit),
    p_content_unit: fields.data.content_unit,
    p_details: {
      ...(supplierId ? { supplier_id: supplierId.data } : {}),
      ...(fields.data.brand_name ? { brand_name: fields.data.brand_name } : {}),
    },
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return done(error, "Producto de compra agregado.");
}

export async function createSupplierAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.supplier.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const groupId = uuid.safeParse(formData.get("groupId"));
  const back = ingredientId(formData);
  if (!groupId.success) return { status: "bad", message: "Falta el grupo." };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("create_supplier", {
    p_group_id: groupId.data,
    p_code: fields.data.code,
    p_name: fields.data.name,
    p_details: fields.data.tax_id ? { tax_id: fields.data.tax_id } : {},
    p_reason: fields.data.reason,
  });
  if (back.success) revalidatePath(`/materias-primas/${back.data}`);
  return done(error, "Proveedor creado. Ya lo podés elegir en el producto.");
}
