import Link from "next/link";

import { createIngredientAction } from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { Card, CardDescription } from "@/components/ui/card";
import { NewIngredientFields } from "@/components/new-ingredient-fields";
import { FormTextarea } from "@/components/ui/form";
import { getCategories, getUnits } from "@/lib/catalog";

// El alta de una materia prima: la usan la página /materias-primas/nueva y el modal de la lista (ADR-0036), así son
// siempre el mismo formulario. Sin categorías todavía, manda a crearlas. En el modal va sin tarjeta (el modal ya
// es un panel) y en una sola columna (el modal es angosto aunque la ventana sea ancha).
export async function NewIngredientForm({ inModal = false }: { inModal?: boolean }) {
  const [categories, units] = await Promise.all([getCategories(), getUnits()]);
  const Frame = inModal ? "div" : Card;
  const columns = inModal ? "grid gap-4" : "grid gap-4 sm:grid-cols-2";
  return (
    <>
      {categories.length === 0 ? (
        <Frame className="flex flex-col gap-4">
          <CardDescription>
            Todavía no hay rubros, y cada materia prima va en uno. Crealos primero.
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
            {/* Los rubros dados de baja no se ofrecen (ADR-0038). Sin envases: no tienen unidad base. */}
            <NewIngredientFields
              columns={columns}
              categories={categories
                .filter((c) => c.isActive)
                .map((c) => ({ id: c.id, label: c.label }))}
              units={units.flatMap((u) =>
                u.dimension === "mass" || u.dimension === "volume" || u.dimension === "count"
                  ? [{ code: u.code, label: u.label, dimension: u.dimension }]
                  : [],
              )}
            />
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
