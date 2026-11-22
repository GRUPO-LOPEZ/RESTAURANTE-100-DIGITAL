import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { NewPlaceForm } from "@/components/new-place-form";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { getOrgPermissions } from "@/lib/org";
import { getStructurePanel } from "@/lib/org-panel";

// Alta de un local sin JavaScript (con JavaScript, el Panel la abre en un modal corto; ADR-0061).
export default function NuevoLocalPage() {
  return (
    <AppShell
      title="Nuevo local"
      back={
        <BackLink href="/configuracion" label="Volver al Panel de control">
          Panel de control
        </BackLink>
      }
    >
      <Suspense fallback={<Loading />}>
        <NewPlace />
      </Suspense>
    </AppShell>
  );
}

async function NewPlace() {
  await requireMenu("panel");
  const [menus, panel, perms] = await Promise.all([
    getMenus(),
    getStructurePanel(),
    getOrgPermissions(),
  ]);
  const brands = panel.brands.filter(
    (b) =>
      b.status === "active" && (perms.groups.includes(b.groupId) || perms.brands.includes(b.id)),
  );
  if (!menus.orgManage || brands.length === 0)
    return <EmptyState title="No tenés marcas donde crear locales." />;
  return (
    <Card className="max-w-xl">
      <NewPlaceForm brands={brands.map((b) => ({ id: b.id, name: b.name }))} />
    </Card>
  );
}
