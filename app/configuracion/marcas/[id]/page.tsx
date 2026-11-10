import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { createRestaurantAction, updateBrandAction } from "@/app/configuracion/actions";
import { RestaurantFields } from "@/app/configuracion/restaurant-fields";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { uuidOrUndefined } from "@/lib/data";
import {
  BRAND_STATUS_LABELS,
  RESTAURANT_STATUS_LABELS,
  SITE_TYPE_LABELS,
  getBrand,
  getLegalEntities,
  getOrgPermissions,
  getRestaurants,
  type UnitStatus,
} from "@/lib/org";
import { requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

// Una marca (ADR-0031): sus datos y sus locales. El nombre lo cambia quien administra la marca; el
// código y el estado, quien administra todo el grupo. Un local nuevo lo crea quien administra la marca.
export default function MarcaPage({ params }: PageProps<"/configuracion/marcas/[id]">) {
  return (
    <AppShell title="Marca" description="Sus datos y sus locales.">
      <Suspense fallback={<Loading />}>
        <Brand params={params} />
      </Suspense>
    </AppShell>
  );
}

async function Brand({ params }: { params: PageProps<"/configuracion/marcas/[id]">["params"] }) {
  await requireMenu("orgManage");
  const id = uuidOrUndefined((await params).id);
  if (!id) notFound();
  const [brand, restaurants, permissions] = await Promise.all([
    getBrand(id),
    getRestaurants(id),
    getOrgPermissions(),
  ]);
  if (!brand) notFound();
  const groupManager = permissions.groups.includes(brand.groupId);
  const brandManager = permissions.brands.includes(brand.id);
  const legalEntities = groupManager ? await getLegalEntities() : undefined;

  return (
    <>
      <BackLink href="/configuracion/marcas">Volver a marcas</BackLink>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle>{brand.name}</CardTitle>
          <Badge status={brand.status === "active" ? "ok" : "neutral"}>
            {BRAND_STATUS_LABELS[brand.status]}
          </Badge>
        </div>
        <CardDescription>Código {brand.code}</CardDescription>
        {brandManager ? (
          <Disclosure summary="Editar la marca">
            <ActionForm action={updateBrandAction} schema="brandEdit" submitLabel="Guardar marca">
              <input type="hidden" name="brandId" value={brand.id} />
              <div className="grid gap-4 sm:grid-cols-2">
                <FormInput
                  id="marca-editar-nombre"
                  label="Nombre"
                  name="name"
                  required
                  maxLength={120}
                  defaultValue={brand.name}
                />
                {groupManager ? (
                  <FormInput
                    id="marca-editar-codigo"
                    label="Código"
                    name="code"
                    required
                    maxLength={20}
                    autoCapitalize="characters"
                    autoComplete="off"
                    spellCheck={false}
                    defaultValue={brand.code}
                  />
                ) : null}
              </div>
              {groupManager ? (
                <FormSelect
                  id="marca-editar-estado"
                  label="Estado"
                  hint="Una marca inactiva no se borra: su historia se conserva."
                  name="status"
                  defaultValue={brand.status}
                >
                  {(Object.keys(BRAND_STATUS_LABELS) as UnitStatus[]).map((s) => (
                    <option key={s} value={s}>
                      {BRAND_STATUS_LABELS[s]}
                    </option>
                  ))}
                </FormSelect>
              ) : null}
              <FormTextarea
                id="marca-editar-motivo"
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

      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {restaurants.length === 1 ? "1 local" : `${restaurants.length} locales`}
        </CardTitle>
        {restaurants.length === 0 ? (
          <EmptyState title="Esta marca todavía no tiene locales.">
            {brandManager ? "Creá el primero con «Nuevo local»." : null}
          </EmptyState>
        ) : (
          <ul aria-label="Locales" className="flex flex-col divide-y divide-line">
            {restaurants.map((r) => (
              <li key={r.id} className="flex flex-wrap items-center gap-2 py-3">
                <div className="flex min-w-0 flex-1 flex-col gap-1">
                  <Link
                    href={`/configuracion/locales/${r.id}`}
                    className="inline-flex min-h-touch items-center text-base font-medium text-primary underline-offset-4 hover:underline"
                  >
                    {r.name}
                  </Link>
                  <span className="text-sm text-ink-muted">
                    {[r.code, SITE_TYPE_LABELS[r.siteType]].filter(Boolean).join(" · ")}
                  </span>
                </div>
                {r.legalEntityId ? null : <Badge status="warn">Sin razón social</Badge>}
                <Badge status={r.status === "active" ? "ok" : "neutral"}>
                  {RESTAURANT_STATUS_LABELS[r.status]}
                </Badge>
              </li>
            ))}
          </ul>
        )}
        {brandManager ? (
          <Disclosure summary="Nuevo local">
            <ActionForm
              action={createRestaurantAction}
              schema="restaurant"
              submitLabel="Crear local"
              pendingLabel="Creando…"
            >
              <input type="hidden" name="brandId" value={brand.id} />
              <RestaurantFields
                prefix="local-nuevo"
                showSiteType
                showStatus={false}
                legalEntities={legalEntities}
              />
            </ActionForm>
          </Disclosure>
        ) : null}
      </Card>
    </>
  );
}
