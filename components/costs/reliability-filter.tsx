"use client";

import { useRouter } from "next/navigation";

import { cn } from "@/lib/utils";

export type ReliabilityOption = {
  // Vacío = todas.
  value: string;
  label: string;
  count?: number;
  // La lista con esta confiabilidad (vuelve a la página 1).
  href: string;
  current: boolean;
};

// La confiabilidad de Costos como botones a la vista (pocas opciones = botones, ADR-0039; ADR-0048), en vez de pestañas.
// Son botones de un formulario GET (?confiabilidad=): sin JavaScript la página vuelve filtrada; con él, navega sin
// recargar, como el ranking del Inicio. aria-pressed dice cuál está aplicada.
export function ReliabilityFilter({
  path,
  keep,
  options,
}: {
  path: string;
  // Lo que sigue igual al cambiar la confiabilidad: la búsqueda, el orden y las filas.
  keep: Record<string, string>;
  options: ReliabilityOption[];
}) {
  const router = useRouter();
  return (
    <form method="get" action={path} className="print:hidden">
      {Object.entries(keep).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      <div role="group" aria-label="Confiabilidad" className="flex flex-wrap gap-1.5">
        {options.map((o) => (
          <button
            key={o.value || "todas"}
            type="submit"
            name="confiabilidad"
            value={o.value}
            aria-pressed={o.current}
            onClick={(event) => {
              event.preventDefault();
              router.push(o.href, { scroll: false });
            }}
            className={cn(
              "inline-flex min-h-touch items-center gap-1.5 rounded-sm border px-3 text-sm desk:min-h-control-sm",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              o.current
                ? "border-primary bg-nav-active font-medium text-nav-active-ink"
                : "border-line bg-surface text-ink hover:bg-line/50",
            )}
          >
            {o.label}
            {o.count === undefined ? null : <span className="tabular-nums">{o.count}</span>}
          </button>
        ))}
      </div>
    </form>
  );
}
