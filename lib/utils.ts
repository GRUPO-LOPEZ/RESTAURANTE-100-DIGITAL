import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// tailwind-merge tiene que conocer los tamaños propios de app/globals.css;
// si no, toma "text-kpi" por un color y lo descarta al combinarlo con "text-ink".
const twMerge = extendTailwindMerge({
  extend: {
    theme: {
      text: ["kpi"],
      // Alturas y anchos propios (ADR-0036): sin esto, "min-h-touch" y "desk:min-h-control-sm" no se reconocen
      // como la misma propiedad y quedan las dos clases.
      spacing: [
        "touch",
        "control",
        "control-sm",
        "sidebar",
        "sidebar-collapsed",
        "topbar",
        "gutter",
        "gutter-wide",
      ],
    },
  },
});

/** Combina clases de Tailwind resolviendo conflictos (la última gana). */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
