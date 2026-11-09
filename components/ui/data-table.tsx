import * as React from "react";
import Link from "next/link";
import { ArrowDown, ArrowUp, ArrowUpDown } from "lucide-react";

import { EmptyState } from "@/components/ui/states";
import { listHref, sortPatch, type ListState } from "@/lib/list-params";
import { cn } from "@/lib/utils";

// Tabla de listados (ADR-0036, pantallas tipo C). Ancho completo, encabezados que ordenan (en el servidor,
// por la dirección: así ordena todos los registros y no solo la página), números a la derecha y tabulares.
// En el celular (menos de 800 px) pasa a tarjetas con nombre, estado y acción.
export type DataColumn<T> = {
  key: string;
  header: string;
  cell: (row: T) => React.ReactNode;
  align?: "left" | "right";
  // Si se puede ordenar por esta columna: la clave que entiende la pantalla ("nombre", "fecha"...).
  sortKey?: string;
  // En la tarjeta del celular: el título, el estado, una línea con su etiqueta, la acción (abajo), o nada.
  mobile?: "title" | "status" | "line" | "action" | "hidden";
};

function DataTable<T>({
  caption,
  columns,
  rows,
  rowKey,
  list,
  path,
  params,
  empty,
}: {
  // Nombre de la tabla para lectores de pantalla y para las pruebas ("Recetas").
  caption: string;
  columns: DataColumn<T>[];
  rows: T[];
  rowKey: (row: T) => string;
  // Orden actual y dirección de la pantalla, para los encabezados que ordenan.
  list?: ListState;
  path?: string;
  params?: Record<string, string>;
  empty?: React.ReactNode;
}) {
  // Sin filas, nunca una tabla vacía: el vacío de la pantalla o uno por defecto.
  if (rows.length === 0)
    return <>{empty ?? <EmptyState title="No hay registros para mostrar." />}</>;
  const title = columns.find((c) => c.mobile === "title") ?? columns[0];
  const status = columns.filter((c) => c.mobile === "status");
  const actions = columns.filter((c) => c.mobile === "action");
  const lines = columns.filter((c) => c !== title && (c.mobile ?? "line") === "line");

  return (
    <div data-slot="data-table" className="flex flex-col">
      <ul className="flex flex-col gap-2 desk:hidden print:hidden" aria-label={caption}>
        {rows.map((row) => (
          <li
            key={rowKey(row)}
            className="flex flex-col gap-2 rounded-md border border-line bg-surface p-4"
          >
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="min-w-0 font-medium [overflow-wrap:anywhere] text-ink">
                {title?.cell(row)}
              </div>
              {status.map((c) => (
                <div key={c.key}>{c.cell(row)}</div>
              ))}
            </div>
            {lines.length > 0 ? (
              <dl className="flex flex-col gap-1 text-sm">
                {lines.map((c) => (
                  <div key={c.key} className="flex flex-wrap justify-between gap-2">
                    <dt className="text-ink-muted">{c.header}</dt>
                    <dd className={cn("text-ink", c.align === "right" && "tabular-nums")}>
                      {c.cell(row)}
                    </dd>
                  </div>
                ))}
              </dl>
            ) : null}
            {actions.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {actions.map((c) => (
                  <div key={c.key}>{c.cell(row)}</div>
                ))}
              </div>
            ) : null}
          </li>
        ))}
      </ul>
      <div className="hidden overflow-x-auto rounded-md border border-line bg-surface desk:block print:block">
        <table className="w-full border-collapse text-left">
          <caption className="sr-only">{caption}</caption>
          <thead>
            <tr className="border-b border-line">
              {columns.map((c) => (
                <th
                  key={c.key}
                  scope="col"
                  aria-sort={
                    list && c.sortKey && list.sort === c.sortKey
                      ? list.dir === "asc"
                        ? "ascending"
                        : "descending"
                      : undefined
                  }
                  className={cn(
                    "px-4 py-2 text-sm font-medium text-ink-muted",
                    c.align === "right" ? "text-right" : "text-left",
                  )}
                >
                  {list && path && c.sortKey ? (
                    <Link
                      href={listHref(path, params ?? {}, sortPatch(list, c.sortKey))}
                      className={cn(
                        "inline-flex min-h-control-sm items-center gap-1 rounded-sm hover:text-ink",
                        c.align === "right" && "flex-row-reverse",
                      )}
                    >
                      {c.header}
                      {list.sort === c.sortKey ? (
                        list.dir === "asc" ? (
                          <ArrowUp aria-hidden="true" className="size-4" />
                        ) : (
                          <ArrowDown aria-hidden="true" className="size-4" />
                        )
                      ) : (
                        <ArrowUpDown aria-hidden="true" className="size-4 opacity-50" />
                      )}
                      <span className="sr-only">
                        {list.sort === c.sortKey
                          ? list.dir === "asc"
                            ? " (de menor a mayor; para invertir el orden)"
                            : " (de mayor a menor; para invertir el orden)"
                          : " (para ordenar por esta columna)"}
                      </span>
                    </Link>
                  ) : (
                    c.header
                  )}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={rowKey(row)} className="border-b border-line last:border-0 hover:bg-app">
                {columns.map((c) => (
                  <td
                    key={c.key}
                    className={cn(
                      "px-4 py-2 align-top text-ink",
                      c.align === "right" && "text-right tabular-nums",
                    )}
                  >
                    {c.cell(row)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export { DataTable };
