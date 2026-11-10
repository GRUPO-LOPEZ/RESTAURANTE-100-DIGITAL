import Link from "next/link";
import { Suspense } from "react";

import { createBrandAction } from "@/app/configuracion/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { Badge } from "@/components/ui/badge";
import { Card, CardTitle } from "@/components/ui/card";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { BRAND_STATUS_LABELS, getBrands, getOrgPermissions } from "@/lib/org";
import { requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

// Marcas del grupo (ADR-0031): ¿qué marcas hay y cuántos locales tiene cada una? Una marca nueva la da
// de alta quien administra todo el grupo.
export default function MarcasPage() {
  return (
    <AppShell title="Marcas y locales" description="Cada marca con sus locales.">
      <Suspense fallback={<Loading />}>
        <Brands />
      </Suspense>
    </AppShell>
  );
}

async function Brands() {
  await requireMenu("orgManage");
  const [brands, permissions] = await Promise.all([getBrands(), getOrgPermissions()]);
  // Hoy hay un solo grupo. Si se suman otros, el alta va a tener que elegir el grupo.
  const groupId = permissions.groups[0];
  return (
    <>
      <BackLink href="/configuracion">Volver al panel de control</BackLink>
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {brands.length === 1 ? "1 marca" : `${brands.length} marcas`}
        </CardTitle>
        {brands.length === 0 ? (
          <EmptyState title="Todavía no hay marcas.">
            {groupId ? "Creá la primera con «Nueva marca»." : "Las crea quien administra el grupo."}
          </EmptyState>
        ) : (
          <ul aria-label="Marcas" className="flex flex-col divide-y divide-line">
            {brands.map((b) => (
              <li key={b.id} className="flex flex-wrap items-center gap-2 py-3">
                <div className="flex min-w-0 flex-1 flex-col gap-1">
                  <Link
                    href={`/configuracion/marcas/${b.id}`}
                    className="inline-flex min-h-touch items-center text-base font-medium text-primary underline-offset-4 hover:underline"
                  >
                    {b.name}
                  </Link>
                  <span className="text-sm text-ink-muted tabular-nums">
                    {b.code} · {b.restaurants === 1 ? "1 local" : `${b.restaurants} locales`}
                  </span>
                </div>
                <Badge status={b.status === "active" ? "ok" : "neutral"}>
                  {BRAND_STATUS_LABELS[b.status]}
                </Badge>
              </li>
            ))}
          </ul>
        )}
        {groupId ? (
          <Disclosure summary="Nueva marca">
            <ActionForm
              action={createBrandAction}
              schema="brand"
              submitLabel="Crear marca"
              pendingLabel="Creando…"
            >
              <input type="hidden" name="groupId" value={groupId} />
              <div className="grid gap-4 sm:grid-cols-2">
                <FormInput id="marca-nombre" label="Nombre" name="name" required maxLength={120} />
                <FormInput
                  id="marca-codigo"
                  label="Código"
                  hint="Corto y único, por ejemplo NONNOS. Aparece junto al nombre de cada local."
                  name="code"
                  required
                  maxLength={20}
                  autoCapitalize="characters"
                  autoComplete="off"
                  spellCheck={false}
                />
              </div>
              <FormTextarea
                id="marca-motivo"
                label="Motivo"
                hint="Queda en el historial."
                name="reason"
                required
                maxLength={500}
              />
            </ActionForm>
          </Disclosure>
        ) : null}
      </Card>
    </>
  );
}
