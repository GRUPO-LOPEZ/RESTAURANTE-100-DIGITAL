"use client";

import { Tooltip } from "@/components/ui/tooltip";

// Una celda sin dato: «—» y el motivo en un tooltip (nunca $ 0 ni una suma parcial). Es un botón para que el motivo
// también se pueda leer con el teclado; necesita un TooltipProvider arriba (la ficha lo pone una vez).
export function Missing({ reason }: { reason: string }) {
  return (
    <Tooltip content={reason}>
      <button
        type="button"
        aria-label={`Sin dato: ${reason}`}
        className="inline-flex min-h-control-sm min-w-control-sm items-center justify-end rounded-sm px-1 text-ink-muted underline decoration-dotted underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        —
      </button>
    </Tooltip>
  );
}
