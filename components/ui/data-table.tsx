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
  // Con scroll, cada fila va en un renglón; un nombre importante (proveedor, comprobante, materia prima) no se corta
  // con «…»: pasa a dos renglones (criterio 13 de Soy, ADR-0068). true: la columna principal, de 160 px como mínimo;
  // "narrow": una secundaria (local, rubros), de 96 px como mínimo, para que la tabla entre en 1440 con el panel.
  wrap?: boolean | "narrow";
  // Solo en la tarjeta del celular: en la computadora lo dice otra cosa de la pantalla (la pestaña «Activos»).
  desk?: "hidden";
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
  scroll = false,
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
  // Pantallas sin scroll (ADR-0048): en la computadora la tabla ocupa el alto que le dan y se desplaza adentro, con el
  // encabezado fijo. Quien la usa le da el alto (un padre flex con min-h-0). El celular sigue con tarjetas.
  scroll?: boolean;
}) {
  // Sin filas, nunca una tabla vacía: el vacío de la pantalla o uno por defecto.
  if (rows.length === 0)
    return <>{empty ?? <EmptyState title="No hay registros para mostrar." />}</>;
  const title = columns.find((c) => c.mobile === "title") ?? columns[0];
  const status = columns.filter((c) => c.mobile === "status");
  const actions = columns.filter((c) => c.mobile === "action");
  const lines = columns.filter((c) => c !== title && (c.mobile ?? "line") === "line");
  const deskColumns = columns.filter((c) => c.desk !== "hidden");

  return (
    <div
      data-slot="data-table"
      className={cn("flex flex-col", scroll && "desk:min-h-0 desk:flex-[1_1_0px] print:block")}
    >
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
      {/* Si la tabla es más ancha que el lugar, se desplaza de costado: también con el teclado (WCAG 2.1.1). */}
      <div
        role="region"
        aria-label={`${caption} (tabla)`}
        tabIndex={0}
        className={cn(
          "hidden overflow-x-auto rounded-md border border-line bg-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:block print:block",
          // relative: el título oculto de la tabla (sr-only, absoluto) no escapa del recorte ni agranda la página.
          scroll &&
            "relative desk:h-0 desk:min-h-0 desk:flex-[1_1_0px] desk:overflow-auto print:h-auto print:flex-none",
        )}
      >
        <table className="w-full border-collapse text-left">
          <caption className="sr-only">{caption}</caption>
          {/* Con border-collapse el borde de la fila no acompaña al encabezado fijo: va una línea de 1 px propia. */}
          <thead
            className={cn(
              scroll &&
                "sticky top-0 z-10 bg-app shadow-[inset_0_-1px_0_var(--color-line)] print:static",
            )}
          >
            <tr className="border-b border-line">
              {deskColumns.map((c) => (
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
                    // Un encabezado largo («Entrega esperada») pasa a dos renglones antes que agrandar la tabla.
                    scroll && "px-2 align-bottom",
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
                {deskColumns.map((c) => (
                  <td
                    key={c.key}
                    className={cn(
                      "px-4 py-2 align-top text-ink",
                      // Una fila, un renglón: así entran más filas en el alto de la pantalla.
                      scroll && "px-2 py-1.5 align-middle whitespace-nowrap",
                      // break-word y no anywhere: corta entre palabras (con anywhere la tabla achica la columna hasta
                      // partir una palabra al medio).
                      scroll && c.wrap && "[overflow-wrap:break-word] whitespace-normal",
                      scroll && (c.wrap === "narrow" ? "min-w-24" : c.wrap && "min-w-40"),
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
