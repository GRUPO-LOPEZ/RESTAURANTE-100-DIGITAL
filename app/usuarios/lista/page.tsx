import Link from "next/link";
import { Suspense } from "react";
import { UserPlus } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { CursorPagination } from "@/components/ui/cursor-pagination";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import {
  first,
  getActiveRestaurantId,
  getAreas,
  getBrandsAndRestaurants,
  getRoles,
  getUsers,
  personName,
  uuidOrUndefined,
  type UserRow,
} from "@/lib/data";
import { restaurantFilter } from "@/lib/filters";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { getMenus, requireMenu } from "@/lib/auth/session";

const PATH = "/usuarios/lista";
const CURSOR = ["despues_de", "despues_id"];
const STATUS_TABS = [
  { value: undefined, label: "Todas" },
  { value: "active", label: "Activas" },
  { value: "locked", label: "Bloqueadas" },
  { value: "suspended", label: "Suspendidas" },
  { value: "deactivated", label: "Desactivadas" },
] as const;
const STATUSES: readonly string[] = ["active", "locked", "suspended", "deactivated"];

// Usuarios (sección 9; listado del rediseño, ADR-0036): las personas del alcance, con sus roles y el estado de
// su cuenta. El local es el de la barra de arriba; con «Todos mis locales», todo el alcance (decisión de Joaco,
// 2026-11-10). Desde acá se invita; suspender y desactivar se hace en la ficha de cada persona.
export default function ListaPage({ searchParams }: PageProps<"/usuarios/lista">) {
  return (
    <AppShell
      title="Personas"
      description="Todas las personas de tu alcance, con sus roles y el estado de su cuenta."
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <People searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Actions() {
  await requireMenu("users");
  const menus = await getMenus();
  if (!menus.invite) return null;
  return (
    <Button asChild>
      <Link href="/usuarios/invitar">
        <UserPlus aria-hidden="true" />
        Invitar a una persona
      </Link>
    </Button>
  );
}

// El grupo va solo con su nombre, que ya dice "Grupo" (como scopeLabel de lib/data.ts).
const SCOPE = { group: "", brand: "Marca ", restaurant: "Local " } as const;

function StatusBadge({ row }: { row: UserRow }) {
  if (row.status === "deactivated") return <Badge status="bad">Desactivada</Badge>;
  if (row.status === "suspended") return <Badge status="warn">Suspendida</Badge>;
  if (row.locked) return <Badge status="warn">Bloqueada</Badge>;
  return <Badge status="ok">Activa</Badge>;
}

async function People({
  searchParams,
}: {
  searchParams: PageProps<"/usuarios/lista">["searchParams"];
}) {
  const session = await requireMenu("users");
  const raw = await searchParams;
  const params = plainParams(raw);
  const activeId = await getActiveRestaurantId(session.user_id);
  const local = restaurantFilter(first(raw.local), activeId);
  const status = first(raw.estado);
  const role = first(raw.rol);
  const list = parseList(raw, []);
  const filter = {
    search: first(raw.q)?.slice(0, 100),
    // La marca solo filtra cuando no hay un local elegido.
    brandId: local.restaurantId ? undefined : uuidOrUndefined(first(raw.marca)),
    restaurantId: local.restaurantId,
    status: status && STATUSES.includes(status) ? status : undefined,
    roleCode: role && /^[a-z_]{1,60}$/.test(role) ? role : undefined,
    areaId: uuidOrUndefined(first(raw.area)),
    afterKey: first(raw.despues_de)?.slice(0, 300),
    afterId: uuidOrUndefined(first(raw.despues_id)),
  };
  // Un cursor a medias (un enlace editado a mano) se descarta entero: vuelve al principio.
  if (!filter.afterKey || !filter.afterId) {
    filter.afterKey = undefined;
    filter.afterId = undefined;
  }
  const [rows, places, roles, areas] = await Promise.all([
    getUsers(filter, list.size + 1),
    getBrandsAndRestaurants(),
    getRoles(),
    getAreas(),
  ]);
  const page = rows.slice(0, list.size);
  const last = rows.length > list.size ? page[page.length - 1] : undefined;
  const placeName = local.restaurantId
    ? (places.restaurants.find((r) => r.id === local.restaurantId)?.name ??
      "un local que no está en tu alcance")
    : undefined;

  const remove = (key: string) =>
    listHref(PATH, params, { [key]: undefined, despues_de: undefined, despues_id: undefined });
  const active = [
    filter.search ? { label: `Buscar: «${filter.search}»`, removeHref: remove("q") } : null,
    filter.roleCode
      ? {
          label: `Rol: ${roles.find((r) => r.code === filter.roleCode)?.name ?? filter.roleCode}`,
          removeHref: remove("rol"),
        }
      : null,
    filter.brandId
      ? {
          label: `Marca: ${places.brands.find((b) => b.id === filter.brandId)?.name ?? ""}`,
          removeHref: remove("marca"),
        }
      : null,
    filter.areaId
      ? {
          label: `Área: ${areas.find((a) => a.id === filter.areaId)?.label ?? ""}`,
          removeHref: remove("area"),
        }
      : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);
  // Volver desde la ficha a esta misma lista, con sus filtros y su tanda.
  const here = listHref(PATH, params, {});

  const columns: DataColumn<UserRow>[] = [
    {
      key: "person",
      header: "Persona",
      mobile: "title",
      cell: (row) => (
        <span className="flex flex-col">
          <Link
            href={`/usuarios/${row.id}?volver=${encodeURIComponent(here)}`}
            className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-0"
          >
            {personName(row)}
          </Link>
          <span className="text-sm break-all text-ink-muted">{row.email}</span>
        </span>
      ),
    },
    {
      key: "job",
      header: "Puesto y área",
      cell: (row) => [row.job_title, row.area_name].filter(Boolean).join(" · ") || "—",
    },
    {
      key: "roles",
      header: "Roles y lugar",
      cell: (row) =>
        row.roles.length === 0 ? (
          <span className="text-sm text-ink-muted">Sin roles</span>
        ) : (
          <ul className="flex flex-col gap-1">
            {row.roles.map((r) => (
              <li key={r.assignment_id} className="text-sm text-ink">
                {r.role_name}{" "}
                <span className="text-ink-muted">
                  · {SCOPE[r.scope_type]}
                  {r.scope_name}
                </span>
              </li>
            ))}
          </ul>
        ),
    },
    { key: "status", header: "Estado", mobile: "status", cell: (row) => <StatusBadge row={row} /> },
  ];

  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>
        {placeName ? `Personas de ${placeName}` : "Personas de todo tu alcance"}
      </CardTitle>
      <FilterBar label="Filtros de personas" active={active}>
        <Field id="q" label="Buscar" className="w-full desk:w-72">
          <Input
            type="search"
            name="q"
            defaultValue={filter.search}
            placeholder="Nombre, correo o puesto"
          />
        </Field>
        <Field id="rol" label="Rol" className="w-full desk:w-56">
          <Select name="rol" defaultValue={filter.roleCode ?? ""}>
            <option value="">Todos</option>
            {roles.map((r) => (
              <option key={r.code} value={r.code}>
                {r.name}
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
        <Field id="area" label="Área" className="w-full desk:w-56">
          <Select name="area" defaultValue={filter.areaId ?? ""}>
            <option value="">Todas</option>
            {areas.map((a) => (
              <option key={a.id} value={a.id}>
                {a.label}
              </option>
            ))}
          </Select>
        </Field>
      </FilterBar>
      <Tabs
        label="Estado de las cuentas"
        items={STATUS_TABS.map((t) => ({
          href: listHref(PATH, params, {
            estado: t.value,
            despues_de: undefined,
            despues_id: undefined,
          }),
          label: t.label,
          current: t.value === filter.status,
        }))}
      />
      <DataTable
        caption="Personas"
        columns={columns}
        rows={page}
        rowKey={(r) => r.id}
        empty={
          <EmptyState title="No hay personas con esos filtros.">
            Probá con otro nombre, estado, rol, marca o área, o elegí otro local arriba.
          </EmptyState>
        }
      />
      <CursorPagination
        size={list.size}
        shown={page.length}
        noun={page.length === 1 ? "persona" : "personas"}
        nextPatch={last ? { despues_de: last.sort_key, despues_id: last.id } : null}
        atStart={!filter.afterId}
        cursorKeys={CURSOR}
        path={PATH}
        params={params}
      />
    </Card>
  );
}
