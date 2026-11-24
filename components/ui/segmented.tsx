"use client";

import { Check } from "lucide-react";

import { SEGMENT_OPTION } from "@/components/ui/segmented-field";
import { cn } from "@/lib/utils";

// Pocas opciones como botones a la vista (ADR-0039), fuera de un formulario: el valor lo maneja quien lo usa (una ficha
// que guarda todo junto, ADR-0043). Son radios nativos en un <fieldset>: flechas del teclado y anuncio como grupo. Si
// el valor no es el guardado, el grupo lleva el borde punteado de un cambio sin guardar.
// compact: opciones de 32 px en la computadora (formularios angostos de las pantallas sin scroll, ADR-0045 y ADR-0046;
// 44 en el celular). inline: la leyenda a la izquierda, en la misma fila.
export function Segmented({
  name,
  legend,
  hideLegend = false,
  options,
  value,
  onChange,
  changed = false,
  compact = false,
  inline = false,
  labelClassName,
  describedBy,
  className,
}: {
  name: string;
  legend: string;
  hideLegend?: boolean;
  options: { value: string; label: string }[];
  value: string;
  onChange: (value: string) => void;
  changed?: boolean;
  compact?: boolean;
  inline?: boolean;
  // Ancho de la etiqueta en línea, para alinear varias filas.
  labelClassName?: string;
  // El id de su mensaje de error.
  describedBy?: string;
  className?: string;
}) {
  return (
    <fieldset
      aria-describedby={describedBy}
      className={cn(
        // El margen va siempre: al marcar el cambio, la fila no salta.
        "flex flex-col gap-1 rounded-sm border border-transparent p-1",
        changed && "border-dashed border-ink",
        className,
      )}
    >
      {/* En línea, la leyenda queda para el lector de pantalla y se ve una etiqueta en la fila (una leyenda no se
          puede poner al costado de forma confiable). */}
      <legend className={hideLegend || inline ? "sr-only" : "mb-1 text-sm font-medium text-ink"}>
        {legend}
        {changed ? <span className="sr-only"> (cambio sin guardar)</span> : null}
      </legend>
      <div className={cn("flex flex-wrap items-center", compact ? "gap-1" : "gap-2")}>
        {inline && !hideLegend ? (
          <span
            aria-hidden="true"
            className={cn("text-sm font-medium text-ink", labelClassName ?? "mr-1")}
          >
            {legend}
          </span>
        ) : null}
        {options.map((o) => (
          <label
            key={o.value}
            className={cn(SEGMENT_OPTION, compact && "desk:min-h-8 desk:px-2 desk:text-sm")}
          >
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
