"use client";

import { Tooltip } from "@/components/ui/tooltip";

// Una celda sin dato: «—» y el motivo en un tooltip (nunca $ 0 ni una suma parcial). Es un botón para que el motivo
// también se pueda leer con el teclado; necesita un TooltipProvider arriba (la ficha lo pone una vez).
// `compact`: 24 px (el mínimo de WCAG 2.5.8), para las celdas de la planilla con dos renglones (peso y costo).
export function Missing({ reason, compact = false }: { reason: string; compact?: boolean }) {
  return (
    <Tooltip content={reason}>
      <button
        type="button"
        aria-label={`Sin dato: ${reason}`}
        // text-ink: el «—» también va sobre fondos pastel (la fila marcada para quien revisa, el total), donde el gris
        // no llega a 4,5:1. La línea punteada dice que tiene un motivo.
        className={`inline-flex items-center justify-end rounded-sm px-1 text-ink underline decoration-dotted underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary ${compact ? "min-h-6 min-w-6" : "min-h-control-sm min-w-control-sm"}`}
      >
        —
      </button>
    </Tooltip>
  );
}
