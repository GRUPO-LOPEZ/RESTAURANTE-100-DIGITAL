"use client";

import Link from "next/link";
import { createColumnHelper, tableFeatures, useTable } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
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

// Lista de recetas. En el celular se muestra como tarjetas.
export function RecipesTable({ rows }: { rows: RecipeRow[] }) {
  const table = useTable({ features, columns, data: rows });

  return (
    <>
      <ul className="flex flex-col gap-2 sm:hidden" aria-label="Recetas">
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
          </li>
        ))}
      </ul>
      <table className="hidden w-full border-collapse text-left sm:table">
        <caption className="sr-only">Recetas, su tipo, dónde se usan, categoría y estado</caption>
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
