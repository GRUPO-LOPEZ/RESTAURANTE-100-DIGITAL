"use client";

import Link from "next/link";
import { createColumnHelper, tableFeatures, useTable } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import { RELIABILITY, type CostRow } from "@/lib/cost-labels";
import { RECIPE_TYPE_LABELS } from "@/lib/recipe-format";
import { formatMoney } from "@/lib/money";

function Reliability({ row }: { row: CostRow }) {
  const r = RELIABILITY[row.reliability];
  return <Badge status={r.status}>{r.label}</Badge>;
}

function typeLabel(type: string): string {
  return RECIPE_TYPE_LABELS[type as keyof typeof RECIPE_TYPE_LABELS] ?? type;
}

// TanStack Table v9, como las demás tablas: columnas fuera del componente.
const features = tableFeatures({});
const column = createColumnHelper<typeof features, CostRow>();

function money(value: number | null) {
  return <span className="text-ink tabular-nums">{formatMoney(value)}</span>;
}

// Lista de costos de un local. En el celular se muestra como tarjetas.
export function CostsTable({ rows, placeId }: { rows: CostRow[]; placeId: string }) {
  const NameLink = ({ row }: { row: CostRow }) => (
    <Link
      href={`/costos/${row.recipeId}?local=${placeId}`}
      className="inline-flex min-h-touch items-start py-0.5 font-medium text-primary underline-offset-4 hover:underline"
    >
      {row.name}
    </Link>
  );
  const columns = column.columns([
    column.display({
      id: "name",
      header: "Receta",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <NameLink row={row.original} />
          <span className="text-sm text-ink-muted tabular-nums">
            {row.original.code} · {typeLabel(row.original.type)}
          </span>
        </div>
      ),
    }),
    column.display({
      id: "total",
      header: "Costo sin IVA",
      cell: ({ row }) => money(row.original.total),
    }),
    column.display({
      id: "gross",
      header: "Con IVA",
      cell: ({ row }) => money(row.original.gross),
    }),
    column.display({
      id: "portion",
      header: "Por porción",
      cell: ({ row }) => money(row.original.perPortion),
    }),
    column.display({
      id: "reliability",
      header: "Confiabilidad",
      cell: ({ row }) => <Reliability row={row.original} />,
    }),
  ]);
  const table = useTable({ features, columns, data: rows });

  return (
    <>
      <ul className="flex flex-col gap-2 sm:hidden" aria-label="Costos de las recetas">
        {rows.map((row) => (
          <li
            key={row.recipeId}
            className="flex flex-col gap-1 rounded-lg border border-line bg-surface p-4"
          >
            <NameLink row={row} />
            <span className="text-sm text-ink-muted tabular-nums">
              {row.code} · {typeLabel(row.type)}
            </span>
            <span className="text-base text-ink tabular-nums">
              {row.total === null && row.gross === null
                ? "Sin costo todavía"
                : `${formatMoney(row.total)} sin IVA · ${formatMoney(row.gross)} con IVA`}
            </span>
            {row.perPortion !== null ? (
              <span className="text-sm text-ink-muted tabular-nums">
                {formatMoney(row.perPortion)} por porción
              </span>
            ) : null}
            <span>
              <Reliability row={row} />
            </span>
          </li>
        ))}
      </ul>
      {/* Con scroll propio: con la barra lateral el contenido es más angosto que la ventana (ADR-0036). */}
      <div className="hidden overflow-x-auto sm:block">
        <table className="w-full border-collapse text-left">
          <caption className="sr-only">
            Recetas del local, su costo sin IVA, con IVA, por porción y su confiabilidad
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
