import Link from "next/link";
import { TriangleAlert } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Metric } from "@/components/ui/metric";
import type { QualityCount } from "@/lib/quality";

// Piezas de calidad de datos que comparten Inicio y Calidad (ADR-0033 y ADR-0036): la misma regla y el
// mismo aspecto en las dos pantallas.

// Una tarjeta de lo que falta (métricas confiables): sin denominador dice «Sin datos», nunca «Completo».
// Si falta algo, enlaza a la lista para corregirlo.
export function Missing({
  label,
  indicator,
  counts,
  placeId,
}: {
  label: string;
  indicator: string;
  counts: QualityCount[];
  placeId: string;
}) {
  const count = counts.find((c) => c.indicator === indicator);
  if (!count) return null;
  const missing = count.total - count.done;
  return (
    <Metric
      className="h-full"
      label={label}
      value={missing}
      total={count.total}
      emptyLabel="Todavía no hay nada que medir en este local."
      comparison={`de ${count.total}`}
      status={missing === 0 ? "ok" : "warn"}
      statusLabel={missing === 0 ? "Completo" : missing === 1 ? "Falta 1" : `Faltan ${missing}`}
      href={missing > 0 ? `/calidad/${indicator}?local=${placeId}` : undefined}
      hrefLabel="Ver cuáles"
    />
  );
}

// Requiere atención: lo pendiente, en una línea, con el botón para ir a resolverlo (si se pasa).
export function Attention({
  counts,
  action,
}: {
  counts: QualityCount[];
  action?: { href: string; label: string };
}) {
  const parts = [
    // Singular y plural: "1 precio desactualizado", "3 precios desactualizados".
    ["recipe_cost", "receta con costo por corregir", "recetas con costo por corregir"],
    ["ingredient_price", "materia prima sin precio", "materias primas sin precio"],
    ["price_stale", "precio desactualizado", "precios desactualizados"],
    ["recipe_review", "receta pendiente de revisión", "recetas pendientes de revisión"],
  ]
    .map(([key, one, many]) => {
      const c = counts.find((x) => x.indicator === key);
      const missing = c ? c.total - c.done : 0;
      return missing > 0 ? `${missing} ${missing === 1 ? one : many}` : null;
    })
    .filter((x): x is string => Boolean(x));
  if (parts.length === 0) return null;
  return (
    <div
      role="region"
      aria-label="Requiere atención"
      className="flex flex-col gap-3 rounded-md bg-warn p-4 text-warn-ink desk:flex-row desk:items-center desk:justify-between"
    >
      <p className="flex items-start gap-2 text-base">
        <TriangleAlert aria-hidden="true" className="mt-0.5 size-5 shrink-0" />
        <span>
          <span className="font-medium">Requiere atención:</span> {parts.join(" · ")}.
        </span>
      </p>
      {action ? (
        <Button asChild variant="outline" className="shrink-0">
          <Link href={action.href}>{action.label}</Link>
        </Button>
      ) : null}
    </div>
  );
}
