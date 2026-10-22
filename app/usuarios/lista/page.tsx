import Link from "next/link";
import { Suspense } from "react";
import { UserPlus } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { UsersTable } from "@/components/users-table";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import {
  first,
  getActiveRestaurantId,
  getAreas,
  getBrandsAndRestaurants,
  getRoles,
  getUsers,
  uuidOrUndefined,
} from "@/lib/data";
import { restaurantFilter } from "@/lib/filters";
import { getMenus, requireMenu } from "@/lib/auth/session";

const PAGE_SIZE = 25;
const STATUSES = ["active", "locked", "suspended", "deactivated"];

// Usuarios (sección 9): la lista con filtros por estado, marca, local, rol y área. Desde acá se
// invita; suspender y desactivar se hace en la ficha de cada persona.
export default function ListaPage({ searchParams }: PageProps<"/usuarios/lista">) {
  return (
    <AppShell
      title="Personas"
      description="Todas las personas de tu alcance, con sus roles y el estado de su cuenta."
    >
      <Suspense fallback={<Loading />}>
        <People searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function People({
  searchParams,
}: {
  searchParams: PageProps<"/usuarios/lista">["searchParams"];
}) {
  const session = await requireMenu("users");
  const params = await searchParams;
  const activeId = await getActiveRestaurantId(session.user_id);
  const local = restaurantFilter(first(params.local), activeId);
  const status = first(params.estado);
  const role = first(params.rol);
  const filter = {
    search: first(params.q)?.slice(0, 100),
    brandId: uuidOrUndefined(first(params.marca)),
    restaurantId: local.restaurantId,
    status: status && STATUSES.includes(status) ? status : undefined,
    roleCode: role && /^[a-z_]{1,60}$/.test(role) ? role : undefined,
    areaId: uuidOrUndefined(first(params.area)),
    afterKey: first(params.despues_de),
    afterId: uuidOrUndefined(first(params.despues_id)),
  };
  const [rows, places, roles, areas, menus] = await Promise.all([
    getUsers(filter, PAGE_SIZE + 1),
    getBrandsAndRestaurants(),
    getRoles(),
    getAreas(),
    getMenus(),
  ]);
  const page = rows.slice(0, PAGE_SIZE);
  const next = rows.length > PAGE_SIZE ? page[page.length - 1] : undefined;
  const nextQuery = new URLSearchParams();
  if (filter.search) nextQuery.set("q", filter.search);
  if (filter.brandId) nextQuery.set("marca", filter.brandId);
  nextQuery.set("local", filter.restaurantId ?? "todos");
  if (filter.status) nextQuery.set("estado", filter.status);
  if (filter.roleCode) nextQuery.set("rol", filter.roleCode);
  if (filter.areaId) nextQuery.set("area", filter.areaId);
  if (next) {
    nextQuery.set("despues_de", next.sort_key);
    nextQuery.set("despues_id", next.id);
  }

  const brandName = (id?: string) => places.brands.find((b) => b.id === id)?.name;
  const restaurantName = (id?: string) => places.restaurants.find((r) => r.id === id)?.name;
  const STATUS_TEXT: Record<string, string> = {
    active: "Activas",
    locked: "Bloqueadas",
    suspended: "Suspendidas",
    deactivated: "Desactivadas",
  };
  const activeFilters = [
    filter.search ? `"${filter.search}"` : null,
    filter.status ? STATUS_TEXT[filter.status] : null,
    filter.roleCode ? roles.find((r) => r.code === filter.roleCode)?.name : null,
    brandName(filter.brandId),
    filter.restaurantId
      ? `${restaurantName(filter.restaurantId) ?? "Local"}${local.fromSelector ? " (el que elegiste arriba)" : ""}`
      : null,
    filter.areaId ? areas.find((a) => a.id === filter.areaId)?.label : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <>
      <FiltersPanel active={activeFilters}>
        <form
          method="get"
          role="search"
          aria-label="Filtros de la lista"
          className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
        >
          <Field id="q" label="Buscar" className="lg:col-span-2">
            <Input name="q" defaultValue={filter.search} placeholder="Nombre, correo o puesto" />
          </Field>
          <Field id="estado" label="Estado">
            <Select name="estado" defaultValue={filter.status ?? ""}>
              <option value="">Todos</option>
              <option value="active">Activas</option>
              <option value="locked">Bloqueadas</option>
              <option value="suspended">Suspendidas</option>
              <option value="deactivated">Desactivadas</option>
            </Select>
          </Field>
          <Field id="rol" label="Rol">
            <Select name="rol" defaultValue={filter.roleCode ?? ""}>
              <option value="">Todos</option>
              {roles.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.name}
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
          <Field id="area" label="Área">
            <Select name="area" defaultValue={filter.areaId ?? ""}>
              <option value="">Todas</option>
              {areas.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.label}
                </option>
              ))}
            </Select>
          </Field>
          <Button type="submit">Filtrar</Button>
        </form>
      </FiltersPanel>

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
            Probá con otro nombre, estado, rol, marca, local o área.
          </EmptyState>
        ) : (
          <UsersTable rows={page} />
        )}
        {next ? (
          <Button asChild variant="outline" className="self-start">
            <Link href={`/usuarios/lista?${nextQuery.toString()}`}>Ver más personas</Link>
          </Button>
        ) : null}
      </Card>
    </>
  );
}
