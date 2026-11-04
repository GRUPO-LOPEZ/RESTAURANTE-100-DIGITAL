import Link from "next/link";
import { Suspense } from "react";

import { createScenarioAction } from "@/app/costos/escenarios/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { FiltersPanel } from "@/components/filters-panel";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select } from "@/components/ui/field";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { pickCostPlace } from "@/lib/costs";
import { first, formatDate, getActiveRestaurantId } from "@/lib/data";
import { SCENARIO_LIST, getScenarioPlaces, getScenarios, type Scenario } from "@/lib/scenarios";

// Escenarios de costo (ADR-0032): ¿qué pasaría si cambia un precio, un rendimiento o un gramaje?
// Son simulaciones: guardan solo los cambios y nunca tocan lo oficial.
export default function EscenariosPage({ searchParams }: PageProps<"/costos/escenarios">) {
  return (
    <AppShell
      title="¿Qué pasaría si…?"
      description="Simulá un cambio de precio, proveedor, rendimiento o gramaje antes de decidir."
    >
      <Suspense fallback={<Loading />}>
        <Scenarios searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

function ScenarioList({ title, scenarios }: { title: string; scenarios: Scenario[] }) {
  return (
    <ul className="flex flex-col divide-y divide-line" aria-label={title}>
      {scenarios.map((s) => (
        <li key={s.id} className="flex flex-wrap items-center justify-between gap-x-4 py-2">
          <Link
            href={`/costos/escenarios/${s.id}`}
            className="inline-flex min-h-touch max-w-full min-w-0 items-center font-medium [overflow-wrap:anywhere] break-words text-primary underline-offset-4 hover:underline"
          >
            {s.name}
          </Link>
          <span className="text-sm text-ink-muted tabular-nums">
            Creado el {formatDate(s.createdAt)}
          </span>
        </li>
      ))}
    </ul>
  );
}

async function Scenarios({
  searchParams,
}: {
  searchParams: PageProps<"/costos/escenarios">["searchParams"];
}) {
  const session = await requireMenu("scenarios");
  const params = await searchParams;
  const [places, activeId] = await Promise.all([
    getScenarioPlaces(),
    getActiveRestaurantId(session.user_id),
  ]);
  if (places.length === 0) return <EmptyState title="No tenés locales donde simular costos." />;
  const place = pickCostPlace(places, first(params.local), activeId);

  const filters = (
    <FiltersPanel active={place ? [place.name] : []}>
      <form
        method="get"
        role="search"
        aria-label="Elegir local"
        className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
      >
        <Field id="escenarios-local" label="Local">
          <Select name="local" defaultValue={place?.id ?? ""}>
            {place ? null : <option value="">Elegí un local</option>}
            {places.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </Select>
        </Field>
        <Button type="submit">Ver</Button>
      </form>
    </FiltersPanel>
  );

  if (!place)
    return (
      <>
        {filters}
        <EmptyState title="Elegí un local para ver sus escenarios." />
      </>
    );

  const scenarios = await getScenarios(place.id);
  const active = scenarios.filter((s) => !s.archived);
  const archived = scenarios.filter((s) => s.archived);

  return (
    <>
      {filters}
      <Notice status="info">Es una simulación: no cambia ningún costo ni receta.</Notice>
      {scenarios.length === SCENARIO_LIST ? (
        <Notice status="warn">Se muestran los últimos {SCENARIO_LIST} escenarios.</Notice>
      ) : null}
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <CardTitle>{place.name}</CardTitle>
          <CardDescription>Cada escenario se calcula con los datos de hoy.</CardDescription>
          <Link
            href={`/costos?local=${place.id}`}
            className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline"
          >
            Volver a costos
          </Link>
        </div>
        {active.length === 0 ? (
          <EmptyState
            title={
              archived.length > 0
                ? "No hay escenarios activos."
                : "Este local todavía no tiene escenarios."
            }
          >
            Creá uno para ver qué pasaría con tus costos.
          </EmptyState>
        ) : (
          <ScenarioList title="Escenarios activos" scenarios={active} />
        )}
        <Disclosure summary="Nuevo escenario">
          <ActionForm
            action={createScenarioAction}
            schema="scenario"
            submitLabel="Crear escenario"
            pendingLabel="Creando…"
          >
            <input type="hidden" name="restaurantId" value={place.id} />
            <FormInput
              id="escenario-nombre"
              label="Nombre"
              hint="Por ejemplo: la mozzarella sube 20 %."
              name="name"
              required
              maxLength={120}
              autoComplete="off"
            />
            <FormTextarea
              id="escenario-motivo"
              label="Motivo"
              name="reason"
              required
              maxLength={500}
            />
          </ActionForm>
        </Disclosure>
        {archived.length > 0 ? (
          <div className="flex flex-col gap-2">
            <p className="flex items-center gap-2 text-base font-medium text-ink">
              Archivados <Badge status="neutral">{archived.length}</Badge>
            </p>
            <ScenarioList title="Escenarios archivados" scenarios={archived} />
          </div>
        ) : null}
      </Card>
    </>
  );
}
