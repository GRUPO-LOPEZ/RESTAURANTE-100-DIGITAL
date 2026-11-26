import * as React from "react";
import Link from "next/link";
import type { LucideIcon } from "lucide-react";

import { ScrollFocus } from "@/components/ui/scroll-focus";
import { panelGroups, type GroupItem } from "@/lib/group-counts";
import { cn } from "@/lib/utils";

// Listados con panel izquierdo (criterio 7 de Soy, ADR-0068): a la izquierda, un panel fijo de 250 px con la agrupación
// (proveedores o rubros), cada uno con su ícono, su nombre completo y su cantidad; a la derecha, la tabla con su propio
// scroll. El panel no se desplaza con la página: si los grupos no entran, se desplazan adentro (y se recorren con Tab).
// Son enlaces: el filtro queda en la dirección, y la etiqueta «✕» de los filtros lo quita. En el celular no va: queda
// el filtro de arriba.

const count = new Intl.NumberFormat("es-AR");

export function GroupPanel({
  label,
  icon: Icon,
  allLabel,
  allCount,
  items,
  selected,
  hrefFor,
  unit,
}: {
  // «Proveedores», «Rubros»: el título del panel y el nombre de su navegación.
  label: string;
  icon: LucideIcon;
  // «Todos los proveedores».
  allLabel: string;
  // El total sin el filtro del grupo (si se sabe; si no, «Todos» va sin número).
  allCount?: number;
  items: GroupItem[];
  // El grupo elegido ahora (con su nombre, por si con los filtros de ahora no tiene nada).
  selected?: { id: string; name: string };
  // La dirección de la lista con ese grupo elegido (o sin grupo).
  hrefFor: (id: string | undefined) => string;
  // Qué se cuenta, para el lector de pantalla: «Lácteos Demo, 2 facturas».
  unit: { one: string; many: string };
}) {
  const groups = panelGroups(items, selected);
  return (
    <nav
      aria-label={label}
      className="relative hidden w-group-panel shrink-0 flex-col gap-1 rounded-md border border-line bg-surface p-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:flex desk:min-h-0 desk:overflow-y-auto print:hidden"
    >
      <ScrollFocus />
      <h2 className="px-2 py-1 text-sm font-medium text-ink-muted">{label}</h2>
      <ul className="flex flex-col gap-0.5">
        <li>
          <PanelLink
            href={hrefFor(undefined)}
            current={!selected}
            icon={Icon}
            name={allLabel}
            value={allCount}
            unit={unit}
          />
        </li>
        {groups.map((g) => (
          <li key={g.id}>
            <PanelLink
              href={hrefFor(g.id)}
              current={selected?.id === g.id}
              icon={Icon}
              name={g.name}
              value={g.count}
              unit={unit}
            />
          </li>
        ))}
      </ul>
    </nav>
  );
}

function PanelLink({
  href,
  current,
  icon: Icon,
  name,
  value,
  unit,
}: {
  href: string;
  current: boolean;
  icon: LucideIcon;
  name: string;
  value?: number;
  unit: { one: string; many: string };
}) {
  return (
    <Link
      href={href}
      // «true» y no «page»: la barra lateral ya marca la pantalla; esto es un filtro dentro de ella.
      aria-current={current ? "true" : undefined}
      className={cn(
        "flex min-h-control-sm items-center gap-2 rounded-sm px-2 py-1 text-sm text-ink hover:bg-line/50",
        current && "bg-nav-active font-medium text-nav-active-ink hover:bg-nav-active",
      )}
    >
      <Icon aria-hidden="true" className="size-4 shrink-0" />
      {/* El nombre entero, en dos renglones si hace falta: nunca «…» (criterio 13). */}
      <span className="min-w-0 flex-1 [overflow-wrap:anywhere]">{name}</span>
      {value === undefined ? null : (
        // El lector oye «(2 facturas)»; a la vista, el número solo. Entre paréntesis: no se confunde con el título de la
        // tabla («2 facturas»).
        <span className="shrink-0 tabular-nums">
          <span aria-hidden="true">{count.format(value)}</span>
          <span className="sr-only">
            {` (${count.format(value)} ${value === 1 ? unit.one : unit.many})`}
          </span>
        </span>
      )}
    </Link>
  );
}

// La disposición: el panel a la izquierda y, a la derecha, lo que va con la tabla. En la computadora ocupa el alto que
// queda (AppShell fill) y cada eslabón lleva min-h-0 y base 0px, como Costos (ADR-0048).
export function GroupLayout({
  panel,
  children,
}: {
  panel: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:flex-row">
      {panel}
      <div className="flex min-w-0 flex-col gap-4 desk:min-h-0 desk:flex-[1_1_0px]">{children}</div>
    </div>
  );
}
