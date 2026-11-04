"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { parseAmount, perBaseLabel } from "@/lib/money";
import { getScenarioIngredients } from "@/lib/scenarios";
import { createClient } from "@/lib/supabase/server";

// Acciones de los escenarios de costo (ADR-0032). Cada una llama a una función de costing.* que
// controla el permiso, pide el motivo y deja la auditoría. Ninguna toca un costo oficial.
const uuid = z.string().uuid();

function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

type DbError = { message?: string; code?: string } | null;

function failed(error: DbError): ActionState {
  return toActionState(null, error ?? { message: "Sin respuesta" });
}

function saved(error: DbError, scenarioId: string, message: string): ActionState {
  if (error) return failed(error);
  revalidatePath(`/costos/escenarios/${scenarioId}`);
  return { status: "ok", message };
}

export async function createScenarioAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.scenario.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const place = uuid.safeParse(formData.get("restaurantId"));
  if (!place.success) return { status: "bad", message: "Elegí un local." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("create_scenario", {
    p_restaurant_id: place.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  if (error || typeof data !== "string") return failed(error);
  revalidatePath("/costos/escenarios");
  redirect(`/costos/escenarios/${data}`);
}

export async function archiveScenarioAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const scenario = uuid.safeParse(formData.get("scenarioId"));
  if (!scenario.success) return { status: "bad", message: "Falta el escenario." };
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("archive_scenario", {
    p_scenario_id: scenario.data,
    p_reason: fields.data.reason,
  });
  if (error) return failed(error);
  revalidatePath("/costos/escenarios");
  redirect(`/costos/escenarios/${scenario.data}?aviso=archivado`);
}

// La materia prima tiene que estar en la lista del escenario: la que la persona ve en ese local.
async function listedIngredient(scenarioId: string, ingredientId: string) {
  const ingredients = await getScenarioIngredients(scenarioId).catch(() => null);
  return ingredients?.find((i) => i.id === ingredientId);
}

// El precio se escribe por kg o por litro, como se ve en costos; la base lo guarda por unidad de uso.
export async function setScenarioPriceAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.scenarioPrice.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const scenario = uuid.safeParse(formData.get("scenarioId"));
  const amount = parseAmount(fields.data.amount);
  if (!scenario.success || amount === null)
    return { status: "bad", message: "Falta el escenario." };
  const supplier = uuid.optional().safeParse(fields.data.supplier || undefined);
  if (!supplier.success) return { status: "bad", message: "Elegí un proveedor de la lista." };
  const ingredient = await listedIngredient(scenario.data, fields.data.ingredient);
  if (!ingredient) return { status: "bad", message: "Elegí una materia prima de la lista." };
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("set_scenario_override", {
    p_scenario_id: scenario.data,
    p_kind: "price",
    p_reason: fields.data.reason,
    p_ingredient_id: ingredient.id,
    p_unit_cost: amount / perBaseLabel(ingredient.unit).factor,
    p_supplier_id: supplier.data,
  });
  return saved(error, scenario.data, "Precio simulado cargado.");
}

export async function setScenarioYieldAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.scenarioYield.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const scenario = uuid.safeParse(formData.get("scenarioId"));
  const cleaning = parseAmount(fields.data.cleaning);
  const cooking = parseAmount(fields.data.cooking);
  if (!scenario.success || cleaning === null || cooking === null)
    return { status: "bad", message: "Revisá los datos del cambio." };
  const ingredient = await listedIngredient(scenario.data, fields.data.ingredient);
  if (!ingredient) return { status: "bad", message: "Elegí una materia prima de la lista." };
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("set_scenario_override", {
    p_scenario_id: scenario.data,
    p_kind: "yield",
    p_reason: fields.data.reason,
    p_ingredient_id: ingredient.id,
    p_cleaning_yield: cleaning / 100,
    p_cooking_factor: cooking,
  });
  return saved(error, scenario.data, "Rendimiento simulado cargado.");
}

export async function setScenarioQuantityAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.scenarioQuantity.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const scenario = uuid.safeParse(formData.get("scenarioId"));
  const line = uuid.safeParse(fields.data.line);
  const quantity = parseAmount(fields.data.quantity);
  if (!scenario.success || !line.success || quantity === null)
    return { status: "bad", message: "Revisá los datos del cambio." };
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("set_scenario_override", {
    p_scenario_id: scenario.data,
    p_kind: "quantity",
    p_reason: fields.data.reason,
    p_recipe_component_id: line.data,
    p_quantity: quantity,
  });
  return saved(error, scenario.data, "Gramaje simulado cargado.");
}

// El cambio desaparece de la lista con su formulario: el aviso va arriba, en la dirección.
export async function removeScenarioChangeAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const scenario = uuid.safeParse(formData.get("scenarioId"));
  const change = uuid.safeParse(formData.get("changeId"));
  if (!scenario.success || !change.success) return { status: "bad", message: "Falta el cambio." };
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("remove_scenario_override", {
    p_override_id: change.data,
    p_reason: fields.data.reason,
  });
  if (error) return failed(error);
  revalidatePath(`/costos/escenarios/${scenario.data}`);
  redirect(`/costos/escenarios/${scenario.data}?aviso=quitado`);
}
