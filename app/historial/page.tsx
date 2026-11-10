import { Suspense } from "react";
import { Download } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { HISTORY_COLUMNS } from "@/components/history-list";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { CursorPagination } from "@/components/ui/cursor-pagination";
import { DataTable } from "@/components/ui/data-table";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { EmptyState } from "@/components/ui/states";
import { FormNotice } from "@/components/form-notice";
import {
  MODULE_LABELS,
  first,
  formatDate,
  getActiveRestaurantId,
  getBrandsAndRestaurants,
  getHistory,
  getUser,
  getUsers,
  personName,
  uuidOrUndefined,
} from "@/lib/data";
import { dateParam, restaurantFilter } from "@/lib/filters";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { getMenus, requireMenu } from "@/lib/auth/session";

const PATH = "/historial";

// Historial inalterable (secciones 6 y 9; listado del rediseño, ADR-0036): quién, cuándo, qué cambió y por qué,
// en lenguaje simple, con búsqueda por fecha, persona, marca, módulo y registro, y exportación. El local es el
// de la barra de arriba; con «Todos mis locales», todo el alcance (decisión de Joaco, 2026-11-10). Solo lo de tu
// alcance, y sin costos si no tenés permiso para verlos.
export default function HistorialPage({ searchParams }: PageProps<"/historial">) {
  return (
    <AppShell
      title="¿Quién cambió qué?"
      description="Cada cambio queda registrado para siempre: nadie lo puede borrar ni modificar."
    >
      <Suspense fallback={<Loading />}>
        <History searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// La fecha "hasta" incluye todo ese día (hora de Buenos Aires).
function dayStart(value: string | undefined): string | undefined {
  return value ? `${value}T00:00:00-03:00` : undefined;
}
function dayEnd(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const next = new Date(`${value}T00:00:00-03:00`);
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString();
}

async function History({
  searchParams,
}: {
  searchParams: PageProps<"/historial">["searchParams"];
}) {
  const session = await requireMenu("audit");
  const raw = await searchParams;
  const params = plainParams(raw);
  const activeId = await getActiveRestaurantId(session.user_id);
  const local = restaurantFilter(first(raw.local), activeId);
  const beforeRaw = first(raw.antes);
  const moduleParam = first(raw.modulo);
  const from = dateParam(first(raw.desde));
  const to = dateParam(first(raw.hasta));
  const list = parseList(raw, []);
  const filter = {
    before: beforeRaw && /^[0-9]{1,18}$/.test(beforeRaw) ? Number(beforeRaw) : undefined,
    recordId: uuidOrUndefined(first(raw.registro)),
    from: dayStart(from),
    to: dayEnd(to),
    actorId: uuidOrUndefined(first(raw.persona)),
    // La marca solo filtra cuando no hay un local elegido.
    brandId: local.restaurantId ? undefined : uuidOrUndefined(first(raw.marca)),
    restaurantId: local.restaurantId,
    module: moduleParam && MODULE_LABELS[moduleParam] ? moduleParam : undefined,
  };
  const [fetched, places, firstPeople, chosen, menus] = await Promise.all([
    getHistory(filter, list.size + 1),
    getBrandsAndRestaurants(),
    getUsers({}, 100),
    filter.actorId ? getUser(filter.actorId) : Promise.resolve(null),
    getMenus(),
  ]);
  const rows = fetched.slice(0, list.size);
  const last = fetched.length > list.size ? rows[rows.length - 1] : undefined;
  // La lista muestra las primeras 100 personas; si la URL elige otra, también aparece.
  const people =
    chosen && !firstPeople.some((p) => p.id === chosen.id) ? [chosen, ...firstPeople] : firstPeople;
  const placeName = local.restaurantId
    ? (places.restaurants.find((r) => r.id === local.restaurantId)?.name ??
      "un local que no está en tu alcance")
    : undefined;

  // Los mismos filtros, para exportar (sin el cursor ni las filas).
  const exportQuery = new URLSearchParams();
  if (from) exportQuery.set("desde", from);
  if (to) exportQuery.set("hasta", to);
  if (filter.actorId) exportQuery.set("persona", filter.actorId);
  if (filter.brandId) exportQuery.set("marca", filter.brandId);
  exportQuery.set("local", filter.restaurantId ?? "todos");
  if (filter.module) exportQuery.set("modulo", filter.module);
  if (filter.recordId) exportQuery.set("registro", filter.recordId);

  const remove = (...keys: string[]) =>
    listHref(PATH, params, {
      ...Object.fromEntries(keys.map((k) => [k, undefined])),
      antes: undefined,
    });
  const active = [
    from ? { label: `Desde ${formatDate(from)}`, removeHref: remove("desde") } : null,
    to ? { label: `Hasta ${formatDate(to)}`, removeHref: remove("hasta") } : null,
    filter.actorId
      ? {
          label: `Persona: ${chosen ? personName(chosen) : "una persona"}`,
          removeHref: remove("persona"),
        }
      : null,
    filter.module
      ? { label: `Módulo: ${MODULE_LABELS[filter.module]}`, removeHref: remove("modulo") }
      : null,
    filter.brandId
      ? {
          label: `Marca: ${places.brands.find((b) => b.id === filter.brandId)?.name ?? ""}`,
          removeHref: remove("marca"),
        }
      : null,
    filter.recordId ? { label: "Un registro", removeHref: remove("registro") } : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);

  return (
    <>
      {first(raw.error) === "exportar" ? (
        <FormNotice
          state={{
            status: "bad",
            message: "No pudimos exportar el historial. Probá de nuevo o con menos filtros.",
          }}
        />
      ) : null}
      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <CardTitle>
            {placeName ? `Cambios en ${placeName}` : "Cambios en todo tu alcance"}
          </CardTitle>
          {menus.auditExport ? (
            <div className="flex flex-col gap-1 desk:items-end">
              <Button asChild variant="outline">
                {/* Archivo CSV con los mismos filtros; la exportación queda en el registro de seguridad. */}
                <a href={`/historial/exportar?${exportQuery.toString()}`}>
                  <Download aria-hidden="true" />
                  Exportar (CSV)
                </a>
              </Button>
              <p className="text-sm text-ink-muted">
                Hasta 2.000 cambios por archivo. Para más, exportá por períodos más cortos.
              </p>
            </div>
          ) : null}
        </div>
        <FilterBar label="Buscar en el historial" active={active}>
          <Field id="desde" label="Desde" className="w-full sm:w-44">
            <Input name="desde" type="date" defaultValue={from} />
          </Field>
          <Field id="hasta" label="Hasta" className="w-full sm:w-44">
            <Input name="hasta" type="date" defaultValue={to} />
          </Field>
          <Field id="persona" label="Persona que hizo el cambio" className="w-full desk:w-64">
            <Select name="persona" defaultValue={filter.actorId ?? ""}>
              <option value="">Cualquiera</option>
              {people.map((p) => (
                <option key={p.id} value={p.id}>
                  {personName(p)}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="modulo" label="Módulo" className="w-full desk:w-56">
            <Select name="modulo" defaultValue={filter.module ?? ""}>
              <option value="">Todos</option>
              {Object.entries(MODULE_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>
          {local.restaurantId ? null : (
            <Field id="marca" label="Marca" className="w-full desk:w-56">
              <Select name="marca" defaultValue={filter.brandId ?? ""}>
                <option value="">Todas</option>
                {places.brands.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.name}
                  </option>
                ))}
              </Select>
            </Field>
          )}
          <Field
            id="registro"
            label="Registro (código)"
            hint="Opcional: el código de un dato."
            className="w-full desk:w-80"
          >
            <Input
              name="registro"
              defaultValue={filter.recordId}
              autoComplete="off"
              spellCheck={false}
            />
          </Field>
        </FilterBar>
        <DataTable
          caption="Historial de cambios"
          columns={HISTORY_COLUMNS}
          rows={rows}
          rowKey={(r) => String(r.sequence_number)}
          empty={
            <EmptyState title="No hay cambios con esos filtros en tu alcance.">
              Probá con otras fechas, otra persona, sin filtros o con otro local arriba.
            </EmptyState>
          }
        />
        <CursorPagination
          size={list.size}
          shown={rows.length}
          noun={rows.length === 1 ? "cambio" : "cambios"}
          nextPatch={last ? { antes: String(last.sequence_number) } : null}
          atStart={filter.before === undefined}
          cursorKeys={["antes"]}
          path={PATH}
          params={params}
          nextLabel="Más antiguos"
        />
      </Card>
    </>
  );
}
