"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import type { AllergenStatus, ConversionKind, DataSource } from "@/lib/catalog";
import { fieldErrors, formValues, isChecked, schemas } from "@/lib/forms/schemas";
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

// Rendimientos (etapa 2.1 B). Un ensayo nunca cambia el estándar: el estándar se propone y lo
// aprueba un Chef de todo el grupo (ADR-0021).
const grams = (value: string | undefined) => (value ? decimal(value) : undefined);

export async function recordYieldTestAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.yieldTest.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  const processId = uuid.safeParse(fields.data.process_id);
  const restaurantId = uuid.safeParse(fields.data.restaurant_id);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  if (!processId.success)
    return { status: "bad", fieldErrors: { process_id: "Elegí el proceso." } };
  if (!restaurantId.success)
    return { status: "bad", fieldErrors: { restaurant_id: "Elegí el local donde se midió." } };
  const measures = {
    gross_weight: grams(fields.data.gross_weight),
    clean_weight: grams(fields.data.clean_weight),
    before_cooking_weight: grams(fields.data.before_cooking_weight),
    after_cooking_weight: grams(fields.data.after_cooking_weight),
  };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("record_yield_test", {
    p_ingredient_id: id.data,
    p_process_id: processId.data,
    p_restaurant_id: restaurantId.data,
    p_tested_on: fields.data.tested_on,
    p_measures: Object.fromEntries(Object.entries(measures).filter(([, v]) => v !== undefined)),
    p_details: {
      samples: Number(fields.data.samples),
      ...(fields.data.cut ? { cut: fields.data.cut } : {}),
      ...(fields.data.responsible ? { responsible: fields.data.responsible } : {}),
    },
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return done(error, "Ensayo registrado. El estándar no cambia: si hace falta, proponé uno nuevo.");
}

export async function proposeYieldAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.yieldProposal.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  const processId = uuid.safeParse(fields.data.process_id);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  if (!processId.success)
    return { status: "bad", fieldErrors: { process_id: "Elegí el proceso." } };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("propose_yield_standard", {
    p_ingredient_id: id.data,
    p_process_id: processId.data,
    p_cut: fields.data.cut ?? "",
    // La limpieza se escribe en %; la base la guarda entre 0 y 1, con 4 decimales.
    p_cleaning_yield: Math.round(decimal(fields.data.cleaning_percent) * 100) / 10000,
    p_cooking_factor: decimal(fields.data.cooking_factor),
    p_method: fields.data.method ?? "",
    p_declared_no_loss: isChecked(fields.data.declared_no_loss),
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return error
    ? toActionState(null, error)
    : {
        status: "info",
        message: "Queda pendiente: lo tiene que aprobar un Chef de todo el grupo, distinto de vos.",
      };
}

// Mermas en % (ADR-0040): la base propone, juntas, la limpieza y el descongelado como estándares (catalog.propose_waste);
// no cambian el costo hasta que las apruebe un Chef de todo el grupo.
export async function proposeWasteAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.waste.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  const loss = (text: string | undefined) =>
    text ? Math.round(decimal(text) * 100) / 10000 : undefined;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("catalog").rpc("propose_waste", {
    p_ingredient_id: id.data,
    p_cleaning_loss: loss(fields.data.cleaning_loss),
    p_thawing_loss: loss(fields.data.thawing_loss),
    p_declared_no_loss: isChecked(fields.data.declared_no_loss),
    p_method: fields.data.method ?? "",
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  if (error) return toActionState(null, error);
  const requests = Number((data as { requests?: number } | null)?.requests ?? 0);
  return {
    status: "info",
    message:
      requests === 1
        ? "Queda pendiente: la tiene que aprobar un Chef de todo el grupo, distinto de vos."
        : "Quedan pendientes: las tiene que aprobar un Chef de todo el grupo, distinto de vos.",
  };
}

// Una unidad nueva (ADR-0040). Las unidades valen para todo el sistema; la base pide catalog.manage en el grupo.
export async function createUnitAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.unit.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const group = uuid.safeParse(formData.get("groupId"));
  if (!group.success) return { status: "bad", message: "Falta el grupo." };
  const client = await createClient();
  const { error } = await client.schema("catalog").rpc("create_unit", {
    p_group_id: group.data,
    p_code: fields.data.code,
    p_long_name: fields.data.long_name,
    p_abbreviation: fields.data.abbreviation,
    p_dimension: fields.data.dimension,
    ...(fields.data.factor ? { p_factor: decimal(fields.data.factor) } : {}),
    p_reason: fields.data.reason,
  });
  revalidatePath("/materias-primas/configuracion");
  return done(error, `Unidad «${fields.data.long_name}» creada.`);
}

// Dar de baja una unidad que nada usó (ADR-0040): para corregir un error de carga. La base controla que no se use.
export async function archiveUnitAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const group = uuid.safeParse(formData.get("groupId"));
  const unit = uuid.safeParse(formData.get("unitId"));
  if (!group.success || !unit.success) return { status: "bad", message: "Falta la unidad." };
  const client = await createClient();
  const { error } = await client.schema("catalog").rpc("archive_unit", {
    p_group_id: group.data,
    p_unit_id: unit.data,
    p_reason: fields.data.reason,
  });
  revalidatePath("/materias-primas/configuracion");
  return done(error, "Unidad dada de baja.");
}

// Se compra congelada (ADR-0040): cambia el costo de sus recetas (la base anota el recálculo).
export async function setThawingAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.thawing.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  const value = fields.data.requires_thawing === "true";
  const supabase = await createClient();
  const { data, error } = await supabase.schema("catalog").rpc("set_requires_thawing", {
    p_ingredient_id: id.data,
    p_value: value,
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  if (error) return toActionState(null, error);
  // Dejar de comprarla congelada baja el costo: lo aprueba un Chef de todo el grupo (decisión de Joaco, ADR-0040).
  const result = (data as { result?: string } | null)?.result;
  if (result === "pending_approval")
    return {
      status: "info",
      message:
        "Queda pendiente: dejar de comprarla congelada lo tiene que aprobar un Chef de todo el grupo.",
    };
  if (result === "unchanged") return { status: "ok", message: "No había nada que cambiar." };
  return {
    status: "ok",
    message: "Guardado: se compra congelada. Los costos se actualizan en un minuto.",
  };
}

// Proponer un precio (ADR-0029). La base controla prices.propose en el lugar elegido, calcula la
// variación y crea la solicitud: la aprueba el Controller y, si la variación supera el % del grupo,
// también Dirección General.
const PLACE =
  /^(group|brand|restaurant):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/;

export async function proposePriceAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.priceProposal.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = ingredientId(formData);
  const product = uuid.safeParse(fields.data.product_id);
  const place = PLACE.exec(fields.data.place);
  const supplier = fields.data.supplier_id ? uuid.safeParse(fields.data.supplier_id) : null;
  if (!id.success) return { status: "bad", message: "Falta la materia prima." };
  if (!product.success) return { status: "bad", fieldErrors: { product_id: "Elegí el producto." } };
  if (!place) return { status: "bad", fieldErrors: { place: "Elegí para quién vale." } };
  if (supplier && !supplier.success)
    return { status: "bad", fieldErrors: { supplier_id: "Elegí el proveedor." } };
  const [, scope, placeId] = place;
  const invoice = fields.data.document_type === "invoice";
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("propose_price", {
    p_purchase_product_id: product.data,
    p_scope_type: scope as string,
    // La función acepta lugares vacíos (según el alcance); el tipo generado no lo refleja.
    p_brand_id: (scope === "brand" ? placeId : null) as string,
    p_restaurant_id: (scope === "restaurant" ? placeId : null) as string,
    p_valid_from: fields.data.valid_from,
    p_package_price: decimal(fields.data.package_price),
    p_document_type: fields.data.document_type,
    p_vat_rate: (invoice ? Number(fields.data.vat_rate) : null) as number,
    p_price_includes_vat: invoice ? isChecked(fields.data.price_includes_vat) : true,
    p_discount_amount: fields.data.discount_amount ? decimal(fields.data.discount_amount) : 0,
    p_supplier_id: (supplier?.data ?? null) as string,
    p_source: fields.data.source,
    p_notes: fields.data.notes ?? "",
    p_reason: fields.data.reason,
  });
  revalidatePath(`/materias-primas/${id.data}`);
  return error
    ? toActionState(null, error)
    : {
        status: "info",
        message:
          "Precio propuesto. Queda pendiente: lo aprueba el Controller y, si cambia mucho, también Dirección General.",
      };
}

// Configuración del catálogo (ADR-0022). Categorías: catalog.manage para todo el grupo. Procesos:
// yields.approve para todo el grupo. La base controla el permiso y que no se dé de baja algo en uso.
function settingsDone(error: { message?: string; code?: string } | null, message: string) {
  revalidatePath("/materias-primas", "layout");
  return done(error, message);
}

export async function createCategoryAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  // Desde la configuración solo se crean subcategorías: los rubros se crean en Rubros (ADR-0038).
  const fields = schemas.subcategory.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const groupId = uuid.safeParse(formData.get("groupId"));
  if (!groupId.success) return { status: "bad", message: "Falta el grupo." };
  const parent = fields.data.parent_id ? uuid.safeParse(fields.data.parent_id) : null;
  if (parent && !parent.success)
    return { status: "bad", fieldErrors: { parent_id: "Elegí la categoría madre." } };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("create_category", {
    p_group_id: groupId.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
    ...(parent ? { p_parent_id: parent.data } : {}),
  });
  return settingsDone(error, "Subcategoría creada. Ya la podés elegir en las materias primas.");
}

export async function renameCategoryAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.rename.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("categoryId"));
  if (!id.success) return { status: "bad", message: "Falta la categoría." };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("rename_category", {
    p_id: id.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  return settingsDone(error, "Nombre cambiado.");
}

export async function archiveCategoryAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("categoryId"));
  if (!id.success) return { status: "bad", message: "Falta la categoría." };
  const supabase = await createClient();
  const { error } = await supabase
    .schema("catalog")
    .rpc("archive_category", { p_id: id.data, p_reason: fields.data.reason });
  if (error) return toActionState(null, error);
  // La categoría deja de aparecer, y con ella su formulario: el aviso va arriba de la pantalla.
  revalidatePath("/materias-primas", "layout");
  redirect("/materias-primas/configuracion?baja=categoria");
}

export async function createProcessAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.yieldProcess.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const groupId = uuid.safeParse(formData.get("groupId"));
  if (!groupId.success) return { status: "bad", message: "Falta el grupo." };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("create_yield_process", {
    p_group_id: groupId.data,
    p_code: fields.data.code,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  return settingsDone(error, "Proceso creado. Ya se puede usar en los rendimientos.");
}

export async function renameProcessAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.rename.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("processId"));
  if (!id.success) return { status: "bad", message: "Falta el proceso." };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("rename_yield_process", {
    p_id: id.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  return settingsDone(error, "Nombre cambiado.");
}

export async function archiveProcessAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("processId"));
  if (!id.success) return { status: "bad", message: "Falta el proceso." };
  const supabase = await createClient();
  const { error } = await supabase
    .schema("catalog")
    .rpc("archive_yield_process", { p_id: id.data, p_reason: fields.data.reason });
  if (error) return toActionState(null, error);
  revalidatePath("/materias-primas", "layout");
  redirect("/materias-primas/configuracion?baja=proceso");
}
