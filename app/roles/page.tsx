import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { PermissionMatrix } from "@/components/permission-matrix";
import { EmptyState } from "@/components/ui/kpi";
import { getBrandsAndRestaurants, getPermissionMatrix } from "@/lib/data";
import { requireMenu } from "@/lib/auth/session";

// Roles y permisos (ADR-0039, pedido de Soy): la matriz completa de roles por permisos, con edición directa.
// Entra solo quien tiene permissions.manage (el menú lo pide, como antes). Las columnas de sus propios roles se
// ven sin poder cambiarse.
export default function RolesPage() {
  return (
    <AppShell
      title="Roles y permisos"
      description="Qué puede hacer cada rol. Los cambios se guardan juntos, con un motivo, y quedan en el historial."
    >
      <Suspense fallback={<Loading />}>
        <Matrix />
      </Suspense>
    </AppShell>
  );
}

async function Matrix() {
  await requireMenu("roles");
  const { groups } = await getBrandsAndRestaurants();
  const group = groups[0];
  if (!group) return <EmptyState title="No hay un grupo en tu alcance." />;
  const matrix = await getPermissionMatrix(group.id);
  if (!matrix) return <EmptyState title="No podés ver la matriz de este grupo." />;
  if (matrix.roles.length === 0) return <EmptyState title="No hay roles." />;
  return <PermissionMatrix groupId={group.id} matrix={matrix} />;
}
