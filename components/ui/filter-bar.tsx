"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { X } from "lucide-react";

import { cn } from "@/lib/utils";

// Barra de filtros (ADR-0036, pantallas tipo C): una sola línea que se aplica sola, sin botón "Filtrar".
// Los controles van como hijos, con su name: un select se aplica al cambiar; un texto, al dejar de escribir.
// Los filtros activos se ven como etiquetas que se pueden quitar. Cambiar un filtro vuelve a la página 1.
// Sin JavaScript sigue funcionando: el botón "Aplicar" queda visible solo para quien no lo tiene.
const noop = () => () => {};

function FilterBar({
  label = "Filtros",
  active = [],
  children,
  className,
}: {
  label?: string;
  // Filtros aplicados: qué dicen y a qué dirección lleva quitarlos.
  active?: { label: string; removeHref: string }[];
  children: React.ReactNode;
  className?: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const form = React.useRef<HTMLFormElement>(null);
  const timer = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  // En el servidor (y sin JavaScript) es falso: el botón "Aplicar" queda; en el navegador, se aplica solo.
  const scripted = React.useSyncExternalStore(
    noop,
    () => true,
    () => false,
  );

  const apply = React.useCallback(() => {
    if (!form.current) return;
    const next = new URLSearchParams(params);
    for (const [key, value] of new FormData(form.current).entries()) {
      if (typeof value !== "string") continue;
      if (value.trim()) next.set(key, value.trim());
      else next.delete(key);
    }
    next.delete("pagina");
    const query = next.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  }, [params, pathname, router]);

  return (
    <div data-slot="filter-bar" className={cn("flex flex-col gap-2 print:hidden", className)}>
      <form
        ref={form}
        role="search"
        aria-label={label}
        method="get"
        className="flex flex-wrap items-end gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          apply();
        }}
        onChange={(event) => {
          const target = event.target as HTMLElement;
          if (timer.current) clearTimeout(timer.current);
          // Al escribir, espera a que la persona termine. Un select espera un poco también: en Windows cada
          // flecha del teclado lo cambia, y no conviene recargar la lista en cada una.
          const typing =
            target instanceof HTMLInputElement && ["text", "search"].includes(target.type);
          timer.current = setTimeout(apply, typing ? 400 : 300);
        }}
      >
        {children}
        {scripted ? null : (
          <button
            type="submit"
            className="min-h-touch rounded-sm border border-line bg-surface px-3 text-sm text-ink desk:min-h-control"
          >
            Aplicar
          </button>
        )}
      </form>
      {active.length > 0 ? (
        <ul className="flex flex-wrap gap-2" aria-label="Filtros aplicados">
          {active.map((f) => (
            <li key={f.label}>
              <Link
                href={f.removeHref}
                scroll={false}
                className="inline-flex min-h-touch items-center gap-1 rounded-sm bg-info px-2 text-sm text-info-ink hover:underline desk:min-h-control-sm"
              >
                {f.label}
                <X aria-hidden="true" className="size-4" />
                <span className="sr-only"> (quitar filtro)</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

export { FilterBar };
