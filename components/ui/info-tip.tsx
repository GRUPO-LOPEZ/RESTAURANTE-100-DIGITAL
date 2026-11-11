"use client";

import { Info } from "lucide-react";

import { Tooltip, TooltipProvider } from "@/components/ui/tooltip";

// Una explicación en un tooltip, junto a un título o una etiqueta (edición directa, ADR-0039): el ícono de información
// es un botón de 44 px en el celular (40 en la computadora) con nombre accesible, y el texto se abre con el mouse, el
// foco o un toque.
export function InfoTip({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <TooltipProvider>
      <Tooltip content={children}>
        <button
          type="button"
          aria-label={`Más información: ${label}`}
          className="inline-flex size-touch shrink-0 items-center justify-center rounded-sm text-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:size-control"
        >
          <Info aria-hidden="true" className="size-4" />
        </button>
      </Tooltip>
    </TooltipProvider>
  );
}
