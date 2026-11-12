import { createRecipeAction } from "@/app/recetas/actions";
import { ActionForm } from "@/components/action-form";
import { RecipeTypeCategory } from "@/components/recipe-type-category";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { getDraftScopes, getRecipeCategories } from "@/lib/recipes";

// El alta de una receta (sección 13): crea el borrador y lleva a su ficha. La usan la página /recetas/nueva y
// el modal de la lista (ADR-0036), así son siempre el mismo formulario. Orden del pedido de Soy (ADR-0041):
// alcance, tipo, rubro, código (automático), nombre y motivo.
export async function NewRecipeForm() {
  const [scopes, categories] = await Promise.all([getDraftScopes(), getRecipeCategories()]);
  return (
    <ActionForm
      action={createRecipeAction}
      schema="recipe"
      submitLabel="Crear receta"
      pendingLabel="Creando…"
    >
      <FormSelect
        id="rec-alta-alcance"
        label="Alcance"
        hint="Dónde se usa la receta. No cambia después."
        name="scope"
        required
        defaultValue={scopes.length === 1 ? scopes[0]?.value : ""}
      >
        <option value="" disabled>
          Elegí dónde se usa
        </option>
        {scopes.map((s) => (
          <option key={s.value} value={s.value}>
            {s.label}
          </option>
        ))}
      </FormSelect>
      {/* Los rubros dados de baja no se ofrecen (ADR-0038). */}
      <RecipeTypeCategory
        categories={categories
          .filter((c) => c.isActive)
          .map((c) => ({ id: c.id, label: c.label, kind: c.kind }))}
      />
      <FormInput id="rec-alta-nombre" label="Nombre" name="name" required maxLength={120} />
      <FormTextarea
        id="rec-alta-motivo"
        label="Motivo"
        hint="Queda en el historial."
        name="reason"
        required
        maxLength={500}
      />
    </ActionForm>
  );
}
