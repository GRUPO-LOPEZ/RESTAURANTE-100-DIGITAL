import * as React from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight } from "lucide-react";

import { PAGE_SIZES, listHref, pageCount, rangeLabel, type ListState } from "@/lib/list-params";
import { cn } from "@/lib/utils";

const control =
  "inline-flex min-h-touch items-center gap-1 rounded-sm border border-line bg-surface px-3 text-sm text-ink hover:bg-line/50 desk:min-h-control-sm";

// Paginación (ADR-0036): total de registros, página actual, anterior y siguiente, y filas por página
// (10, 15, 25, 50). Sin scroll infinito. Todo son enlaces: conserva los filtros de la dirección.
function Pagination({
  list,
  total,
  shown,
  path,
  params,
}: {
  list: ListState;
  total: number;
  shown: number;
  path: string;
  params: Record<string, string>;
}) {
  const pages = pageCount(total, list.size);
  const href = (patch: Record<string, string | undefined>) => listHref(path, params, patch);
  return (
    <nav
      aria-label="Páginas"
      data-slot="pagination"
      className="flex flex-col gap-3 desk:flex-row desk:items-center desk:justify-between print:hidden"
    >
      {/* Se anuncia al cambiar un filtro o la página: la tabla se actualiza sola (WCAG 4.1.3). */}
      <p role="status" className="text-sm text-ink-muted tabular-nums">
        {rangeLabel(list, total, shown)}
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm text-ink-muted">Filas por página:</span>
        {PAGE_SIZES.map((size) => (
          <Link
            key={size}
            href={href({ filas: size === 15 ? undefined : String(size), pagina: undefined })}
            aria-current={size === list.size ? "true" : undefined}
            aria-label={`${size} filas por página`}
            className={cn(
              control,
              "tabular-nums",
              size === list.size && "border-primary bg-nav-active font-medium text-nav-active-ink",
            )}
          >
            {size}
          </Link>
        ))}
      </div>
      {pages > 1 ? (
        <div className="flex items-center gap-2">
          {/* En la primera y la última página quedan desactivados: los botones no cambian de lugar. */}
          {list.page > 1 ? (
            <Link
              href={href({ pagina: list.page === 2 ? undefined : String(list.page - 1) })}
              className={control}
            >
              <ChevronLeft aria-hidden="true" className="size-4" />
              Anterior
            </Link>
          ) : (
            <span aria-disabled="true" className={cn(control, "opacity-50")}>
              <ChevronLeft aria-hidden="true" className="size-4" />
              Anterior
            </span>
          )}
          <span className="text-sm text-ink tabular-nums">
            Página {list.page} de {pages}
          </span>
          {list.page < pages ? (
            <Link href={href({ pagina: String(list.page + 1) })} className={control}>
              Siguiente
              <ChevronRight aria-hidden="true" className="size-4" />
            </Link>
          ) : (
            <span aria-disabled="true" className={cn(control, "opacity-50")}>
              Siguiente
              <ChevronRight aria-hidden="true" className="size-4" />
            </span>
          )}
        </div>
      ) : null}
    </nav>
  );
}

export { Pagination };
