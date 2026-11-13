import * as React from "react";

import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

// Barra de avance (ADR-0036): para porcentajes en tablas y tarjetas. Siempre con el número escrito al
// lado: la barra acompaña, no reemplaza. Sin total (denominador 0), dice "Sin datos" y no dibuja 0 %.
function ProgressBar({
  value,
  total,
  label,
  decorative = false,
  className,
}: {
  value: number;
  total: number;
  // Qué mide, para lectores de pantalla ("Recetas completas").
  label: string;
  // Dentro de un enlace que ya dice el número: la barra se oculta a los lectores de pantalla, así el nombre
  // del enlace no repite todo.
  decorative?: boolean;
  className?: string;
}) {
  if (total <= 0) {
    return (
      <Badge status="none" aria-hidden={decorative || undefined} className={className}>
        Sin datos
      </Badge>
    );
  }
  const pct = Math.max(0, Math.min(100, Math.round((value / total) * 100)));
  return (
    <span
      data-slot="progress-bar"
      aria-hidden={decorative || undefined}
      className={cn("flex items-center gap-2", className)}
    >
      <span
        role={decorative ? undefined : "progressbar"}
        aria-label={decorative ? undefined : label}
        aria-valuemin={decorative ? undefined : 0}
        aria-valuemax={decorative ? undefined : 100}
        aria-valuenow={decorative ? undefined : pct}
        className="h-2 w-24 shrink-0 overflow-hidden rounded-sm bg-line"
      >
        <span className="block h-full bg-primary" style={{ width: `${pct}%` }} />
      </span>
      <span className="text-sm text-ink tabular-nums">{pct} %</span>
    </span>
  );
}

export { ProgressBar };
