import Link from "next/link";
import { Check } from "lucide-react";

import { sharePercent, type Rubro, type RubroClass } from "@/lib/rubros";
import { cn } from "@/lib/utils";

// Listados por rubro (pedido de Soy, ADR-0041): arriba las tarjetas de los rubros, con el mismo diseño de /rubros
// (nombre, código, cantidad, % y barra), y abajo la tabla. Un clic en una tarjeta filtra la tabla; otro clic en la
// misma, o la etiqueta «✕» del filtro, lo quita. Son enlaces: el filtro queda en la dirección.

// La barra lleva el tono fuerte de su clase, como en /rubros (design.md: barras con chart-strong).
const BAR: Record<RubroClass, string> = {
  purchase: "bg-chart-strong-2",
  subrecipe: "bg-chart-strong-5",
  menu: "bg-chart-strong-6",
};

const count = new Intl.NumberFormat("es-AR");

export function RubroFilterGrid({
  label,
  rubros,
  selectedId,
  hrefFor,
  words,
}: {
  label: string;
  rubros: Rubro[];
  selectedId: string | undefined;
  // La dirección de la lista con ese rubro elegido (o sin rubro).
  hrefFor: (rubroId: string | undefined) => string;
  // «receta / recetas» o «materia prima / materias primas».
  words: { one: string; many: string };
}) {
  // El denominador del %: todo lo de la clase. Sin nada cargado no hay porcentaje (nunca «0 %»).
  const total = rubros.reduce((sum, r) => sum + r.uses, 0);
  // Los activos primero y por cantidad; los dados de baja solo si todavía tienen algo.
  const shown = rubros
    .filter((r) => r.isActive || r.uses > 0)
    .sort((a, b) =>
      a.isActive !== b.isActive
        ? a.isActive
          ? -1
          : 1
        : b.uses - a.uses || a.name.localeCompare(b.name, "es"),
    );
  if (shown.length === 0) return null;
  return (
    <ul aria-label={label} className="grid grid-cols-2 gap-3 desk:grid-cols-3 xl:grid-cols-5">
      {shown.map((r) => {
        const selected = r.id === selectedId;
        const pct = sharePercent(r.uses, total);
        return (
          <li key={r.id}>
            <Link
              href={hrefFor(selected ? undefined : r.id)}
              scroll={false}
              aria-current={selected ? "true" : undefined}
              className={cn(
                "flex min-h-22 flex-col justify-between rounded-md border px-3 py-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                selected
                  ? "border-primary bg-nav-active"
                  : r.isActive
                    ? "border-line bg-surface hover:border-primary"
                    : "border-line bg-app hover:border-primary",
              )}
            >
              <span
                className={cn(
                  "flex min-h-control-sm items-center gap-1 text-sm leading-4 font-medium [overflow-wrap:anywhere]",
                  selected ? "text-nav-active-ink" : r.isActive ? "text-ink" : "text-ink-muted",
                )}
              >
                {selected ? <Check aria-hidden="true" className="size-4 shrink-0" /> : null}
                <span className="line-clamp-2">{r.name}</span>
                {selected ? (
                  <span className="sr-only">
                    {" "}
                    (filtro aplicado; elegilo de nuevo para quitarlo)
                  </span>
                ) : null}
              </span>
              <span className="flex flex-wrap items-center justify-between gap-x-2 text-xs tabular-nums">
                <span className={selected ? "text-nav-active-ink" : "text-ink-muted"}>
                  <span className="font-medium">{r.code}</span>
                  {pct !== null && r.uses > 0 ? (
                    <>
                      {" · "}
                      <span className={selected ? undefined : "text-ink"}>{pct} %</span>
                      <span className="sr-only"> del total</span>
                    </>
                  ) : null}
                </span>
                {r.uses === 0 ? (
                  <span className="rounded-sm bg-none px-1 text-none-ink">Sin {words.many}</span>
                ) : (
                  <span className={selected ? "text-nav-active-ink" : "text-ink-muted"}>
                    {count.format(r.uses)} {r.uses === 1 ? words.one : words.many}
                  </span>
                )}
                {r.isActive ? null : (
                  <span className="rounded-sm bg-none px-1 text-none-ink">De baja</span>
                )}
              </span>
              <span
                aria-hidden="true"
                className="mb-1 block h-1 overflow-hidden rounded-sm bg-line"
              >
                {pct !== null && r.uses > 0 ? (
                  <span
                    className={cn("block h-full", BAR[r.rubroClass])}
                    style={{ width: `${pct}%` }}
                  />
                ) : null}
              </span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

// Pocas opciones a la vista (edición directa, ADR-0039), como enlaces: Platos | Preparaciones, con su cantidad.
export function SegmentedLinks({
  label,
  unit,
  items,
}: {
  label: string;
  // Lo que se cuenta, para el lector de pantalla («Platos, 12 recetas»).
  unit: string;
  items: { href: string; label: string; count: number; current: boolean }[];
}) {
  return (
    <nav aria-label={label}>
      <ul className="flex flex-wrap gap-2">
        {items.map((t) => (
          <li key={t.href}>
            <Link
              href={t.href}
              scroll={false}
              aria-current={t.current ? "page" : undefined}
              className={cn(
                "inline-flex min-h-touch items-center gap-2 rounded-sm border px-3 text-base focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:min-h-control",
                t.current
                  ? "border-primary bg-nav-active font-medium text-nav-active-ink"
                  : "border-line bg-surface text-ink hover:border-primary",
              )}
            >
              {t.current ? <Check aria-hidden="true" className="size-4" /> : null}
              {t.label}
              <span className="rounded-sm bg-none px-1 text-xs text-none-ink tabular-nums">
                <span className="sr-only">, </span>
                {count.format(t.count)}
                <span className="sr-only"> {unit}</span>
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
