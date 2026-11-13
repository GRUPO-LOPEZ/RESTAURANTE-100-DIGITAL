"use client";

import * as React from "react";
import { useFormContext } from "react-hook-form";
import { Check, X } from "lucide-react";

import { cn } from "@/lib/utils";

// Sí o no de un clic dentro de un formulario (edición directa, ADR-0039). Es un <button> con aria-pressed que cambia
// un campo del formulario ("true" o "false"): lo que se guarda lo decide el botón Guardar de ese formulario, con su
// motivo. Cuando el valor ya no es el original, el borde queda punteado, como en la matriz de permisos.
// Con value y onChange es controlado: lo usa una ficha que guarda todo junto (ficha de materia prima, ADR-0043).
export function ToggleField({
  name,
  id,
  label,
  defaultValue,
  yesLabel = "Sí",
  noLabel = "No",
  className,
  value,
  onChange,
  disabled,
}: {
  name: string;
  id: string;
  label: string;
  defaultValue: boolean;
  yesLabel?: string;
  noLabel?: string;
  className?: string;
  value?: boolean;
  onChange?: (value: boolean) => void;
  disabled?: boolean;
}) {
  // Fuera de un formulario no hay nada que avisar: solo el campo oculto.
  const form = useFormContext() as ReturnType<typeof useFormContext> | null;
  const [own, setOwn] = React.useState(defaultValue);
  const on = value ?? own;
  // Al guardar, la página vuelve con el valor nuevo: quien lo usa le pone key={String(valor)}, así el original se
  // vuelve a tomar. El formulario valida con su copia (setValue); lo que se envía es el campo oculto, que siempre
  // tiene lo que se ve.
  React.useEffect(() => {
    form?.register(name);
    form?.setValue(name, defaultValue ? "true" : "false");
  }, [form, name, defaultValue]);
  const changed = on !== defaultValue;
  return (
    <div className={cn("flex flex-wrap items-center gap-3", className)}>
      <span id={`${id}-etiqueta`} className="text-sm font-medium text-ink">
        {label}
      </span>
      <button
        id={id}
        type="button"
        aria-pressed={on}
        // Nombre fijo (la pregunta); el estado lo anuncia aria-pressed, como en la matriz de permisos (APG).
        aria-labelledby={`${id}-etiqueta`}
        aria-describedby={changed ? `${id}-cambio` : undefined}
        disabled={disabled}
        onClick={() => {
          setOwn(!on);
          onChange?.(!on);
          form?.setValue(name, on ? "false" : "true", { shouldDirty: true });
        }}
        className={cn(
          "inline-flex size-touch items-center justify-center rounded-sm border-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed desk:size-control",
          on ? "border-ok bg-ok text-ok-ink" : "border-line bg-none text-none-ink",
          changed && "border-dashed border-ink",
        )}
      >
        {/* Adentro, solo el ícono: el nombre del botón es la pregunta (si el texto cambiara adentro, el nombre no
            coincidiría con lo que se ve). La palabra va al lado. */}
        {on ? (
          <Check aria-hidden="true" className="size-4" />
        ) : (
          <X aria-hidden="true" className="size-4" />
        )}
      </button>
      <span aria-hidden="true" className="text-base font-medium text-ink">
        {on ? yesLabel : noLabel}
      </span>
      {changed ? (
        <span id={`${id}-cambio`} className="sr-only">
          Cambio sin guardar
        </span>
      ) : null}
      <input type="hidden" name={name} value={on ? "true" : "false"} readOnly />
    </div>
  );
}
