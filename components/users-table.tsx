"use client";

import Link from "next/link";
import { createColumnHelper, tableFeatures, useTable } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import type { UserRow } from "@/lib/data";

const SCOPE = { group: "Grupo", brand: "Marca", restaurant: "Local" } as const;

function name(row: UserRow) {
  return [row.first_name, row.last_name].filter(Boolean).join(" ") || row.email;
}

function StatusBadge({ row }: { row: UserRow }) {
  if (row.status === "disabled") return <Badge status="bad">Desactivada</Badge>;
  if (row.locked) return <Badge status="warn">Bloqueada</Badge>;
  return <Badge status="ok">Activa</Badge>;
}

function Roles({ row }: { row: UserRow }) {
  if (row.roles.length === 0) return <span className="text-sm text-ink-muted">Sin roles</span>;
  return (
    <ul className="flex flex-col gap-1">
      {row.roles.map((r) => (
        <li key={r.assignment_id} className="text-sm text-ink">
          {r.role_name}{" "}
          <span className="text-ink-muted">
            · {SCOPE[r.scope_type]} {r.scope_name}
          </span>
        </li>
      ))}
    </ul>
  );
}

// TanStack Table v9: solo el modelo básico de filas. Funciones y columnas fuera del componente
// para que no se recreen en cada render.
const features = tableFeatures({});
const column = createColumnHelper<typeof features, UserRow>();
const columns = column.columns([
  column.display({
    id: "person",
    header: "Persona",
    cell: ({ row }) => (
      <div className="flex flex-col">
        <Link
          href={`/usuarios/${row.original.id}`}
          className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline"
        >
          {name(row.original)}
        </Link>
        <span className="text-sm text-ink-muted">{row.original.email}</span>
      </div>
    ),
  }),
  column.display({
    id: "roles",
    header: "Roles y lugar",
    cell: ({ row }) => <Roles row={row.original} />,
  }),
  column.display({
    id: "status",
    header: "Estado",
    cell: ({ row }) => <StatusBadge row={row.original} />,
  }),
]);

// Tabla de detalle del tablero de usuarios. En el celular se muestra como lista de tarjetas.
export function UsersTable({ rows }: { rows: UserRow[] }) {
  const table = useTable({ features, columns, data: rows });

  return (
    <>
      <ul className="flex flex-col gap-2 sm:hidden" aria-label="Personas">
        {rows.map((row) => (
          <li
            key={row.id}
            className="flex flex-col gap-2 rounded-lg border border-line bg-surface p-4"
          >
            <div className="flex items-start justify-between gap-2">
              <Link
                href={`/usuarios/${row.id}`}
                className="flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline"
              >
                {name(row)}
              </Link>
              <StatusBadge row={row} />
            </div>
            <span className="text-sm break-all text-ink-muted">{row.email}</span>
            <Roles row={row} />
          </li>
        ))}
      </ul>
      <table className="hidden w-full border-collapse text-left sm:table">
        <caption className="sr-only">Personas, sus roles y su estado</caption>
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
