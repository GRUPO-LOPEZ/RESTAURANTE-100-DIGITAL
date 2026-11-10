import Link from "next/link";
import { Suspense } from "react";
import { List, UserPlus } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { HistoryList } from "@/components/history-list";
import { LoginsByDayChart } from "@/components/logins-by-day-chart";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Kpi } from "@/components/ui/kpi";
import { EmptyState } from "@/components/ui/states";
import {
  MODULE_LABELS,
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
      title="¿Quién tiene acceso y qué está pasando?"
      description="Las cuentas de tu alcance, los ingresos y los cambios importantes."
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
      {menus.invite ? (
        <Button asChild>
          <Link href="/usuarios/invitar">
            <UserPlus aria-hidden="true" />
            Invitar a una persona
          </Link>
        </Button>
      ) : null}
    </>
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
        className="grid grid-cols-1 gap-4 sm:grid-cols-2 desk:grid-cols-4"
      >
        {/* Los tres primeros son el estado de hoy (no dependen del período elegido). */}
        <Kpi
          label="Cuentas activas"
          period="Hoy"
          value={panel.active}
          detail={
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
          label="Desactivadas o suspendidas"
          period="Hoy"
          value={off}
          detail={`${weekAgo(off, offBefore, panel.prev_as_of)} · ${panel.deactivated} desactivadas · ${panel.suspended} suspendidas`}
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
          label="Aprobaciones pendientes"
          period="Hoy"
          value={panel.pending_approvals}
          detail={weekAgo(panel.pending_approvals, panel.pending_prev, panel.prev_as_of)}
          status={panel.pending_approvals > 0 ? "info" : "ok"}
          statusLabel={panel.pending_approvals > 0 ? "Esperan decisión" : "Nada pendiente"}
          href={panel.pending_approvals > 0 ? "/aprobaciones" : undefined}
          hrefLabel="Ver cuáles"
        />
        {panel.can_view_security && panel.rejected_7d !== null ? (
          <Kpi
            label="Accesos rechazados en 7 días"
            value={panel.rejected_7d}
            detail={
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
            label="Accesos rechazados en 7 días"
            value="—"
            detail="Lo ven quienes tienen permiso sobre el registro de seguridad."
            status="none"
            statusLabel="Sin permiso"
          />
        )}
      </section>

      <Card className="flex flex-col gap-4">
        <CardTitle>Accesos por día</CardTitle>
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
      </Card>

      <div className="grid gap-6 desk:grid-cols-2">
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Personas por local</CardTitle>
            <CardDescription>
              Con un rol de ese local o de su marca. Con acceso a todo el grupo:{" "}
              {panel.group_wide_people}.
            </CardDescription>
          </div>
          {panel.by_restaurant.length === 0 ? (
            <EmptyState title="No hay locales en tu alcance." />
          ) : (
            <DataTable
              caption="Personas por local"
              columns={[
                {
                  key: "place",
                  header: "Local",
                  mobile: "title",
                  cell: (r) => (
                    <span>
                      {r.restaurant_name}{" "}
                      <span className="text-sm text-ink-muted">· {r.brand_name}</span>
                    </span>
                  ),
                },
                {
                  key: "people",
                  header: "Personas",
                  align: "right",
                  cell: (r) => r.people.toLocaleString("es-AR"),
                },
              ]}
              rows={panel.by_restaurant}
              rowKey={(r) => r.restaurant_id}
            />
          )}
        </Card>
        <Card className="flex flex-col gap-4">
          <CardTitle>Personas por rol</CardTitle>
          {panel.by_role.length === 0 ? (
            <EmptyState title="No hay personas con roles en tu alcance." />
          ) : (
            <DataTable
              caption="Personas por rol"
              columns={[
                { key: "role", header: "Rol", mobile: "title", cell: (r) => r.role_name },
                {
                  key: "people",
                  header: "Personas",
                  align: "right",
                  cell: (r) => r.people.toLocaleString("es-AR"),
                },
              ]}
              rows={panel.by_role}
              rowKey={(r) => r.role_code}
            />
          )}
        </Card>
      </div>

      <section aria-labelledby="criticos" className="flex flex-col gap-4">
        <h2 id="criticos" className="text-xl text-ink">
          Últimos cambios críticos
        </h2>
        <p className="text-sm text-ink-muted">
          Roles, permisos, cuentas y aprobaciones del período, dentro de lo que podés ver del
          historial.
        </p>
        {panel.critical_changes.length === 0 ? (
          <EmptyState title="No hubo cambios críticos en el período." />
        ) : (
          <HistoryList rows={panel.critical_changes.slice(0, CRITICAL_SHOWN)} compact />
        )}
        <Link
          href={historyHref}
          className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline desk:min-h-control"
        >
          Ver todos los cambios en el Historial
        </Link>
      </section>
    </>
  );
}
