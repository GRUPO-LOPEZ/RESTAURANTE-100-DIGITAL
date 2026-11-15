"use client";

import { Tooltip, TooltipProvider } from "@/components/ui/tooltip";

// Un dato que falta en una tabla (métricas confiables, ADR-0036): «—» y el motivo en un tooltip, con el mouse, el foco o
// un toque. El motivo también va en el nombre accesible, así el lector de pantalla lo dice sin abrir nada.
export function MissingValue({ why }: { why: string }) {
  return (
    <TooltipProvider>
      <Tooltip content={why}>
        <button
          type="button"
          aria-label={`Sin dato: ${why}`}
          className="inline-flex min-h-touch min-w-6 items-center justify-end rounded-sm text-ink underline decoration-dotted underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:min-h-7"
        >
          —
        </button>
      </Tooltip>
    </TooltipProvider>
  );
}
