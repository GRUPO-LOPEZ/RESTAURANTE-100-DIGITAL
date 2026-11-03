import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import {
  createAreaAction,
  renameAreaAction,
  setRestaurantLegalEntityAction,
  updateRestaurantAction,
} from "@/app/configuracion/actions";
import { RestaurantFields } from "@/app/configuracion/restaurant-fields";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { formatDate, uuidOrUndefined } from "@/lib/data";
import {
  RESTAURANT_STATUS_LABELS,
  SITE_TYPE_LABELS,
  VAT_CONDITION_LABELS,
  formatTaxId,
  getBrand,
  getLegalEntities,
  getOrgPermissions,
  getRestaurant,
} from "@/lib/org";
import { requireMenu } from "@/lib/auth/session";

// Un local (ADR-0031): sus datos, su razón social y sus áreas. Los datos los cambia quien administra el
// local; el tipo y el estado, quien administra la marca; la razón social, quien administra todo el grupo.
export default function LocalPage({ params }: PageProps<"/configuracion/locales/[id]">) {
  return (
    <AppShell title="Local" description="Sus datos, su razón social y sus áreas.">
      <Suspense fallback={<Loading />}>
        <Restaurant params={params} />
      </Suspense>
    </AppShell>
  );
}

function Reason({ id, label = "Motivo" }: { id: string; label?: string }) {
  return (
    <FormTextarea
      id={id}
      label={label}
      hint="Queda en el historial."
      name="reason"
      required
      maxLength={500}
    />
  );
}

async function Restaurant({
  params,
}: {
  params: PageProps<"/configuracion/locales/[id]">["params"];
}) {
  await requireMenu("orgManage");
  const id = uuidOrUndefined((await params).id);
  if (!id) notFound();
  const [restaurant, permissions, legalEntities] = await Promise.all([
    getRestaurant(id),
    getOrgPermissions(),
    getLegalEntities(),
  ]);
  if (!restaurant) notFound();
  const brand = await getBrand(restaurant.brandId);
  const groupManager = permissions.groups.includes(restaurant.groupId);
  const brandManager = permissions.brands.includes(restaurant.brandId);
  const manager = permissions.restaurants.includes(restaurant.id);
  const entity = legalEntities.find((l) => l.id === restaurant.legalEntityId);

  return (
    <>
      <Link
        href={brand ? `/configuracion/marcas/${brand.id}` : "/configuracion/marcas"}
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        {brand ? `Volver a ${brand.name}` : "Volver a marcas"}
      </Link>

      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle>{restaurant.name}</CardTitle>
          <Badge status={restaurant.status === "active" ? "ok" : "neutral"}>
            {RESTAURANT_STATUS_LABELS[restaurant.status]}
          </Badge>
        </div>
        <CardDescription>
          {[brand?.name, restaurant.code, SITE_TYPE_LABELS[restaurant.siteType]]
            .filter(Boolean)
            .join(" · ")}
        </CardDescription>
        <dl className="grid gap-2 text-base sm:grid-cols-2">
          {[
            ["Dirección", restaurant.address],
            ["Localidad", restaurant.locality],
            ["Teléfono", restaurant.phone],
            ["Apertura", restaurant.openedOn ? formatDate(restaurant.openedOn) : null],
          ].map(([label, value]) => (
            <div key={label} className="flex flex-col">
              <dt className="text-sm text-ink-muted">{label}</dt>
              <dd className="text-ink tabular-nums">{value || "Sin cargar"}</dd>
            </div>
          ))}
        </dl>
        {manager ? (
          <Disclosure summary="Editar los datos del local">
            <ActionForm
              action={updateRestaurantAction}
              schema="restaurantEdit"
              submitLabel="Guardar local"
            >
              <input type="hidden" name="restaurantId" value={restaurant.id} />
              <RestaurantFields
                prefix="local-editar"
                restaurant={restaurant}
                showSiteType={brandManager}
                showStatus={brandManager}
              />
            </ActionForm>
          </Disclosure>
        ) : null}
      </Card>

      <Card className="flex flex-col gap-4">
        <CardTitle>Razón social</CardTitle>
        {entity ? (
          <p className="text-base text-ink">
            {entity.name} · <span className="tabular-nums">{formatTaxId(entity.taxId)}</span> ·{" "}
            {VAT_CONDITION_LABELS[entity.vatCondition]}
          </p>
        ) : restaurant.legalEntityId ? (
          // Tiene una, pero esta persona no ve las razones sociales: nunca decir que no tiene.
          <p className="text-base text-ink">Tiene su razón social cargada.</p>
        ) : (
          <Notice status="warn">
            Este local todavía no tiene razón social: su costo sin IVA queda incompleto.
            {groupManager ? null : " La elige quien administra el grupo."}
          </Notice>
        )}
        {groupManager ? (
          legalEntities.length === 0 ? (
            <p className="text-base text-ink">
              Primero cargá la razón social en{" "}
              <Link
                href="/configuracion/razones-sociales"
                className="text-primary underline underline-offset-4"
              >
                Razones sociales
              </Link>
              .
            </p>
          ) : (
            <Disclosure summary={entity ? "Cambiar la razón social" : "Elegir la razón social"}>
              <ActionForm
                action={setRestaurantLegalEntityAction}
                schema="restaurantLegalEntity"
                submitLabel="Guardar razón social"
              >
                <input type="hidden" name="restaurantId" value={restaurant.id} />
                <FormSelect
                  id="local-razon-social"
                  label="Razón social"
                  hint="Decide si el costo de este local va con o sin IVA."
                  name="legal_entity_id"
                  required
                  defaultValue={restaurant.legalEntityId ?? ""}
                >
                  <option value="" disabled>
                    Elegí la razón social
                  </option>
                  {legalEntities.map((l) => (
                    <option key={l.id} value={l.id}>
                      {l.name} · {formatTaxId(l.taxId)} · {VAT_CONDITION_LABELS[l.vatCondition]}
                    </option>
                  ))}
                </FormSelect>
                <Reason id="local-razon-social-motivo" />
              </ActionForm>
            </Disclosure>
          )
        ) : null}
      </Card>

      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          Áreas: {restaurant.areas.length.toLocaleString("es-AR")}
        </CardTitle>
        <CardDescription>
          Salón, Cocina, Barra… Sirven para ubicar a cada persona en el local.
        </CardDescription>
        {restaurant.areas.length === 0 ? (
          <EmptyState title="Este local todavía no tiene áreas.">
            {manager ? "Creá la primera con «Nueva área»." : null}
          </EmptyState>
        ) : (
          <ul aria-label="Áreas" className="flex flex-col gap-2">
            {restaurant.areas.map((a) => (
              <li key={a.id} className="flex flex-col gap-2 rounded-sm border border-line p-3">
                <span className="font-medium text-ink">{a.name}</span>
                {manager ? (
                  <Disclosure summary={`Cambiar el nombre de «${a.name}»`}>
                    <ActionForm
                      action={renameAreaAction}
                      schema="area"
                      submitLabel="Cambiar nombre"
                    >
                      <input type="hidden" name="areaId" value={a.id} />
                      <input type="hidden" name="restaurantId" value={restaurant.id} />
                      <FormInput
                        id={`area-nombre-${a.id}`}
                        label="Nombre nuevo"
                        name="name"
                        required
                        maxLength={120}
                        defaultValue={a.name}
                      />
                      <Reason id={`area-motivo-${a.id}`} label="Motivo del cambio de nombre" />
                    </ActionForm>
                  </Disclosure>
                ) : null}
              </li>
            ))}
          </ul>
        )}
        {manager ? (
          <Disclosure summary="Nueva área">
            <ActionForm
              action={createAreaAction}
              schema="area"
              submitLabel="Crear área"
              pendingLabel="Creando…"
            >
              <input type="hidden" name="restaurantId" value={restaurant.id} />
              <FormInput
                id="area-nueva-nombre"
                label="Nombre"
                name="name"
                required
                maxLength={120}
              />
              <Reason id="area-nueva-motivo" />
            </ActionForm>
          </Disclosure>
        ) : null}
      </Card>
    </>
  );
}
