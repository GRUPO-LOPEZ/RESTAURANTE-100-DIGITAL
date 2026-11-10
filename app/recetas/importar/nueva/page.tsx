import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { ImportUpload } from "@/components/import-upload";
import { Card, CardDescription } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import { getImportBrands } from "@/lib/imports/jobs";
import { requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

// Leer un Excel grande lleva su tiempo: la acción de servidor de esta pantalla tiene hasta 60 s.
export const maxDuration = 60;

export default function NuevaImportacionPage() {
  return (
    <AppShell
      title="Importar recetario"
      description="Subís el Excel, revisás lo que se va a crear y recién después se confirma."
    >
      <Suspense fallback={<Loading />}>
        <NewImport />
      </Suspense>
    </AppShell>
  );
}

async function NewImport() {
  await requireMenu("importsRun");
  const brands = await getImportBrands();
  return (
    <>
      <BackLink href="/recetas/importar">Volver a importaciones</BackLink>
      <Card className="flex flex-col gap-4">
        <CardDescription>
          Nada se crea al subir: primero ves una vista previa con lo que se crea, lo que ya existe y
          lo que tiene errores. Las materias primas nuevas las confirma Compras y las recetas, la
          cocina.
        </CardDescription>
        {brands.length === 0 ? (
          <EmptyState title="No tenés marcas donde importar.">
            Pedile a quien administra los permisos que te habilite.
          </EmptyState>
        ) : (
          <ImportUpload brands={brands} />
        )}
      </Card>
    </>
  );
}
