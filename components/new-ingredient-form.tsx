import Link from "next/link";

import { createIngredientAction } from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { Card, CardDescription } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { getCategories } from "@/lib/catalog";

// El alta de una materia prima: la usan la página /materias-primas/nueva y el modal de la lista (ADR-0036), así son
// siempre el mismo formulario. Sin categorías todavía, manda a crearlas. En el modal va sin tarjeta (el modal ya
// es un panel) y en una sola columna (el modal es angosto aunque la ventana sea ancha).
export async function NewIngredientForm({ inModal = false }: { inModal?: boolean }) {
  const categories = await getCategories();
  const Frame = inModal ? "div" : Card;
  const columns = inModal ? "grid gap-4" : "grid gap-4 sm:grid-cols-2";
  return (
    <>
      {categories.length === 0 ? (
        <Frame className="flex flex-col gap-4">
          <CardDescription>
            Todavía no hay categorías, y cada materia prima va en una. Crealas primero.
          </CardDescription>
          <Link
            href="/materias-primas/configuracion"
            className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
          >
            Ir a la configuración del catálogo
          </Link>
        </Frame>
      ) : (
        <Frame className="flex flex-col gap-4">
          <CardDescription>
            El nombre va sin marca: «Mozzarella», no la de un proveedor. La marca va en el producto
            de compra.
          </CardDescription>
          <ActionForm
            action={createIngredientAction}
            schema="ingredient"
            submitLabel="Crear materia prima"
            pendingLabel="Creando…"
          >
            <div className={columns}>
              <FormInput
                id="mp-alta-codigo"
                label="Código"
                hint="No cambia nunca. Por ejemplo, ING-0051."
                name="code"
                required
                maxLength={30}
                autoCapitalize="characters"
              />
              <FormInput id="mp-alta-nombre" label="Nombre" name="name" required maxLength={120} />
            </div>
            <div className={columns}>
              <FormSelect
                id="mp-alta-categoria"
                label="Categoría"
                name="category_id"
                required
                defaultValue=""
              >
                <option value="" disabled>
                  Elegí la categoría
                </option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.label}
                  </option>
                ))}
              </FormSelect>
              <FormSelect
                id="mp-alta-unidad"
                label="Se usa en recetas en"
                hint="Las recetas siempre calculan en g, ml o unidades."
                name="recipe_unit"
                required
                defaultValue=""
              >
                <option value="" disabled>
                  Elegí la unidad
                </option>
                <option value="g">Gramos (g)</option>
                <option value="ml">Mililitros (ml)</option>
                <option value="unit">Unidades</option>
              </FormSelect>
            </div>
            <FormTextarea
              id="mp-alta-motivo"
              label="Motivo"
              hint="Queda en el historial."
              name="reason"
              required
              maxLength={500}
            />
          </ActionForm>
        </Frame>
      )}
    </>
  );
}
