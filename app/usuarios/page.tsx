import Link from "next/link";
import { Suspense } from "react";
import { List, UserPlus } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { HistoryList } from "@/components/history-list";
import { LoginsByDayChart } from "@/components/logins-by-day-chart";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState, Kpi } from "@/components/ui/kpi";
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
import { getMenus, requireMenu } from "@/lib/auth/session";

// Tablero de control de usuarios (sección 9 del documento de Soy): una pregunta, filtros fijos
// arriba (fecha, marca, local y módulo), 4 tarjetas, el gráfico de accesos, dos tablas y los
// últimos cambios críticos, siempre con la fecha de los datos.
export default function UsuariosPage({ searchParams }: PageProps<"/usuarios">) {
  return (
    <AppShell
      title="¿Quién tiene acceso y qué está pasando?"
      description="Las cuentas de tu alcance, los ingresos y los cambios importantes."
    >
      <Suspense fallback={<Loading />}>
        <Dashboard searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

function comparison(now: number, before: number): string {
  if (now === before) return `Igual que los 7 días anteriores (${before})`;
  const diff = now - before;
  return `${diff > 0 ? "+" : ""}${diff} contra los 7 días anteriores (${before})`;
}

async function Dashboard({
  searchParams,
}: {
  searchParams: PageProps<"/usuarios">["searchParams"];
}) {
  const session = await requireMenu("users");
  const params = await searchParams;
  const activeId = await getActiveRestaurantId(session.user_id);
  const local = restaurantFilter(first(params.local), activeId);
  const moduleParam = first(params.modulo);
  const filter = {
    from: dateParam(first(params.desde)),
    to: dateParam(first(params.hasta)),
    brandId: uuidOrUndefined(first(params.marca)),
    restaurantId: local.restaurantId,
    module: moduleParam && MODULE_LABELS[moduleParam] ? moduleParam : undefined,
  };
  const [panel, places, menus] = await Promise.all([
    getControlPanel(filter),
    getBrandsAndRestaurants(),
    getMenus(),
  ]);
  const off = panel.deactivated + panel.suspended;

  const brandName = (id?: string) => places.brands.find((b) => b.id === id)?.name;
  const restaurantName = (id?: string) => places.restaurants.find((r) => r.id === id)?.name;
  const activeFilters = [
    filter.from || filter.to ? `Del ${formatDate(panel.from)} al ${formatDate(panel.to)}` : null,
    brandName(filter.brandId),
    filter.restaurantId
      ? `${restaurantName(filter.restaurantId) ?? "Local"}${local.fromSelector ? " (el que elegiste arriba)" : ""}`
      : null,
    filter.module ? MODULE_LABELS[filter.module] : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <>
      <FiltersPanel active={activeFilters}>
        <form
          method="get"
          role="search"
          aria-label="Filtros del tablero"
          className="grid gap-4 sm:grid-cols-2 lg:grid-cols-6 lg:items-end"
        >
          <Field id="desde" label="Desde">
            <Input name="desde" type="date" defaultValue={filter.from ?? panel.from} />
          </Field>
          <Field id="hasta" label="Hasta">
            <Input name="hasta" type="date" defaultValue={filter.to ?? panel.to} />
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
          <Field id="modulo" label="Módulo de los cambios">
            <Select name="modulo" defaultValue={filter.module ?? ""}>
              <option value="">Todos</option>
              {Object.entries(MODULE_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>
          <Button type="submit">Filtrar</Button>
        </form>
      </FiltersPanel>

      <p className="text-sm text-ink-muted">
        Del {formatDate(panel.from)} al {formatDate(panel.to)} · Datos al{" "}
        {formatDateTime(panel.as_of)} · Se actualizan en cada consulta
      </p>

      <section
        aria-label="Indicadores"
        className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"
      >
        <Kpi
          label="Cuentas activas"
          value={panel.active}
          detail={panel.locked > 0 ? `${panel.locked} bloqueadas unos minutos` : "Estado actual"}
          status="ok"
          statusLabel="Operando"
        />
        <Kpi
          label="Desactivadas o suspendidas"
          value={off}
          detail={`${panel.deactivated} desactivadas · ${panel.suspended} suspendidas`}
          status={off > 0 ? "warn" : "ok"}
          statusLabel={off > 0 ? "Revisar" : "Ninguna"}
        />
        <Kpi
          label="Aprobaciones pendientes"
          value={panel.pending_approvals}
          detail="Estado actual"
          status={panel.pending_approvals > 0 ? "info" : "ok"}
          statusLabel={panel.pending_approvals > 0 ? "Esperan decisión" : "Nada pendiente"}
        />
        {panel.can_view_security && panel.rejected_7d !== null ? (
          <Kpi
            label="Accesos rechazados en 7 días"
            value={panel.rejected_7d}
            detail={comparison(panel.rejected_7d, panel.rejected_prev_7d ?? 0)}
            status={panel.rejected_7d > (panel.rejected_prev_7d ?? 0) ? "warn" : "ok"}
            statusLabel={
              panel.rejected_7d > (panel.rejected_prev_7d ?? 0) ? "Subieron" : "Sin aumento"
            }
          />
        ) : (
          <Kpi
            label="Accesos rechazados en 7 días"
            value="Sin permiso"
            detail="Lo ven quienes tienen permiso sobre el registro de seguridad."
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

      <div className="grid gap-6 lg:grid-cols-2">
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
            <table className="w-full text-left tabular-nums">
              <caption className="sr-only">Personas por local</caption>
              <thead>
                <tr className="border-b border-line text-sm text-ink-muted">
                  <th scope="col" className="py-2 font-medium">
                    Local
                  </th>
                  <th scope="col" className="py-2 text-right font-medium">
                    Personas
                  </th>
                </tr>
              </thead>
              <tbody>
                {panel.by_restaurant.map((r) => (
                  <tr key={r.restaurant_id} className="border-b border-line last:border-0">
                    <th scope="row" className="py-2 font-normal text-ink">
                      {r.restaurant_name}{" "}
                      <span className="text-sm text-ink-muted">· {r.brand_name}</span>
                    </th>
                    <td className="py-2 text-right text-ink">{r.people}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
        <Card className="flex flex-col gap-4">
          <CardTitle>Personas por rol</CardTitle>
          {panel.by_role.length === 0 ? (
            <EmptyState title="No hay personas con roles en tu alcance." />
          ) : (
            <table className="w-full text-left tabular-nums">
              <caption className="sr-only">Personas por rol</caption>
              <thead>
                <tr className="border-b border-line text-sm text-ink-muted">
                  <th scope="col" className="py-2 font-medium">
                    Rol
                  </th>
                  <th scope="col" className="py-2 text-right font-medium">
                    Personas
                  </th>
                </tr>
              </thead>
              <tbody>
                {panel.by_role.map((r) => (
                  <tr key={r.role_code} className="border-b border-line last:border-0">
                    <th scope="row" className="py-2 font-normal text-ink">
                      {r.role_name}
                    </th>
                    <td className="py-2 text-right text-ink">{r.people}</td>
                  </tr>
                ))}
              </tbody>
            </table>
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
          <HistoryList rows={panel.critical_changes} compact />
        )}
      </section>

      <div className="flex flex-wrap gap-2">
        <Button asChild variant="outline">
          <Link href="/usuarios/lista">
            <List aria-hidden="true" />
            Ver la lista de personas
          </Link>
        </Button>
        {menus.invite ? (
          <Button asChild variant="outline">
            <Link href="/usuarios/invitar">
              <UserPlus aria-hidden="true" />
              Invitar a una persona
            </Link>
          </Button>
        ) : null}
      </div>
    </>
  );
}
