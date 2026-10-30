import Link from "next/link";
import { Suspense } from "react";

import { createRecipeAction } from "@/app/recetas/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Card, CardDescription } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import {
  RECIPE_TYPE_LABELS,
  getDraftScopes,
  getRecipeCategories,
  type RecipeType,
} from "@/lib/recipes";
import { requireMenu } from "@/lib/auth/session";

export default function NuevaRecetaPage() {
  return (
    <AppShell
      title="Nueva receta"
      description="Primero sus datos; después cargás los componentes, los pasos y el rendimiento en el borrador."
    >
      <Suspense fallback={<Loading />}>
        <NewRecipeForm />
      </Suspense>
    </AppShell>
  );
}

async function NewRecipeForm() {
  await requireMenu("recipesDraft");
  const [scopes, categories] = await Promise.all([getDraftScopes(), getRecipeCategories()]);
  return (
    <>
      <Link
        href="/recetas"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a recetas
      </Link>
      <Card className="flex flex-col gap-4">
        <CardDescription>
          Una receta se carga una sola vez: la maestra del grupo o la de una marca se asignan a los
          locales que la usan, sin copiarla.
        </CardDescription>
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
            <FormSelect
              id="rec-alta-categoria"
              label="Categoría"
              name="category_id"
              defaultValue=""
            >
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
      </Card>
    </>
  );
}
