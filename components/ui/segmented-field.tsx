"use client";

import * as React from "react";
import { useFormContext } from "react-hook-form";
import { Check } from "lucide-react";

import { cn } from "@/lib/utils";

// Pocas opciones (hasta 5) como botones a la vista, no un desplegable (edición directa, ADR-0039). Son radios nativos
// dentro de un <fieldset>: se usan con el teclado (flechas) y el lector los anuncia como grupo. Registrados en el
// formulario: se validan con su esquema y muestran el error debajo.
export function SegmentedField({
  name,
  id,
  label,
  options,
  defaultValue,
  hint,
  className,
}: {
  name: string;
  id: string;
  label: string;
  options: { value: string; label: string }[];
  defaultValue?: string;
  hint?: string;
  className?: string;
}) {
  const form = useFormContext();
  const message = form?.formState.errors[name]?.message;
  const error = typeof message === "string" ? message : undefined;
  const hintId = hint ? `${id}-ayuda` : undefined;
  const errorId = error ? `${id}-error` : undefined;
  return (
    <fieldset
      className={cn("flex flex-col gap-1", className)}
      aria-describedby={[hintId, errorId].filter(Boolean).join(" ") || undefined}
    >
      <legend className="mb-1 text-sm font-medium text-ink">{label}</legend>
      <div className="flex flex-wrap gap-2">
        {options.map((o) => (
          <label
            key={o.value}
            className="inline-flex min-h-touch cursor-pointer items-center rounded-sm border border-line bg-surface px-3 text-base text-ink has-checked:border-primary has-checked:bg-nav-active has-checked:font-medium has-checked:text-nav-active-ink has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-primary desk:min-h-control"
          >
            <input
              type="radio"
              value={o.value}
              defaultChecked={o.value === defaultValue}
              className="sr-only"
              {...(form ? form.register(name) : { name })}
            />
            {/* La elegida lleva una marca, además del color. */}
            <Check aria-hidden="true" className="mr-1 hidden size-4 in-has-checked:inline" />
            {o.label}
          </label>
        ))}
      </div>
      {hint ? (
        <p id={hintId} className="text-sm text-ink-muted">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} className="text-sm text-bad-ink">
          {error}
        </p>
      ) : null}
    </fieldset>
  );
}
