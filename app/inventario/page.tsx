import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { first, formatDate, getActiveRestaurantId, uuidOrUndefined } from "@/lib/data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { qtyText } from "@/lib/purchase-orders";
import { getIngredientOptions, getMovements, type MovementRow } from "@/lib/receipts-data";

// Inventario (Fase 3, Prompt 4, ADR-0056), listado tipo C de consulta: ¿qué entró al stock, cuándo y de qué lote? Las
// entradas por recepción del local elegido arriba (o de todos mis locales), en la unidad de uso de cada materia prima.
// Nada descuenta todavía (D8). Filtros por materia prima, fechas y lote (P9: el lote se sigue desde acá y desde Calidad).
// En una pantalla: la tabla se desplaza adentro (ADR-0048).
export default function InventarioPage({ searchParams }: PageProps<"/inventario">) {
  return (
    <AppShell
      title="Inventario"
      description="Lo que entró al stock de cada local, en la unidad de uso de cada materia prima."
      fill
    >
      <Suspense fallback={<Loading />}>
        <Movements searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const PATH = "/inventario";
const DATE = /^\d{4}-\d{2}-\d{2}$/;

async function Movements({
  searchParams,
}: {
  searchParams: PageProps<"/inventario">["searchParams"];
}) {
  const session = await requireMenu("inventory");
  const raw = await searchParams;
  const params = plainParams(raw);
  const list = parseList(raw, [], null);
  const local =
    uuidOrUndefined(first(raw.local)) ??
    (await getActiveRestaurantId(session.user_id)) ??
    undefined;
  const [ingredients, menus] = await Promise.all([getIngredientOptions(), getMenus()]);
  const ingredientId = uuidOrUndefined(first(raw.materia));
  const ingredient = ingredients.find((i) => i.id === ingredientId);
  const from = DATE.test(first(raw.desde) ?? "") ? first(raw.desde) : undefined;
  const to = DATE.test(first(raw.hasta) ?? "") ? first(raw.hasta) : undefined;
  const lot = (first(raw.lote) ?? "").trim().slice(0, 60);
  const { rows, total } = await getMovements({
    restaurantId: local,
    ingredientId: ingredient?.id,
    from,
    to,
    lot: lot || undefined,
    page: list.page - 1,
    size: list.size,
  });

  const remove = (key: string) => listHref(PATH, params, { [key]: undefined, pagina: undefined });
  const active = [
    lot ? { label: `Lote: «${lot}»`, removeHref: remove("lote") } : null,
    ingredient
      ? { label: `Materia prima: ${ingredient.name}`, removeHref: remove("materia") }
      : null,
    from
      ? { label: `Desde el ${from.split("-").reverse().join("/")}`, removeHref: remove("desde") }
      : null,
    to
      ? { label: `Hasta el ${to.split("-").reverse().join("/")}`, removeHref: remove("hasta") }
      : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);

  const columns: DataColumn<MovementRow>[] = [
    {
      key: "when",
      header: "Cuándo",
      mobile: "line",
      cell: (m) => <span className="tabular-nums">{formatDate(m.occurred_at)}</span>,
    },
    { key: "ingredient", header: "Materia prima", mobile: "title", cell: (m) => m.ingredient_name },
    {
      key: "quantity",
      header: "Entró",
      align: "right",
      mobile: "line",
      cell: (m) => (
        <span className="tabular-nums">
          {qtyText(m.quantity)} {m.unit_name}
        </span>
      ),
    },
    {
      key: "product",
      header: "Cómo llegó",
      mobile: "line",
      cell: (m) =>
        m.product_name
          ? `${m.packages !== null ? `${qtyText(m.packages)} × ` : ""}${m.product_name}`
          : "Sin nombre de factura",
    },
    {
      key: "lot",
      header: "Lote",
      mobile: "line",
      cell: (m) => (m.lot_code ? <span className="tabular-nums">{m.lot_code}</span> : "—"),
    },
    {
      key: "origin",
      header: "Origen",
      mobile: "line",
      cell: (m) =>
        m.purchase_order_id && m.order_number ? (
          <span>
            {m.supplier_name} ·{" "}
            {menus.orders ? (
              <Link
                href={`/compras/ordenes/${m.purchase_order_id}?seccion=recepcion`}
                className="text-primary tabular-nums underline-offset-4 hover:underline"
              >
                {m.order_number}
              </Link>
            ) : (
              <span className="tabular-nums">{m.order_number}</span>
            )}
          </span>
        ) : (
          `${m.supplier_name ?? "—"} · sin OC`
        ),
    },
    // El local, solo si se mira más de uno (con un local elegido arriba, sobra).
    ...(local
      ? []
      : [
          {
            key: "place",
            header: "Local",
            mobile: "line" as const,
            cell: (m: MovementRow) => m.restaurant_name,
          },
        ]),
  ];

  return (
    <section
      aria-label="Movimientos de stock"
      className="flex flex-col gap-3 rounded-md border border-line bg-surface p-4 desk:min-h-0 desk:flex-[1_1_0px]"
    >
      <FilterBar label="Filtros del inventario" active={active}>
        <Field id="inv-lote" label="Lote" className="w-full desk:w-48">
          <Input type="search" name="lote" defaultValue={lot} placeholder="Por ejemplo, L-2611" />
        </Field>
        <Field id="inv-materia" label="Materia prima" className="w-full desk:w-64">
          <Select name="materia" defaultValue={ingredient?.id ?? ""}>
            <option value="">Todas</option>
            {ingredients.map((i) => (
              <option key={i.id} value={i.id}>
                {i.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field id="inv-desde" label="Desde" className="w-full desk:w-44">
          <Input type="date" name="desde" defaultValue={from ?? ""} />
        </Field>
        <Field id="inv-hasta" label="Hasta" className="w-full desk:w-44">
          <Input type="date" name="hasta" defaultValue={to ?? ""} />
        </Field>
      </FilterBar>
      {rows.length === 0 && list.page > 1 ? (
        <EmptyState title="Esa página no existe.">
          <Link
            href={listHref(PATH, params, { pagina: undefined })}
            className="text-primary underline-offset-4 hover:underline"
          >
            Ir a la primera página
          </Link>
        </EmptyState>
      ) : (
        <DataTable
          caption="Movimientos de stock"
          scroll
          columns={columns}
          rows={rows}
          rowKey={(r) => r.id}
          list={list}
          path={PATH}
          params={params}
          empty={
            <EmptyState
              title={
                active.length > 0
                  ? "No hay movimientos con esos filtros."
                  : "Todavía no entró nada al stock."
              }
            >
              {active.length > 0
                ? "Probá con otro lote, materia prima o fechas."
                : "Las entradas aparecen al cerrar una recepción."}
            </EmptyState>
          }
        />
      )}
      {total > 0 ? (
        <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
      ) : null}
    </section>
  );
}
