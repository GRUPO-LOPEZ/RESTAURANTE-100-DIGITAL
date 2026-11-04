"use client";

import { createColumnHelper, tableFeatures, useTable } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import {
  SCENARIO_RELIABILITY,
  formatDifference,
  formatMoneyDifference,
  type ScenarioRow,
} from "@/lib/cost-labels";
import { formatMoney } from "@/lib/money";

const features = tableFeatures({});
const column = createColumnHelper<typeof features, ScenarioRow>();

function money(value: number | null) {
  return <span className="text-ink tabular-nums">{formatMoney(value)}</span>;
}

function Reliability({ row }: { row: ScenarioRow }) {
  const r = SCENARIO_RELIABILITY[row.reliability];
  return <Badge status={r.status}>{r.label}</Badge>;
}

const columns = column.columns([
  column.display({
    id: "recipe",
    header: "Receta",
    cell: ({ row }) => <span className="font-medium text-ink">{row.original.recipe}</span>,
  }),
  column.display({ id: "today", header: "Hoy", cell: ({ row }) => money(row.original.today) }),
  column.display({
    id: "simulated",
    header: "Simulado",
    cell: ({ row }) => money(row.original.simulated),
  }),
  column.display({
    id: "difference",
    header: "Diferencia",
    cell: ({ row }) => (
      <span className="text-ink tabular-nums">
        {formatMoneyDifference(row.original.difference)} (
        {formatDifference(row.original.differencePct)})
      </span>
    ),
  }),
  column.display({
    id: "portion",
    header: "Por porción, simulado",
    cell: ({ row }) => money(row.original.portionSimulated),
  }),
  column.display({
    id: "reliability",
    header: "Datos de la simulación",
    cell: ({ row }) => <Reliability row={row.original} />,
  }),
]);

// El resultado de un escenario. Hasta lg se muestra como tarjetas: seis columnas no entran.
export function ScenarioTable({ rows }: { rows: ScenarioRow[] }) {
  const table = useTable({ features, columns, data: rows });

  return (
    <>
      <ul className="flex flex-col gap-2 lg:hidden" aria-label="Recetas alcanzadas">
        {rows.map((row) => (
          <li
            key={row.recipeId}
            className="flex flex-col gap-1 rounded-lg border border-line bg-surface p-4"
          >
            <span className="font-medium text-ink">{row.recipe}</span>
            <span className="text-base text-ink tabular-nums">
              {formatMoney(row.today)} hoy · {formatMoney(row.simulated)} simulado
            </span>
            <span className="text-base text-ink tabular-nums">
              {row.difference === null
                ? "Sin diferencia: falta un costo"
                : `Diferencia: ${formatMoneyDifference(row.difference)} (${formatDifference(row.differencePct)})`}
            </span>
            {row.portionSimulated !== null ? (
              <span className="text-sm text-ink-muted tabular-nums">
                {formatMoney(row.portionSimulated)} por porción, simulado
              </span>
            ) : null}
            <span>
              <Reliability row={row} />
            </span>
          </li>
        ))}
      </ul>
      <table className="hidden w-full border-collapse text-left lg:table">
        <caption className="sr-only">
          Recetas alcanzadas: costo de hoy, costo simulado, diferencia, costo simulado por porción y
          datos de la simulación
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
    </>
  );
}
