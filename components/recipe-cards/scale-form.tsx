"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/field";
import { cn } from "@/lib/utils";

export type ScaleUnit = { value: string; label: string };

// «Quiero hacer [12] [recetas | porciones | kg de producto]» (ADR-0065). Un formulario GET: sin JavaScript, «Calcular»
// vuelve con las cantidades; con él, navega sin recargar, y elegir la unidad ya calcula. El formulario no se vuelve a
// armar al calcular: el foco queda donde estaba.
export function ScaleForm({
  path,
  target,
  unit,
  units,
  error,
}: {
  path: string;
  target: string;
  unit: string;
  units: ScaleUnit[];
  // Lo que dice la base o la lectura del número.
  error?: string;
}) {
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const [pending, startTransition] = useTransition();
  const [value, setValue] = useState(target);
  const [shown, setShown] = useState(target);
  const [empty, setEmpty] = useState(false);
  // Otra dirección (atrás, un enlace): el campo sigue a lo calculado.
  if (shown !== target) {
    setShown(target);
    setValue(target);
  }
  const message = empty ? "Escribí cuánto querés hacer." : error;

  function go(por: string) {
    const objetivo = value.trim();
    if (objetivo === "") {
      setEmpty(true);
      input.current?.focus();
      return;
    }
    startTransition(() => {
      router.push(`${path}?${new URLSearchParams({ por, objetivo })}`, { scroll: false });
    });
  }
  return (
    <form
      method="get"
      action={path}
      noValidate
      aria-label="Cuánto querés hacer"
      className="flex flex-wrap items-center gap-3"
      onSubmit={(event) => {
        event.preventDefault();
        go(unit);
      }}
    >
      <label
        htmlFor="escalar-objetivo"
        className="text-base font-medium whitespace-nowrap text-ink"
      >
        Quiero hacer
      </label>
      <Input
        ref={input}
        id="escalar-objetivo"
        name="objetivo"
        inputMode="decimal"
        enterKeyHint="go"
        autoComplete="off"
        value={value}
        onChange={(event) => {
          setValue(event.target.value);
          setEmpty(false);
        }}
        aria-invalid={message ? true : undefined}
        aria-describedby={message ? "escalar-error" : undefined}
        className="w-28 text-center text-xl font-semibold tabular-nums"
      />
      <input type="hidden" name="por" value={unit} />
      <div role="group" aria-label="Medido en" className="flex flex-wrap gap-1.5">
        {units.map((u) => (
          <button
            key={u.value}
            type="button"
            aria-pressed={u.value === unit}
            onClick={() => go(u.value)}
            className={cn(
              "inline-flex min-h-touch items-center rounded-sm border px-3 text-base desk:min-h-control desk:text-sm",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              u.value === unit
                ? "border-primary bg-nav-active font-medium text-nav-active-ink"
                : "border-line bg-surface text-ink hover:bg-line/50",
            )}
          >
            {u.label}
          </button>
        ))}
      </div>
      <Button type="submit" className="w-full desk:w-auto" aria-busy={pending}>
        {pending ? "Calculando…" : "Calcular"}
      </Button>
      {message ? (
        <p id="escalar-error" role="alert" className="w-full text-sm text-bad-ink">
          {message}
        </p>
      ) : null}
    </form>
  );
}
