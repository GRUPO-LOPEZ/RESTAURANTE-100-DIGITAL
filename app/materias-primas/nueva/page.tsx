import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { NewIngredientForm } from "@/components/new-ingredient-form";
import { requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

export default function NuevaMateriaPrimaPage() {
  return (
    <AppShell
      title="Nueva materia prima"
      description="Se carga una sola vez para todo el grupo. Después le agregás cómo se compra, sus conversiones y alérgenos."
    >
      <Suspense fallback={<Loading />}>
        <NewIngredient />
      </Suspense>
    </AppShell>
  );
}

async function NewIngredient() {
  await requireMenu("catalogManage");
  return (
    <>
      <BackLink href="/materias-primas">Volver a materias primas</BackLink>
      <div className="max-w-3xl">
        <NewIngredientForm />
      </div>
    </>
  );
}
