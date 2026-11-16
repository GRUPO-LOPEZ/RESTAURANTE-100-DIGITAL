import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { NewSupplierForm } from "@/components/new-supplier-form";
import { Card } from "@/components/ui/card";
import { requireMenu } from "@/lib/auth/session";

// Alta de proveedor sin JavaScript: el mismo formulario que el modal de la lista (ADR-0036).
export default function NuevoProveedorPage() {
  return (
    <AppShell
      title="Nuevo proveedor"
      description="Se carga una sola vez para todo el grupo. Después completás su ficha: días, canal, facturación y pago."
      back={
        <BackLink href="/proveedores" label="Volver a proveedores">
          Proveedores
        </BackLink>
      }
    >
      <Suspense fallback={<Loading />}>
        <NewSupplier />
      </Suspense>
    </AppShell>
  );
}

async function NewSupplier() {
  await requireMenu("suppliersManage");
  return (
    <>
      <Card className="max-w-3xl">
        <NewSupplierForm />
      </Card>
    </>
  );
}
