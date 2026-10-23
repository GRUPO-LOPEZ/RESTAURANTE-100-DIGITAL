"use client";

import * as React from "react";
import { useEffect, useRef } from "react";
import { SlidersHorizontal } from "lucide-react";

// Filtros de una pantalla. En el celular empiezan plegados (el contenido queda a la vista) y el
// título resume los activos; desde 640 px se abren solos, como "filtros fijos arriba".
export function FiltersPanel({
  active,
  children,
}: {
  active: string[];
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    if (ref.current && window.matchMedia("(min-width: 640px)").matches) ref.current.open = true;
  }, []);
  return (
    <details ref={ref} className="rounded-lg border border-line bg-surface">
      <summary className="flex min-h-touch cursor-pointer flex-wrap items-center gap-2 px-4 py-2 text-base font-medium text-ink">
        <SlidersHorizontal aria-hidden="true" className="size-5" />
        Filtros
        <span className="text-sm font-normal text-ink-muted">
          {active.length > 0 ? `· ${active.join(" · ")}` : "· Sin filtros"}
        </span>
      </summary>
      <div className="border-t border-line p-4 sm:p-6">{children}</div>
    </details>
  );
}
