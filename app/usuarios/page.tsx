import Link from "next/link";
import { Suspense } from "react";
import { UserPlus } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { PeopleByRoleChart } from "@/components/people-by-role-chart";
import { UsersTable } from "@/components/users-table";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { formatDateTime, getBrandsAndRestaurants, getUsers, getUsersOverview } from "@/lib/data";
import { getMenus, requireMenu } from "@/lib/auth/session";

const PAGE_SIZE = 25;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Tablero de usuarios (reglas de tableros): una pregunta, filtros arriba, KPIs, gráfico, tabla
// y la fecha de los datos. Muestra el estado ACTUAL de las cuentas (una foto del momento), por
// eso no compara con un período anterior ni filtra por fecha.
export default function UsuariosPage({ searchParams }: PageProps<"/usuarios">) {
  return (
    <AppShell
      title="¿Quién tiene acceso y dónde?"
      description="Personas de tu alcance, sus roles y el estado de su cuenta, en este momento."
    >
      <Suspense fallback={<Loading />}>
        <Dashboard searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

async function Dashboard({
  searchParams,
}: {
  searchParams: PageProps<"/usuarios">["searchParams"];
}) {
  await requireMenu("users");
  const params = await searchParams;
  const brandId = first(params.marca);
  const restaurantId = first(params.local);
  const status = first(params.estado);
  const filter = {
    search: first(params.q)?.slice(0, 100),
    brandId: brandId && UUID.test(brandId) ? brandId : undefined,
    restaurantId: restaurantId && UUID.test(restaurantId) ? restaurantId : undefined,
    status: status && ["active", "locked", "disabled"].includes(status) ? status : undefined,
    afterKey: first(params.despues_de),
    afterId: first(params.despues_id),
  };
  const [overview, rows, places, menus] = await Promise.all([
    getUsersOverview(filter),
    getUsers(filter, PAGE_SIZE + 1),
    getBrandsAndRestaurants(),
    getMenus(),
  ]);
  const page = rows.slice(0, PAGE_SIZE);
  const next = rows.length > PAGE_SIZE ? page[page.length - 1] : undefined;
  const nextQuery = new URLSearchParams();
  if (filter.search) nextQuery.set("q", filter.search);
  if (filter.brandId) nextQuery.set("marca", filter.brandId);
  if (filter.restaurantId) nextQuery.set("local", filter.restaurantId);
  if (filter.status) nextQuery.set("estado", filter.status);
  if (next) {
    nextQuery.set("despues_de", next.sort_key);
    nextQuery.set("despues_id", next.id);
  }
  const blocked = overview.locked + overview.disabled;

  return (
    <>
      <Card>
        <form
          method="get"
          className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5 lg:items-end"
          role="search"
        >
          <Field id="q" label="Buscar" className="lg:col-span-2">
            <Input name="q" defaultValue={filter.search} placeholder="Nombre o correo" />
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
          <Field id="local" label="Local">
            <Select name="local" defaultValue={filter.restaurantId ?? ""}>
              <option value="">Todos</option>
              {places.restaurants.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="estado" label="Estado">
            <Select name="estado" defaultValue={filter.status ?? ""}>
              <option value="">Todos</option>
              <option value="active">Activas</option>
              <option value="locked">Bloqueadas</option>
              <option value="disabled">Desactivadas</option>
            </Select>
          </Field>
          <Button type="submit" className="lg:col-start-5">
            Filtrar
          </Button>
        </form>
      </Card>

      <p className="text-sm text-ink-muted">
        Estado actual · Datos al {formatDateTime(overview.as_of)} · Se actualizan en cada consulta
      </p>
      <section
        aria-label="Indicadores"
        className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"
      >
        <Kpi label="Cuentas activas" value={overview.active} status="ok" statusLabel="Operando" />
        <Kpi
          label="Bloqueadas o desactivadas"
          value={blocked}
          status={blocked > 0 ? "warn" : "ok"}
          statusLabel={blocked > 0 ? "Revisar" : "Ninguna"}
        />
        <Kpi
          label="Sin doble verificación"
          value={overview.without_mfa}
          status={overview.without_mfa > 0 ? "warn" : "ok"}
          statusLabel={overview.without_mfa > 0 ? "Les falta registrarla" : "Todas al día"}
        />
        <Kpi
          label="Aprobaciones pendientes"
          value={overview.pending_approvals}
          status={overview.pending_approvals > 0 ? "info" : "ok"}
          statusLabel={overview.pending_approvals > 0 ? "Esperan decisión" : "Nada pendiente"}
        />
      </section>
      {overview.by_role.length > 0 ? (
        <Card>
          <PeopleByRoleChart data={overview.by_role} />
        </Card>
      ) : null}

      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle>Personas</CardTitle>
          {menus.invite ? (
            <Button asChild variant="outline">
              <Link href="/usuarios/invitar">
                <UserPlus aria-hidden="true" />
                Invitar a una persona
              </Link>
            </Button>
          ) : null}
        </div>
        {page.length === 0 ? (
          <EmptyState title="No hay personas con esos filtros.">
            Probá con otro nombre, marca, local o estado.
          </EmptyState>
        ) : (
          <UsersTable rows={page} />
        )}
        {next ? (
          <Button asChild variant="outline" className="self-start">
            <Link href={`/usuarios?${nextQuery.toString()}`}>Ver más personas</Link>
          </Button>
        ) : null}
      </Card>
    </>
  );
}
