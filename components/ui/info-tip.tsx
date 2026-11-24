"use client";

import { Info } from "lucide-react";

import { Tooltip, TooltipProvider } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

// Una explicación en un tooltip, junto a un título o una etiqueta (edición directa, ADR-0039): el ícono de información
// es un botón de 44 px en el celular (40 en la computadora) con nombre accesible, y el texto se abre con el mouse, el
// foco o un toque.
// className: para achicarlo en una fila de tabla (32 px en la computadora; 44 en el celular).
export function InfoTip({
  label,
  className,
  children,
}: {
  label: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <TooltipProvider>
      <Tooltip content={children}>
        <button
          type="button"
          aria-label={`Más información: ${label}`}
          className={cn(
            "inline-flex size-touch shrink-0 items-center justify-center rounded-sm text-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:size-control",
            className,
          )}
        >
          <Info aria-hidden="true" className="size-4" />
        </button>
      </Tooltip>
    </TooltipProvider>
  );
}
