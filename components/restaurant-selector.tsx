"use client";

import { useActionState, useEffect } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

import { setActiveRestaurantAction } from "@/app/shell-actions";
import type { ActionState } from "@/lib/auth/results";

// Selector de local: aparece solo si la persona tiene más de un local. Se elige y se confirma con
// el botón (moverse por la lista con el teclado no cambia nada). Se guarda en la base y las
// pantallas lo usan como filtro por defecto.
export function RestaurantSelector({
  options,
  value,
}: {
  options: { id: string; label: string }[];
  value: string | null;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [state, formAction, pending] = useActionState<ActionState, FormData>(
    setActiveRestaurantAction,
    {},
  );

  // Si la dirección traía un local elegido a mano, se saca: manda el del selector.
  useEffect(() => {
    if (state.status !== "ok" || !params.has("local")) return;
    const next = new URLSearchParams(params);
    next.delete("local");
    router.replace(next.size ? `${pathname}?${next}` : pathname);
  }, [state, params, pathname, router]);

  return (
    <form
      action={formAction}
      className="order-last flex w-full flex-wrap items-center gap-2 sm:order-none sm:w-auto"
    >
      <label htmlFor="local-activo" className="text-sm font-medium text-ink">
        Local
      </label>
      <select
        id="local-activo"
        name="restaurant"
        aria-label="Local activo"
        defaultValue={value ?? ""}
        className="min-h-touch min-w-0 flex-1 rounded-sm border border-line bg-surface px-2 text-base text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary sm:max-w-56 sm:flex-none"
      >
        <option value="">Todos mis locales</option>
        {options.map((o) => (
          <option key={o.id} value={o.id}>
            {o.label}
          </option>
        ))}
      </select>
      <button
        type="submit"
        disabled={pending}
        className="min-h-touch rounded-sm border border-line bg-surface px-3 text-base font-medium text-ink hover:bg-line/50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50"
      >
        {pending ? "Cambiando…" : "Cambiar"}
      </button>
      {state.status === "bad" ? (
        <p role="alert" className="w-full text-sm text-bad-ink">
          {state.message}
        </p>
      ) : null}
    </form>
  );
}
