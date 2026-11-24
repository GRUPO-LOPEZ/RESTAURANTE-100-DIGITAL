import Link from "next/link";
import { Suspense } from "react";
import { List } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { InviteModal } from "@/components/invite-modal";
import { LoginsByDayChart } from "@/components/logins-by-day-chart";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Kpi } from "@/components/ui/kpi";
import { EmptyState } from "@/components/ui/states";
import { Tile } from "@/components/ui/tile";
import {
  ACTION_LABELS,
  MODULE_LABELS,
  TABLE_LABELS,
  first,
  formatDate,
  formatDateTime,
  getActiveRestaurantId,
  getBrandsAndRestaurants,
  getControlPanel,
  uuidOrUndefined,
} from "@/lib/data";
import { dateParam, restaurantFilter } from "@/lib/filters";
import { listHref, plainParams } from "@/lib/list-params";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Tablero de control de usuarios (sección 9 del documento de Soy; panel del rediseño, ADR-0036): una pregunta,
// filtros que se aplican solos (fecha, marca y módulo), 4 tarjetas, el gráfico de accesos, dos tablas y los
// últimos cambios críticos, siempre con la fecha de los datos. El local es el de la barra de arriba; con
// «Todos mis locales», todo el alcance (decisión de Joaco, 2026-11-10).
export default function UsuariosPage({ searchParams }: PageProps<"/usuarios">) {
  return (
    <AppShell
      title="Tablero de usuarios"
      heading="¿Quién tiene acceso y qué está pasando?"
      fill
      meta={<span className="text-sm text-ink-muted">cuentas, ingresos y cambios importantes</span>}
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Dashboard searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Actions() {
  await requireMenu("users");
  const menus = await getMenus();
  return (
    <>
      <Button asChild variant="outline">
        <Link href="/usuarios/lista">
          <List aria-hidden="true" />
          Ver personas
        </Link>
      </Button>
      {menus.invite ? <InviteModal /> : null}
    </>
  );
}

// Nombre y cantidad, en renglones de 28 px: entran todos los roles sin desplazar (ADR-0045).
function CountList({
  label,
  rows,
  empty,
}: {
  label: string;
  rows: { key: string; name: string; people: number }[];
  empty: string;
}) {
  if (rows.length === 0) return <EmptyState title={empty} />;
  return (
    <ul aria-label={label} className="flex flex-col">
      {rows.map((r) => (
        <li
          key={r.key}
          className="flex min-h-7 items-center justify-between gap-2 border-b border-line text-sm text-ink last:border-0"
        >
          <span className="min-w-0">{r.name}</span>
          <span className="shrink-0 font-medium tabular-nums">
            {r.people.toLocaleString("es-AR")}
            <span className="sr-only">{r.people === 1 ? " persona" : " personas"}</span>
          </span>
        </li>
      ))}
    </ul>
  );
}

const PATH = "/usuarios";
// Cuántos cambios críticos se ven en el tablero; el resto, en el Historial.
const CRITICAL_SHOWN = 5;

function comparison(now: number, before: number): string {
  if (now === before) return `Igual que los 7 días anteriores (${before})`;
  const diff = now - before;
  return `${diff > 0 ? "+" : ""}${diff} contra los 7 días anteriores (${before})`;
}

// Para los KPI de estado: el valor de hoy contra cómo estaba hace 7 días, con la fecha (regla de
// tableros 2). No depende del período filtrado.
function weekAgo(now: number, before: number, asOf: string): string {
  const when = formatDate(asOf);
  if (now === before) return `Igual que el ${when} (${before})`;
  const diff = now - before;
  return `${diff > 0 ? "+" : ""}${diff} contra el ${when} (${before})`;
}

async function Dashboard({
  searchParams,
}: {
  searchParams: PageProps<"/usuarios">["searchParams"];
}) {
  const session = await requireMenu("users");
  const params = await searchParams;
  const plain = plainParams(params);
  const activeId = await getActiveRestaurantId(session.user_id);
  const local = restaurantFilter(first(params.local), activeId);
  const moduleParam = first(params.modulo);
  const filter = {
    from: dateParam(first(params.desde)),
    to: dateParam(first(params.hasta)),
    // La marca solo filtra cuando no hay un local elegido.
    brandId: local.restaurantId ? undefined : uuidOrUndefined(first(params.marca)),
    restaurantId: local.restaurantId,
    module: moduleParam && MODULE_LABELS[moduleParam] ? moduleParam : undefined,
  };
  const [panel, places] = await Promise.all([getControlPanel(filter), getBrandsAndRestaurants()]);
  const off = panel.deactivated + panel.suspended;
  const offBefore = panel.deactivated_prev + panel.suspended_prev;

  const placeName = local.restaurantId
    ? (places.restaurants.find((r) => r.id === local.restaurantId)?.name ??
      "Un local que no está en tu alcance")
    : undefined;
  // "Ver todos" lleva al Historial con el mismo período, módulo y marca.
  const historyQuery = new URLSearchParams();
  if (filter.from) historyQuery.set("desde", filter.from);
  if (filter.to) historyQuery.set("hasta", filter.to);
  if (filter.module) historyQuery.set("modulo", filter.module);
  if (filter.brandId) historyQuery.set("marca", filter.brandId);
  const historyHref = historyQuery.size ? `/historial?${historyQuery}` : "/historial";
  const prevRejected = panel.rejected_prev_7d;
  const remove = (...keys: string[]) =>
    listHref(PATH, plain, Object.fromEntries(keys.map((k) => [k, undefined])));
  const active = [
    filter.from || filter.to
      ? {
          label: `Del ${formatDate(panel.from)} al ${formatDate(panel.to)}`,
          removeHref: remove("desde", "hasta"),
        }
      : null,
    filter.brandId
      ? {
          label: `Marca: ${places.brands.find((b) => b.id === filter.brandId)?.name ?? ""}`,
          removeHref: remove("marca"),
        }
      : null,
    filter.module
      ? { label: `Módulo: ${MODULE_LABELS[filter.module]}`, removeHref: remove("modulo") }
      : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);

  return (
    <>
      <FilterBar label="Filtros del tablero" active={active}>
        <Field id="desde" label="Desde" className="w-full sm:w-44">
          <Input name="desde" type="date" defaultValue={filter.from ?? panel.from} />
        </Field>
        <Field id="hasta" label="Hasta" className="w-full sm:w-44">
          <Input name="hasta" type="date" defaultValue={filter.to ?? panel.to} />
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
        <Field id="modulo" label="Módulo de los cambios" className="w-full desk:w-56">
          <Select name="modulo" defaultValue={filter.module ?? ""}>
            <option value="">Todos</option>
            {Object.entries(MODULE_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </Select>
        </Field>
      </FilterBar>

      <p className="text-sm text-ink-muted">
        {placeName ?? "Todo tu alcance"} · Del {formatDate(panel.from)} al {formatDate(panel.to)} ·
        Datos al {formatDateTime(panel.as_of)} · Se actualizan en cada consulta
      </p>

      <section
        aria-label="Indicadores"
        className="grid grid-cols-1 gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4"
      >
        {/* Los tres primeros son el estado de hoy (no dependen del período elegido). */}
        <Kpi
          compact
          label="Cuentas activas"
          period="Hoy"
          value={panel.active}
          note={
            panel.active === 0
              ? "Sin cuentas activas en lo que estás mirando."
              : [
                  weekAgo(panel.active, panel.active_prev, panel.prev_as_of),
                  panel.locked > 0 ? `${panel.locked} bloqueadas unos minutos` : null,
                ]
                  .filter(Boolean)
                  .join(" · ")
          }
          status={panel.active === 0 ? "none" : "ok"}
          statusLabel={panel.active === 0 ? "Sin datos" : "Operando"}
          href={panel.active > 0 ? "/usuarios/lista?estado=active" : undefined}
          hrefLabel="Ver cuáles"
        />
        <Kpi
          compact
          label="Desactivadas o suspendidas"
          period="Hoy"
          value={off}
          note={`${weekAgo(off, offBefore, panel.prev_as_of)} · ${panel.deactivated} desactivadas · ${panel.suspended} suspendidas`}
          status={off > 0 ? "warn" : "ok"}
          statusLabel={off > 0 ? "Revisar" : "Ninguna"}
          href={
            off > 0
              ? `/usuarios/lista?estado=${panel.suspended > 0 ? "suspended" : "deactivated"}`
              : undefined
          }
          hrefLabel="Ver cuáles"
        />
        <Kpi
          compact
          label="Aprobaciones pendientes"
          period="Hoy"
          value={panel.pending_approvals}
          note={weekAgo(panel.pending_approvals, panel.pending_prev, panel.prev_as_of)}
          status={panel.pending_approvals > 0 ? "info" : "ok"}
          statusLabel={panel.pending_approvals > 0 ? "Esperan decisión" : "Nada pendiente"}
          href={panel.pending_approvals > 0 ? "/aprobaciones" : undefined}
          hrefLabel="Ver cuáles"
        />
        {panel.can_view_security && panel.rejected_7d !== null ? (
          <Kpi
            compact
            label="Accesos rechazados en 7 días"
            value={panel.rejected_7d}
            note={
              prevRejected === null
                ? "Sin el dato de los 7 días anteriores para comparar."
                : comparison(panel.rejected_7d, prevRejected)
            }
            status={
              prevRejected === null ? "none" : panel.rejected_7d > prevRejected ? "warn" : "ok"
            }
            statusLabel={
              prevRejected === null
                ? "Sin comparación"
                : panel.rejected_7d > prevRejected
                  ? "Subieron"
                  : "Sin aumento"
            }
          />
        ) : (
          <Kpi
            compact
            label="Accesos rechazados en 7 días"
            value="—"
            note="Lo ven quienes tienen permiso sobre el registro de seguridad."
            status="none"
            statusLabel="Sin permiso"
          />
        )}
      </section>

      {/* Cuatro columnas que ocupan el alto que queda; lo que no entra se desplaza dentro de su tarjeta (ADR-0051). */}
      <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[4fr_3fr_3fr_4fr] desk:grid-rows-[minmax(0,1fr)]">
        <Tile id="accesos" title="Accesos por día" scroll>
          {panel.logins_by_day &&
          panel.logins_by_day.every((d) => d.succeeded === 0 && d.failed === 0) ? (
            <EmptyState title="No hubo ingresos en el período." />
          ) : panel.logins_by_day ? (
            <LoginsByDayChart data={panel.logins_by_day} />
          ) : (
            <EmptyState title="No tenés permiso para ver los ingresos.">
              Los ven Superadministración, Dirección y Auditoría.
            </EmptyState>
          )}
        </Tile>
        <Tile
          id="por-local"
          title="Personas por local"
          scroll
          titleExtra={
            <span className="text-xs text-ink-muted">
              {panel.group_wide_people} con todo el grupo
            </span>
          }
        >
          <CountList
            label="Personas por local"
            rows={panel.by_restaurant.map((r) => ({
              key: r.restaurant_id,
              name: r.restaurant_name,
              people: r.people,
            }))}
            empty="No hay locales en tu alcance."
          />
        </Tile>
        <Tile id="por-rol" title="Personas por rol" scroll>
          <CountList
            label="Personas por rol"
            rows={panel.by_role.map((r) => ({
              key: r.role_code,
              name: r.role_name,
              people: r.people,
            }))}
            empty="No hay personas con roles en tu alcance."
          />
        </Tile>
        <Tile id="criticos" title="Últimos cambios críticos" scroll>
          {panel.critical_changes.length === 0 ? (
            <EmptyState title="No hubo cambios críticos en el período." />
          ) : (
            <ol className="flex flex-col gap-2">
              {panel.critical_changes.slice(0, CRITICAL_SHOWN).map((r) => (
                <li
                  key={r.sequence_number}
                  className="flex flex-col border-b border-line pb-2 text-sm last:border-0"
                >
                  <span className="font-medium text-ink">
                    {ACTION_LABELS[r.action] ?? "Cambio"} ·{" "}
                    {TABLE_LABELS[`${r.table_schema}.${r.table_name}`] ?? "Dato del sistema"}
                  </span>
                  <span className="text-xs text-ink-muted">
                    <time dateTime={r.occurred_at}>{formatDateTime(r.occurred_at)}</time> ·{" "}
                    {[r.actor_name, r.place_name].filter(Boolean).join(" · ")}
                  </span>
                  {r.reason ? (
                    <span className="truncate text-xs text-ink-muted" title={r.reason}>
                      {r.reason}
                    </span>
                  ) : null}
                </li>
              ))}
            </ol>
          )}
          <Link
            href={historyHref}
            className="inline-flex min-h-touch items-center self-start text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
          >
            Ver todos los cambios en el Historial
          </Link>
        </Tile>
      </div>
    </>
  );
}
