import Link from "next/link";
import { Suspense } from "react";
import { Download } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { HistoryList } from "@/components/history-list";
import { Button } from "@/components/ui/button";

import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import { FormNotice } from "@/components/form-notice";
import {
  HISTORY_PAGE,
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
import { getMenus, requireMenu } from "@/lib/auth/session";

// Historial inalterable (secciones 6 y 9): quién, cuándo, qué cambió y por qué, en lenguaje
// simple, con búsqueda por fecha, persona, marca, local, módulo y registro, y exportación.
// Solo lo de tu alcance, y sin costos si no tenés permiso para verlos.
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
  const params = await searchParams;
  const activeId = await getActiveRestaurantId(session.user_id);
  const local = restaurantFilter(first(params.local), activeId);
  const beforeRaw = first(params.antes);
  const moduleParam = first(params.modulo);
  const from = dateParam(first(params.desde));
  const to = dateParam(first(params.hasta));
  const filter = {
    before: beforeRaw && /^[0-9]{1,18}$/.test(beforeRaw) ? Number(beforeRaw) : undefined,
    recordId: uuidOrUndefined(first(params.registro)),
    from: dayStart(from),
    to: dayEnd(to),
    actorId: uuidOrUndefined(first(params.persona)),
    brandId: uuidOrUndefined(first(params.marca)),
    restaurantId: local.restaurantId,
    module: moduleParam && MODULE_LABELS[moduleParam] ? moduleParam : undefined,
  };
  const [rows, places, firstPeople, chosen, menus] = await Promise.all([
    getHistory(filter),
    getBrandsAndRestaurants(),
    getUsers({}, 100),
    filter.actorId ? getUser(filter.actorId) : Promise.resolve(null),
    getMenus(),
  ]);
  // La lista muestra las primeras 100 personas; si la URL elige otra, también aparece.
  const people =
    chosen && !firstPeople.some((p) => p.id === chosen.id) ? [chosen, ...firstPeople] : firstPeople;

  // Los mismos filtros, para "ver más" y para exportar.
  const query = new URLSearchParams();
  if (from) query.set("desde", from);
  if (to) query.set("hasta", to);
  if (filter.actorId) query.set("persona", filter.actorId);
  if (filter.brandId) query.set("marca", filter.brandId);
  query.set("local", filter.restaurantId ?? "todos");
  if (filter.module) query.set("modulo", filter.module);
  if (filter.recordId) query.set("registro", filter.recordId);
  const last = rows[rows.length - 1];
  const more = new URLSearchParams(query);
  if (last) more.set("antes", String(last.sequence_number));

  const brandName = (id?: string) => places.brands.find((b) => b.id === id)?.name;
  const restaurantName = (id?: string) => places.restaurants.find((r) => r.id === id)?.name;
  const activeFilters = [
    from ? `Desde ${formatDate(from)}` : null,
    to ? `Hasta ${formatDate(to)}` : null,
    filter.actorId ? (chosen ? personName(chosen) : "Una persona") : null,
    filter.module ? MODULE_LABELS[filter.module] : null,
    brandName(filter.brandId),
    filter.restaurantId
      ? `${restaurantName(filter.restaurantId) ?? "Local"}${local.fromSelector ? " (el que elegiste arriba)" : ""}`
      : null,
    filter.recordId ? "Un registro" : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <>
      <FiltersPanel active={activeFilters}>
        <form
          method="get"
          role="search"
          aria-label="Buscar en el historial"
          className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
        >
          <Field id="desde" label="Desde">
            <Input name="desde" type="date" defaultValue={from} />
          </Field>
          <Field id="hasta" label="Hasta">
            <Input name="hasta" type="date" defaultValue={to} />
          </Field>
          <Field id="persona" label="Persona que hizo el cambio">
            <Select name="persona" defaultValue={filter.actorId ?? ""}>
              <option value="">Cualquiera</option>
              {people.map((p) => (
                <option key={p.id} value={p.id}>
                  {personName(p)}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="modulo" label="Módulo">
            <Select name="modulo" defaultValue={filter.module ?? ""}>
              <option value="">Todos</option>
              {Object.entries(MODULE_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="marca" label="Marca">
            <Select name="marca" defaultValue={filter.brandId ?? ""}>
              <option value="">Todas</option>
              {places.brands.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field
            id="local"
            label="Local"
            hint={local.fromSelector ? "El que elegiste arriba." : undefined}
          >
            <Select name="local" defaultValue={filter.restaurantId ?? "todos"}>
              <option value="todos">Todos</option>
              {places.restaurants.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="registro" label="Registro (código)" hint="Opcional: el código de un dato.">
            <Input
              name="registro"
              defaultValue={filter.recordId}
              autoComplete="off"
              spellCheck={false}
            />
          </Field>
          <Button type="submit">Buscar</Button>
        </form>
      </FiltersPanel>

      {first(params.error) === "exportar" ? (
        <FormNotice
          state={{
            status: "bad",
            message: "No pudimos exportar el historial. Probá de nuevo o con menos filtros.",
          }}
        />
      ) : null}
      {menus.auditExport ? (
        <div className="flex flex-col gap-1">
          <Button asChild variant="outline" className="self-start">
            {/* Archivo CSV con los mismos filtros; la exportación queda en el registro de seguridad. */}
            <a href={`/historial/exportar?${query.toString()}`}>
              <Download aria-hidden="true" />
              Exportar (CSV)
            </a>
          </Button>
          <p className="text-sm text-ink-muted">
            Hasta 2.000 cambios por archivo. Para más, exportá por períodos más cortos.
          </p>
        </div>
      ) : null}

      {rows.length === 0 ? (
        <EmptyState title="No hay cambios con esos filtros en tu alcance.">
          Probá con otras fechas, otra persona o sin filtros.
        </EmptyState>
      ) : (
        <HistoryList rows={rows} />
      )}
      {rows.length === HISTORY_PAGE && last ? (
        <Button asChild variant="outline" className="self-start">
          <Link href={`/historial?${more.toString()}`}>Ver cambios más antiguos</Link>
        </Button>
      ) : null}
    </>
  );
}
