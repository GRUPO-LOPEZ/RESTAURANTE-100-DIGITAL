"use client";

import { useState, type ReactNode } from "react";
import { useFormState } from "react-hook-form";
import { ChevronDown } from "lucide-react";

// «Más datos» de un formulario corto (pedido de Soy, ADR-0067): lo opcional, plegado. Si un campo de adentro tiene un
// error, se abre solo (y de nuevo en cada intento de enviar), así el error y el foco se ven. Los campos siguen en el
// formulario aunque esté cerrado.
export function MoreData({
  names,
  summary,
  children,
}: {
  // Los campos de adentro.
  names: string[];
  // Lo que va a viajar, en una línea.
  summary?: string;
  children: ReactNode;
}) {
  const { errors, submitCount } = useFormState();
  const [open, setOpen] = useState(false);
  const bad = names.some((n) => errors[n] !== undefined);
  const [seen, setSeen] = useState({ bad, submitCount });
  if (seen.bad !== bad || seen.submitCount !== submitCount) {
    setSeen({ bad, submitCount });
    if (bad) setOpen(true);
  }
  return (
    <details open={open} className="group rounded-sm border border-line">
      {/* Lo abre y lo cierra este componente (no el navegador): así un error lo puede volver a abrir. */}
      <summary
        onClick={(event) => {
          event.preventDefault();
          setOpen(!open);
        }}
        className="flex min-h-touch cursor-pointer list-none items-center justify-between gap-2 px-3 py-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <span className="flex min-w-0 flex-col">
          <span className="text-base font-medium text-primary">Más datos</span>
          {summary ? <span className="text-sm text-ink-muted">{summary}</span> : null}
        </span>
        <ChevronDown aria-hidden="true" className="size-5 shrink-0 group-open:rotate-180" />
      </summary>
      <div className="flex flex-col gap-4 p-3">{children}</div>
    </details>
  );
}
