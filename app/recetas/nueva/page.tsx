import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { NewRecipeForm } from "@/components/new-recipe-form";
import { Card, CardDescription } from "@/components/ui/card";
import { requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

export default function NuevaRecetaPage() {
  return (
    <AppShell
      title="Nueva receta"
      description="Primero sus datos; después cargás los componentes, los pasos y el rendimiento en el borrador."
    >
      <Suspense fallback={<Loading />}>
        <NewRecipe />
      </Suspense>
    </AppShell>
  );
}

async function NewRecipe() {
  await requireMenu("recipesDraft");
  return (
    <>
      <BackLink href="/recetas">Volver a recetas</BackLink>
      <Card className="flex max-w-3xl flex-col gap-4">
        <CardDescription>
          Una receta se carga una sola vez: la maestra del grupo o la de una marca se asignan a los
          locales que la usan, sin copiarla.
        </CardDescription>
        <NewRecipeForm />
      </Card>
    </>
  );
}
