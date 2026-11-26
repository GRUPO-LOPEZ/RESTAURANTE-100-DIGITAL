"use client";

import * as React from "react";
import { Calendar } from "lucide-react";

import { dayError, dayToIso, isoToDay, maskDay } from "@/lib/dates";
import { cn } from "@/lib/utils";

// Fecha en dd/mm/aaaa (criterio 12 de Soy, ADR-0068). El campo de fecha del navegador sigue el idioma de Chrome (en
// inglés muestra 11/19/2026): este es un campo de texto que se escribe dd/mm/aaaa con las barras puestas solas, y un
// botón que abre el calendario del navegador. El valor viaja en ISO (aaaa-mm-dd) en un campo oculto con el nombre del
// formulario, así las acciones de servidor y los filtros (FilterBar lee el FormData) no cambian. Sirve sin controlar
// (name y defaultValue) y controlado (value y onChange, con el valor en ISO). Field le pone id, aria-describedby y
// aria-invalid al campo de texto.

type DateInputProps = {
  id?: string;
  name?: string;
  // En ISO (aaaa-mm-dd), o vacío.
  value?: string;
  defaultValue?: string;
  // Con la fecha en ISO, o "" si quedó vacía o no vale.
  onChange?: (iso: string) => void;
  // Al salir del campo (el formulario valida ahí: mode onTouched).
  onBlur?: () => void;
  min?: string;
  max?: string;
  required?: boolean;
  disabled?: boolean;
  className?: string;
  // Para el campo de texto: el borde punteado de «cambiado» (ADR-0039) o la altura chica de una ficha.
  inputClassName?: string;
  "aria-describedby"?: string;
  "aria-invalid"?: boolean;
  "aria-label"?: string;
  // Las fichas marcan lo obligatorio sin «required» (el navegador no frena el guardado en lote).
  "aria-required"?: "true";
};

function DateInput({
  id,
  name,
  value,
  defaultValue,
  onChange,
  onBlur,
  min,
  max,
  required,
  disabled,
  className,
  inputClassName,
  "aria-describedby": describedBy,
  "aria-invalid": invalid,
  "aria-label": ariaLabel,
  "aria-required": ariaRequired,
}: DateInputProps) {
  const controlled = value !== undefined;
  const [text, setText] = React.useState(() => isoToDay(controlled ? value : defaultValue));
  const [error, setError] = React.useState<string | null>(null);
  const picker = React.useRef<HTMLInputElement>(null);
  const autoId = React.useId();
  const errorId = `${id ?? autoId}-fecha-error`;
  // Un solo mensaje por campo: si el formulario ya marca un error (aria-invalid desde Field), no se dibuja el propio.
  const ownError = invalid ? null : error;

  const parsed = dayToIso(text);
  const iso = parsed.kind === "ok" && dayError(text, min, max) === null ? parsed.iso : "";

  // Controlado: si el valor cambia desde afuera (otro control, un reinicio), el texto lo sigue. Se ajusta al dibujar,
  // no en un efecto (https://react.dev/learn/you-might-not-need-an-effect). Si el cambio vino de lo que se escribió, el
  // valor ya es el del texto y no se toca (así no se borra una fecha a medio escribir).
  const [seen, setSeen] = React.useState(value);
  if (controlled && value !== seen) {
    setSeen(value);
    if ((value ?? "") !== iso) {
      setText(isoToDay(value));
      setError(null);
    }
  }

  function update(next: string) {
    setText(next);
    if (error) setError(dayError(next, min, max));
    const p = dayToIso(next);
    const nextIso = p.kind === "ok" && dayError(next, min, max) === null ? p.iso : "";
    onChange?.(nextIso);
  }

  function openPicker() {
    const el = picker.current;
    if (!el) return;
    el.value = iso;
    try {
      el.showPicker();
    } catch {
      // Un navegador sin showPicker: queda escribir la fecha.
    }
  }

  return (
    <span className={cn("relative flex w-full flex-col gap-1", className)}>
      <span className="relative flex w-full">
        <input
          id={id}
          type="text"
          inputMode="numeric"
          autoComplete="off"
          placeholder="dd/mm/aaaa"
          maxLength={10}
          value={text}
          required={required}
          disabled={disabled}
          aria-label={ariaLabel}
          aria-required={ariaRequired}
          aria-invalid={invalid || error ? true : undefined}
          aria-describedby={
            [describedBy, ownError ? errorId : null].filter(Boolean).join(" ") || undefined
          }
          onChange={(e) => update(maskDay(e.target.value))}
          onBlur={() => {
            setError(dayError(text, min, max));
            onBlur?.();
          }}
          // Con un error del formulario, el foco viene acá (ServerForm busca data-focus-for).
          data-focus-for={name}
          className={cn(
            "min-h-touch w-full rounded-sm border border-line bg-surface pr-12 pl-3 text-base text-ink tabular-nums placeholder:text-ink-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50 aria-invalid:border-bad-ink desk:min-h-control",
            inputClassName,
            // Después de lo de afuera: el texto nunca queda debajo del botón del calendario.
            "pr-12 desk:pr-12",
          )}
        />
        <button
          type="button"
          onClick={openPicker}
          disabled={disabled}
          aria-label="Abrir calendario"
          className="absolute top-0 right-0 inline-flex h-full min-w-touch items-center justify-center rounded-sm text-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50 desk:min-w-control"
        >
          <Calendar aria-hidden="true" className="size-4" />
        </button>
        {/* El calendario del navegador, sin nombre (no viaja en el formulario) y fuera de la vista y del Tab. */}
        <input
          ref={picker}
          type="date"
          tabIndex={-1}
          aria-hidden="true"
          min={min}
          max={max}
          className="pointer-events-none absolute bottom-0 left-0 size-px opacity-0"
          onChange={(e) => {
            if (!e.target.value) return;
            setError(null);
            update(isoToDay(e.target.value));
          }}
        />
      </span>
      {name ? <input type="hidden" name={name} value={iso} /> : null}
      {ownError ? (
        <span id={errorId} className="text-sm text-bad-ink">
          {ownError}
        </span>
      ) : null}
    </span>
  );
}

export { DateInput };
