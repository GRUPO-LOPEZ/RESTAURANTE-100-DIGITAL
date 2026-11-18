import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { SupplierImport } from "@/components/supplier-import";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { first } from "@/lib/data";

// Importar proveedores desde planilla (ADR-0055), para la carga inicial. Pantalla de carga para la computadora: bajar la
// plantilla, subirla, ver qué pasa con cada fila y confirmar con un motivo. La ve quien administra proveedores.
export default function ImportarProveedoresPage({
  searchParams,
}: PageProps<"/proveedores/importar">) {
  return (
    <AppShell
      title="Importar proveedores"
      back={
        <BackLink href="/proveedores" label="Volver a proveedores">
          Proveedores
        </BackLink>
      }
      fill
    >
      <Suspense fallback={<Loading />}>
        <ImportSupplierScreen searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function ImportSupplierScreen({
  searchParams,
}: {
  searchParams: PageProps<"/proveedores/importar">["searchParams"];
}) {
  await requireMenu("suppliersManage");
  const raw = await searchParams;
  return (
    <>
      {first(raw.plantilla) === "error" ? (
        <Notice status="bad">No pudimos armar la plantilla. Probá de nuevo.</Notice>
      ) : null}
      <SupplierImport />
    </>
  );
}
