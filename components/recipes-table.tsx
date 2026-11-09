"use client";

import Link from "next/link";
import { createColumnHelper, tableFeatures, useTable } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import { RELIABILITY, type Reliability } from "@/lib/cost-labels";
import { formatMoney } from "@/lib/money";
import { cn } from "@/lib/utils";
import { RECIPE_TYPE_LABELS } from "@/lib/recipe-format";
import type { RecipeRow } from "@/lib/recipes";

// Estado de la receta: la versión vigente y, si la hay, una versión abierta (borrador o en revisión).
function StatusBadges({ row }: { row: RecipeRow }) {
  if (!row.isActive) return <Badge>Archivada</Badge>;
  return (
    <span className="flex flex-wrap gap-1">
      {row.isVariant ? <Badge status="info">Variante</Badge> : null}
      {row.current ? <Badge status="ok">Vigente v{row.current}</Badge> : <Badge>Sin vigente</Badge>}
      {row.open === "draft" ? <Badge status="draft">Borrador</Badge> : null}
      {row.open === "in_review" ? <Badge status="review">En revisión</Badge> : null}
    </span>
  );
}

function NameLink({ row }: { row: RecipeRow }) {
  return (
    <Link
      href={`/recetas/${row.id}`}
      className="inline-flex min-h-touch items-start py-0.5 font-medium text-primary underline-offset-4 hover:underline"
    >
      {row.name}
    </Link>
  );
}

// TanStack Table v9, como las demás tablas: columnas fuera del componente.
const features = tableFeatures({});
const column = createColumnHelper<typeof features, RecipeRow>();
const columns = column.columns([
  column.display({
    id: "name",
    header: "Receta",
    cell: ({ row }) => (
      <div className="flex flex-col">
        <NameLink row={row.original} />
        <span className="text-sm text-ink-muted tabular-nums">{row.original.code}</span>
      </div>
    ),
  }),
  column.display({
    id: "type",
    header: "Tipo",
    cell: ({ row }) => <span className="text-ink">{RECIPE_TYPE_LABELS[row.original.type]}</span>,
  }),
  column.display({
    id: "place",
    header: "Alcance",
    cell: ({ row }) => <span className="text-ink">{row.original.place}</span>,
  }),
  column.display({
    id: "category",
    header: "Categoría",
    cell: ({ row }) => <span className="text-ink">{row.original.category || "—"}</span>,
  }),
  column.display({
    id: "status",
    header: "Estado",
    cell: ({ row }) => <StatusBadges row={row.original} />,
  }),
]);

type RecipeCost = { total: number | null; reliability: Reliability };

function CostCell({ cost, label }: { cost?: RecipeCost; label?: string }) {
  if (!cost)
    return <span className="text-sm text-ink-muted">{label ? `${label}: s` : "S"}in costo</span>;
  const r = RELIABILITY[cost.reliability];
  return (
    <span className="flex flex-col items-start gap-1">
      <span className="text-ink tabular-nums">
        {label ? `${label}: ` : ""}
        {cost.total === null ? "sin costo" : formatMoney(cost.total)}
      </span>
      <Badge status={r.status}>{r.label}</Badge>
    </span>
  );
}

// Lista de recetas. En el celular se muestra como tarjetas. Con costs, suma el costo en ese local.
export function RecipesTable({
  rows,
  costs,
  costPlace,
}: {
  rows: RecipeRow[];
  costs?: Record<string, RecipeCost>;
  costPlace?: string;
}) {
  const withCost = costs
    ? column.columns([
        ...columns,
        column.display({
          id: "cost",
          header: `Costo sin IVA en ${costPlace ?? "el local"}`,
          cell: ({ row }) => <CostCell cost={costs[row.original.id]} />,
        }),
      ])
    : columns;
  const table = useTable({ features, columns: withCost, data: rows });

  return (
    <>
      <ul
        className={cn("flex flex-col gap-2", costs ? "lg:hidden" : "sm:hidden")}
        aria-label="Recetas"
      >
        {rows.map((row) => (
          <li
            key={row.id}
            className="flex flex-col gap-1 rounded-lg border border-line bg-surface p-4"
          >
            <NameLink row={row} />
            <span className="text-sm text-ink-muted">
              {row.code} · {RECIPE_TYPE_LABELS[row.type]} · {row.place}
              {row.category ? ` · ${row.category}` : ""}
            </span>
            <StatusBadges row={row} />
            {costs ? (
              <CostCell
                cost={costs[row.id]}
                label={`Costo sin IVA en ${costPlace ?? "el local"}`}
              />
            ) : null}
          </li>
        ))}
      </ul>
      {/* Con scroll propio: con la barra lateral el contenido es más angosto que la ventana (ADR-0036). */}
      <div className={cn("hidden overflow-x-auto", costs ? "lg:block" : "sm:block")}>
        <table className="w-full border-collapse text-left">
          <caption className="sr-only">
            Recetas, su tipo, dónde se usan, categoría y estado{costs ? ", y su costo" : ""}
          </caption>
          <thead>
            {table.getHeaderGroups().map((group) => (
              <tr key={group.id} className="border-b border-line">
                {group.headers.map((header) => (
                  <th
                    key={header.id}
                    scope="col"
                    className="px-3 py-2 text-sm font-medium text-ink-muted"
                  >
                    {header.isPlaceholder ? null : <table.FlexRender header={header} />}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.map((row) => (
              <tr key={row.id} className="border-b border-line align-top last:border-0">
                {row.getAllCells().map((cell) => (
                  <td key={cell.id} className="px-3 py-3">
                    <table.FlexRender cell={cell} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
