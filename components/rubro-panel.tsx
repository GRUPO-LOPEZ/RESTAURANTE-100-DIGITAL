import Link from "next/link";
import type { ReactNode } from "react";
import { Check, ChevronDown, LayoutGrid } from "lucide-react";

import { RubroIcon } from "@/components/rubro-icon";
import { ScrollToCurrent } from "@/components/scroll-to-current";
import type { Rubro } from "@/lib/rubros";
import { cn } from "@/lib/utils";

// Panel de rubros (pedido de Soy, ADR-0066): el mismo en Materias primas y en Rubros. Desde 1.280 px, una columna fija de
// 250 px que no se mueve con la tabla (si los rubros no entran, se desplaza adentro); por debajo, una fila que se
// desliza. Son enlaces: el rubro queda en la dirección. Los vacíos van plegados, para que lo que se usa esté a mano.
const count = new Intl.NumberFormat("es-AR");

const ITEM =
  "flex min-h-touch items-center gap-2 rounded-sm border px-3 text-base whitespace-nowrap focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:min-h-control xl:min-h-control-sm xl:border-0 xl:px-2 xl:text-sm xl:whitespace-normal";
const look = (current: boolean) =>
  current
    ? "border-primary bg-nav-active font-medium text-nav-active-ink"
    : "border-line bg-surface text-ink hover:bg-line/50";
const LIST =
  // relative: los textos ocultos (sr-only, absolutos) no escapan de la fila y ensanchan la página.
  "relative flex gap-2 overflow-x-auto p-1 xl:flex-col xl:gap-0.5 xl:overflow-visible xl:p-0";

export function RubroPanel({
  label,
  rubros,
  selectedId,
  hrefFor,
  words,
  all,
  foldEmpty = true,
  empty,
}: {
  label: string;
  // Ya ordenados y filtrados.
  rubros: Rubro[];
  selectedId: string | undefined;
  hrefFor: (rubroId: string) => string;
  // Lo que se cuenta, para el lector de pantalla.
  words: { one: string; many: string };
  // «Todas», arriba (solo donde el rubro es un filtro).
  all?: { href: string; count: number };
  // Los vacíos, plegados (con una búsqueda se ven todos los que coinciden).
  foldEmpty?: boolean;
  // Qué se dice si no hay ninguno (por ejemplo, una búsqueda sin resultados).
  empty?: ReactNode;
}) {
  // El elegido no cambia de lista (el foco sigue en su enlace): si está entre los vacíos, quedan a la vista.
  const folded = foldEmpty ? rubros.filter((r) => r.uses === 0) : [];
  // Si todos están vacíos no hay nada que plegar.
  const fold = folded.length < rubros.length ? folded : [];
  const shown = rubros.filter((r) => !fold.includes(r));
  const uses = (n: number) => (
    <span className="ml-auto pl-2 tabular-nums">
      {count.format(n)}
      <span className="sr-only"> {n === 1 ? words.one : words.many}</span>
    </span>
  );
  const item = (r: Rubro) => {
    const current = r.id === selectedId;
    return (
      <li key={r.id}>
        <Link
          href={hrefFor(r.id)}
          scroll={false}
          aria-current={current ? "true" : undefined}
          className={cn(ITEM, look(current))}
        >
          <RubroIcon icon={r.icon} className="size-4 shrink-0" />
          <span className="min-w-0 [overflow-wrap:anywhere]">
            {r.name}
            {r.isActive ? null : " "}
            {r.isActive ? null : (
              <span className="rounded-sm bg-none px-1 text-xs text-none-ink">De baja</span>
            )}
          </span>
          {current ? <Check aria-hidden="true" className="size-4 shrink-0" /> : null}
          {uses(r.uses)}
        </Link>
      </li>
    );
  };
  return (
    <nav
      aria-label={label}
      className="relative flex min-w-0 flex-col gap-1 xl:min-h-0 xl:overflow-y-auto xl:rounded-md xl:border xl:border-line xl:bg-surface xl:p-2"
    >
      <ScrollToCurrent current={selectedId} />
      <ul className={LIST}>
        {all ? (
          <li>
            <Link
              href={all.href}
              scroll={false}
              aria-current={selectedId === undefined ? "true" : undefined}
              className={cn(ITEM, look(selectedId === undefined))}
            >
              <LayoutGrid aria-hidden="true" className="size-4 shrink-0" />
              Todas
              {selectedId === undefined ? (
                <Check aria-hidden="true" className="size-4 shrink-0" />
              ) : null}
              {uses(all.count)}
            </Link>
          </li>
        ) : null}
        {shown.map(item)}
      </ul>
      {rubros.length === 0 && empty ? (
        <div role="status" className="px-2 py-1 text-sm text-ink">
          {empty}
        </div>
      ) : null}
      {fold.length > 0 ? (
        <details open={fold.some((r) => r.id === selectedId)} className="group">
          <summary className="flex min-h-touch cursor-pointer list-none items-center gap-1 px-2 text-sm text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-primary desk:min-h-control xl:min-h-control-sm">
            Sin uso ({fold.length})
            <ChevronDown aria-hidden="true" className="size-4 group-open:rotate-180" />
          </summary>
          <ul className={LIST}>{fold.map(item)}</ul>
        </details>
      ) : null}
    </nav>
  );
}
