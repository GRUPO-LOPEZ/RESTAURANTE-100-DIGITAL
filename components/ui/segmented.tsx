"use client";

import { Check } from "lucide-react";

import { SEGMENT_OPTION } from "@/components/ui/segmented-field";
import { cn } from "@/lib/utils";

// Pocas opciones como botones a la vista (ADR-0039), fuera de un formulario: el valor lo maneja quien lo usa (una ficha
// que guarda todo junto, ADR-0043). Son radios nativos en un <fieldset>: flechas del teclado y anuncio como grupo. Si
// el valor no es el guardado, el grupo lleva el borde punteado de un cambio sin guardar.
export function Segmented({
  name,
  legend,
  hideLegend = false,
  options,
  value,
  onChange,
  changed = false,
  className,
}: {
  name: string;
  legend: string;
  hideLegend?: boolean;
  options: { value: string; label: string }[];
  value: string;
  onChange: (value: string) => void;
  changed?: boolean;
  className?: string;
}) {
  return (
    <fieldset
      className={cn(
        // El margen va siempre: al marcar el cambio, la fila no salta.
        "flex flex-col gap-1 rounded-sm border border-transparent p-1",
        changed && "border-dashed border-ink",
        className,
      )}
    >
      <legend className={hideLegend ? "sr-only" : "mb-1 text-sm font-medium text-ink"}>
        {legend}
        {changed ? <span className="sr-only"> (cambio sin guardar)</span> : null}
      </legend>
      <div className="flex flex-wrap gap-2">
        {options.map((o) => (
          <label key={o.value} className={SEGMENT_OPTION}>
            <input
              type="radio"
              name={name}
              value={o.value}
              checked={o.value === value}
              onChange={() => onChange(o.value)}
              className="sr-only"
            />
            <Check
              aria-hidden="true"
              className="mr-1 hidden size-4 group-has-checked/opcion:inline"
            />
            {o.label}
          </label>
        ))}
      </div>
    </fieldset>
  );
}
