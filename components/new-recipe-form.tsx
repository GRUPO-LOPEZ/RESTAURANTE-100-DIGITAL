import { createRecipeAction } from "@/app/recetas/actions";
import { ActionForm } from "@/components/action-form";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import {
  RECIPE_TYPE_LABELS,
  getDraftScopes,
  getRecipeCategories,
  type RecipeType,
} from "@/lib/recipes";

// El alta de una receta (sección 13): crea el borrador y lleva a su ficha. La usan la página /recetas/nueva y
// el modal de la lista (ADR-0036), así son siempre el mismo formulario.
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
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id="rec-alta-codigo"
          label="Código"
          hint="No cambia nunca. Por ejemplo, REC-0001."
          name="code"
          required
          maxLength={30}
          autoCapitalize="characters"
        />
        <FormInput id="rec-alta-nombre" label="Nombre" name="name" required maxLength={120} />
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormSelect id="rec-alta-tipo" label="Tipo" name="type" required defaultValue="">
          <option value="" disabled>
            Elegí el tipo
          </option>
          {(Object.keys(RECIPE_TYPE_LABELS) as RecipeType[]).map((t) => (
            <option key={t} value={t}>
              {RECIPE_TYPE_LABELS[t]}
            </option>
          ))}
        </FormSelect>
        <FormSelect id="rec-alta-categoria" label="Categoría" name="category_id" defaultValue="">
          <option value="">Sin categoría</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </FormSelect>
      </div>
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
