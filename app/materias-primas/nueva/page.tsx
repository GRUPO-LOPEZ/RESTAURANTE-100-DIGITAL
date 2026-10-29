import Link from "next/link";
import { Suspense } from "react";

import { createIngredientAction } from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Card, CardDescription } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { getCategories } from "@/lib/catalog";
import { requireMenu } from "@/lib/auth/session";

export default function NuevaMateriaPrimaPage() {
  return (
    <AppShell
      title="Nueva materia prima"
      description="Se carga una sola vez para todo el grupo. Después le agregás cómo se compra, sus conversiones y alérgenos."
    >
      <Suspense fallback={<Loading />}>
        <NewIngredientForm />
      </Suspense>
    </AppShell>
  );
}

async function NewIngredientForm() {
  await requireMenu("catalogManage");
  const categories = await getCategories();
  return (
    <>
      <Link
        href="/materias-primas"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a materias primas
      </Link>
      <Card className="flex flex-col gap-4">
        <CardDescription>
          El nombre va sin marca: «Mozzarella», no la de un proveedor. La marca va en el producto de
          compra.
        </CardDescription>
        <ActionForm
          action={createIngredientAction}
          schema="ingredient"
          submitLabel="Crear materia prima"
          pendingLabel="Creando…"
        >
          <div className="grid gap-4 sm:grid-cols-2">
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
          <div className="grid gap-4 sm:grid-cols-2">
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
      </Card>
    </>
  );
}
