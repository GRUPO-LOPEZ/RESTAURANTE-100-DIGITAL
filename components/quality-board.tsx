import Link from "next/link";
import { ChevronRight, TriangleAlert } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Metric } from "@/components/ui/metric";
import { missingState } from "@/lib/metrics";
import type { QualityCount } from "@/lib/quality";

// Piezas de calidad de datos que comparten Inicio y Calidad (ADR-0033 y ADR-0036): la misma regla y el
// mismo aspecto en las dos pantallas.

// Una tarjeta de lo que falta (métricas confiables): sin denominador dice «Sin datos», nunca «Completo».
// El color sale de la regla única (lib/metrics.ts, decisión de Soy del 2026-11-13): si falta más de la mitad, Crítico.
// Si falta algo, enlaza a la lista para corregirlo.
export function Missing({
  label,
  indicator,
  counts,
  placeId,
  compact,
  className,
}: {
  label: string;
  indicator: string;
  counts: QualityCount[];
  placeId: string;
  compact?: boolean;
  className?: string;
}) {
  const count = counts.find((c) => c.indicator === indicator);
  if (!count) return null;
  const missing = count.total - count.done;
  const state = missingState(missing, count.total);
  return (
    <Metric
      className={className ?? "h-full"}
      label={label}
      value={missing}
      total={count.total}
      emptyLabel="Todavía no hay nada que medir en este local."
      comparison={`de ${count.total}`}
      status={state.status}
      statusLabel={state.label}
      href={missing > 0 ? `/calidad/${indicator}?local=${placeId}` : undefined}
      hrefLabel="Ver cuáles"
      compact={compact}
    />
  );
}

// Lo pendiente, en palabras: "4 recetas con costo por corregir · 3 materias primas sin precio".
export function attentionParts(counts: QualityCount[]): string[] {
  return [
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
}

// Requiere atención: lo pendiente, en una línea, con el botón para ir a resolverlo (si se pasa).
export function Attention({
  counts,
  action,
}: {
  counts: QualityCount[];
  action?: { href: string; label: string };
}) {
  const parts = attentionParts(counts);
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

// La franja compacta del Inicio (ADR-0045): una sola línea de 44 px que lleva a lo que falta corregir. Las partes ya
// vienen armadas (calidad, revisiones y recálculo) para que nada agregue otra fila.
export function AttentionStrip({ parts, href }: { parts: string[]; href: string }) {
  if (parts.length === 0) return null;
  return (
    <div role="region" aria-label="Requiere atención">
      <Link
        href={href}
        title={`Requiere atención: ${parts.join(" · ")}.`}
        className="flex min-h-touch items-center gap-2 rounded-md bg-warn px-4 py-2 text-sm text-warn-ink underline-offset-4 hover:underline"
      >
        <TriangleAlert aria-hidden="true" className="size-5 shrink-0" />
        <span className="min-w-0 flex-1 desk:truncate">
          <span className="font-medium">Requiere atención:</span> {parts.join(" · ")}.
        </span>
        <ChevronRight aria-hidden="true" className="size-5 shrink-0" />
      </Link>
    </div>
  );
}
