import * as React from "react";
import Link from "next/link";
import { ChevronRight, ChevronsLeft } from "lucide-react";

import { PAGE_SIZES, listHref } from "@/lib/list-params";
import { cn } from "@/lib/utils";

const control =
  "inline-flex min-h-touch items-center gap-1 rounded-sm border border-line bg-surface px-3 text-sm text-ink hover:bg-line/50 desk:min-h-control-sm";

// Paginación con cursor (ADR-0036, decisión de Joaco del 2026-11-10): para listados donde la base trae "los
// siguientes N" desde el último visto, sin total (Personas, Historial). Mismo aspecto que Pagination: cuántas
// filas se ven, filas por página, "Volver al principio" y "Siguientes". Todo son enlaces que conservan los filtros.
function CursorPagination({
  size,
  shown,
  noun,
  nextPatch,
  atStart,
  cursorKeys,
  path,
  params,
  nextLabel = "Siguientes",
}: {
  size: number;
  shown: number;
  // Cómo se llaman las filas ("personas", "cambios").
  noun: string;
  // Los parámetros del cursor para la tanda siguiente, o null si no hay más.
  nextPatch: Record<string, string> | null;
  // Si se está en la primera tanda (no hace falta "Volver al principio").
  atStart: boolean;
  // Los parámetros que forman el cursor: se sacan al volver al principio o al cambiar las filas.
  cursorKeys: string[];
  path: string;
  params: Record<string, string>;
  nextLabel?: string;
}) {
  const reset = Object.fromEntries(cursorKeys.map((k) => [k, undefined]));
  const href = (patch: Record<string, string | undefined>) => listHref(path, params, patch);
  return (
    <nav
      aria-label="Páginas"
      data-slot="cursor-pagination"
      className="flex flex-col gap-3 desk:flex-row desk:items-center desk:justify-between print:hidden"
    >
      {/* Se anuncia al cambiar un filtro o la tanda: la tabla se actualiza sola (WCAG 4.1.3). */}
      <p role="status" className="text-sm text-ink-muted tabular-nums">
        {shown === 0
          ? "Sin registros"
          : `Mostrando ${shown.toLocaleString("es-AR")} ${noun}${atStart ? "" : " siguientes"}`}
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm text-ink-muted">Filas por página:</span>
        {PAGE_SIZES.map((option) => (
          <Link
            key={option}
            href={href({ ...reset, filas: option === 15 ? undefined : String(option) })}
            aria-current={option === size ? "true" : undefined}
            aria-label={`${option} filas por página`}
            className={cn(
              control,
              "tabular-nums",
              option === size && "border-primary bg-nav-active font-medium text-nav-active-ink",
            )}
          >
            {option}
          </Link>
        ))}
      </div>
      {atStart && !nextPatch ? null : (
        <div className="flex items-center gap-2">
          {atStart ? null : (
            <Link href={href(reset)} className={control}>
              <ChevronsLeft aria-hidden="true" className="size-4" />
              Volver al principio
            </Link>
          )}
          {nextPatch ? (
            <Link href={href(nextPatch)} className={control}>
              {nextLabel}
              <ChevronRight aria-hidden="true" className="size-4" />
            </Link>
          ) : null}
        </div>
      )}
    </nav>
  );
}

export { CursorPagination };
