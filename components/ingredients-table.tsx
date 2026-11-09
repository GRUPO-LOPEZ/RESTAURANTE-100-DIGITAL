"use client";

import Link from "next/link";
import { createColumnHelper, tableFeatures, useTable } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import type { IngredientRow } from "@/lib/catalog";

function StatusBadge({ row }: { row: IngredientRow }) {
  return row.isActive ? <Badge status="ok">Activa</Badge> : <Badge>Desactivada</Badge>;
}

function NameLink({ row }: { row: IngredientRow }) {
  return (
    <Link
      href={`/materias-primas/${row.id}`}
      className="inline-flex min-h-touch items-start py-0.5 font-medium text-primary underline-offset-4 hover:underline"
    >
      {row.name}
    </Link>
  );
}

// TanStack Table v9, como la tabla de personas: columnas fuera del componente.
const features = tableFeatures({});
const column = createColumnHelper<typeof features, IngredientRow>();
const columns = column.columns([
  column.display({
    id: "name",
    header: "Materia prima",
    cell: ({ row }) => (
      <div className="flex flex-col">
        <NameLink row={row.original} />
        <span className="text-sm text-ink-muted tabular-nums">{row.original.code}</span>
      </div>
    ),
  }),
  column.display({
    id: "category",
    header: "Categoría",
    cell: ({ row }) => <span className="text-ink">{row.original.category}</span>,
  }),
  column.display({
    id: "unit",
    header: "Se usa en",
    cell: ({ row }) => <span className="text-ink">{row.original.unit}</span>,
  }),
  column.display({
    id: "status",
    header: "Estado",
    cell: ({ row }) => <StatusBadge row={row.original} />,
  }),
]);

// Lista de materias primas. En el celular se muestra como tarjetas.
export function IngredientsTable({ rows }: { rows: IngredientRow[] }) {
  const table = useTable({ features, columns, data: rows });

  return (
    <>
      <ul className="flex flex-col gap-2 sm:hidden" aria-label="Materias primas">
        {rows.map((row) => (
          <li
            key={row.id}
            className="flex flex-col gap-1 rounded-lg border border-line bg-surface p-4"
          >
            <div className="flex items-start justify-between gap-2">
              <NameLink row={row} />
              <StatusBadge row={row} />
            </div>
            <span className="text-sm text-ink-muted">
              {row.code} · {row.category} · se usa en {row.unit}
            </span>
          </li>
        ))}
      </ul>
      {/* Con scroll propio: con la barra lateral el contenido es más angosto que la ventana (ADR-0036). */}
      <div className="hidden overflow-x-auto sm:block">
        <table className="w-full border-collapse text-left">
          <caption className="sr-only">Materias primas, su categoría, unidad y estado</caption>
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
