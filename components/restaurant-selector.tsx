"use client";

import { useEffect, useId, useRef, useState, useSyncExternalStore, useTransition } from "react";
import { usePathname, useSearchParams } from "next/navigation";

import { setActiveRestaurantAction } from "@/app/shell-actions";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

// Selector de local (ADR-0048): lo que muestra es siempre lo que está aplicado.
// - Con el mouse o el dedo, elegir un local lo aplica.
// - Con el teclado, moverse por la lista no cambia nada: queda «Sin aplicar» hasta apretar «Aplicar».
// - Un enlace con ?local= (un aviso, el detalle de un costo) aplica ese local al llegar (decisión de Joaco, 2026-11-14), en
//   el navegador: el prefetch de un enlace no cambia nada.
// Se guarda en la base y las pantallas lo usan como filtro por defecto.
const noop = () => () => {};

export function RestaurantSelector({
  options,
  value,
}: {
  options: { id: string; label: string }[];
  value: string | null;
}) {
  // Cuando cambia lo aplicado, el selector se arma de nuevo: nunca queda una elección vieja a la vista.
  return <Selector key={value ?? ""} options={options} applied={value ?? ""} />;
}

function Selector({
  options,
  applied,
}: {
  options: { id: string; label: string }[];
  applied: string;
}) {
  // Id propio por copia: Next guarda ocultas las pantallas anteriores, cada una con su selector.
  const selectId = useId();
  const pathname = usePathname();
  const params = useSearchParams();
  const [choice, setChoice] = useState(applied);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  // Si la última vez se tocó el selector con el teclado (entonces se confirma con el botón).
  const keyboard = useRef(false);
  // Un ?local= se intenta aplicar una sola vez (si la base lo rechaza, no se insiste).
  const tried = useRef<string | null>(null);
  // En el servidor (y sin JavaScript) es falso: el botón queda siempre a la vista.
  const scripted = useSyncExternalStore(
    noop,
    () => true,
    () => false,
  );

  function apply(id: string) {
    if (pending) return;
    setError(null);
    startTransition(async () => {
      const form = new FormData();
      form.set("restaurant", id);
      const result = await setActiveRestaurantAction({}, form);
      if (result.status === "bad") setError(result.message ?? "No pudimos cambiar el local.");
    });
  }

  const requested = params.get("local");
  const known = requested !== null && options.some((o) => o.id === requested);
  useEffect(() => {
    if (!known || requested === null) return;
    if (requested === applied) {
      // Ya aplicado: la dirección deja de llevarlo, así manda el de arriba. Con la historia del navegador (Next la sincroniza
      // con useSearchParams): no navega ni pide la pantalla de nuevo, así no pisa un clic que la persona ya hizo (ordenar
      // una columna) ni deja la pestaña sin título mientras tanto. Se lee la dirección de este momento, no la del render.
      const now = new URLSearchParams(window.location.search);
      if (window.location.pathname !== pathname || now.get("local") !== requested) return;
      now.delete("local");
      window.history.replaceState(null, "", now.size ? `${pathname}?${now}` : pathname);
      return;
    }
    if (tried.current === requested) return;
    tried.current = requested;
    apply(requested);
    // apply cambia en cada render: el efecto corre solo cuando cambia la dirección o lo aplicado (tried evita repetir).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [known, requested, applied, params, pathname]);

  const unapplied = choice !== applied;
  const status = pending
    ? { status: "info" as const, label: "Aplicando…" }
    : unapplied
      ? { status: "warn" as const, label: "Sin aplicar" }
      : { status: "ok" as const, label: "Aplicado" };

  return (
    <form
      action={(form) => apply(String(form.get("restaurant") ?? ""))}
      // Para las pruebas: si ya responde (hidratado) y qué local está aplicado de verdad.
      data-ready={scripted ? "true" : "false"}
      data-applied={applied}
      className="order-last flex w-full flex-wrap items-center gap-2 desk:order-none desk:w-auto desk:flex-nowrap"
    >
      <label htmlFor={selectId} className="text-sm font-medium text-ink">
        Local
      </label>
      <select
        id={selectId}
        name="restaurant"
        aria-label="Local activo"
        value={choice}
        // No se deshabilita mientras aplica: el foco del teclado se quedaría sin lugar (WCAG 2.4.3). Se ignora el cambio.
        // Tampoco se aclara (la opacidad baja el contraste del texto): el chip dice «Aplicando…».
        aria-busy={pending}
        onPointerDown={() => {
          keyboard.current = false;
        }}
        onKeyDown={() => {
          keyboard.current = true;
        }}
        onChange={(event) => {
          if (pending) return;
          const next = event.target.value;
          setChoice(next);
          if (!keyboard.current && next !== applied) apply(next);
        }}
        className="min-h-touch min-w-0 flex-1 rounded-sm border border-line bg-surface px-2 text-base text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary aria-busy:cursor-progress desk:min-h-control desk:w-48 desk:flex-none desk:text-sm"
      >
        <option value="">Todos mis locales</option>
        {options.map((o) => (
          <option key={o.id} value={o.id}>
            {o.label}
          </option>
        ))}
      </select>
      <span role="status" aria-live="polite" className="inline-flex">
        <Badge status={status.status}>{status.label}</Badge>
      </span>
      {!scripted || unapplied ? (
        <button
          type="submit"
          aria-disabled={pending}
          className={cn(
            "min-h-touch rounded-sm border px-3 text-base font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary aria-disabled:cursor-progress desk:min-h-control desk:text-sm",
            unapplied
              ? "border-primary bg-primary text-primary-ink hover:bg-primary-hover"
              : "border-line bg-surface text-ink hover:bg-line/50",
          )}
        >
          Aplicar
        </button>
      ) : null}
      {error ? (
        <p role="alert" className="w-full text-sm text-bad-ink">
          {error}
        </p>
      ) : null}
    </form>
  );
}
