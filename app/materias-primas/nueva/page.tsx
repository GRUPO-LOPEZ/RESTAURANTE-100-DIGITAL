import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { NewIngredientForm } from "@/components/new-ingredient-form";
import { requireMenu } from "@/lib/auth/session";

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
      <Link
        href="/materias-primas"
        className="inline-flex min-h-touch items-center gap-1 self-start text-base text-primary underline-offset-4 hover:underline desk:min-h-control"
      >
        <ArrowLeft aria-hidden="true" className="size-4" />
        Volver a materias primas
      </Link>
      <div className="max-w-3xl">
        <NewIngredientForm />
      </div>
    </>
  );
}
