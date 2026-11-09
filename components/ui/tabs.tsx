import * as React from "react";
import Link from "next/link";

import { cn } from "@/lib/utils";

// Pestañas (ADR-0036): rápidas de estado en los listados (Todas · Vigentes · Requieren atención) o secciones
// de una ficha. Son enlaces: la pestaña elegida queda en la dirección y se puede compartir o volver.
function Tabs({
  label,
  items,
  className,
}: {
  label: string;
  items: { href: string; label: string; current: boolean; count?: number }[];
  className?: string;
}) {
  return (
    <nav
      aria-label={label}
      data-slot="tabs"
      className={cn("border-b border-line print:hidden", className)}
    >
      <ul className="-mb-px flex gap-1 overflow-x-auto">
        {items.map((t) => (
          <li key={t.href}>
            <Link
              href={t.href}
              scroll={false}
              aria-current={t.current ? "page" : undefined}
              className={cn(
                "inline-flex min-h-touch items-center gap-2 border-b-2 px-3 text-sm whitespace-nowrap desk:min-h-control",
                t.current
                  ? "border-primary font-medium text-primary"
                  : "border-transparent text-ink-muted hover:text-ink",
              )}
            >
              {t.label}
              {t.count !== undefined ? (
                <span className="rounded-sm bg-none px-1.5 text-xs text-none-ink tabular-nums">
                  {t.count}
                </span>
              ) : null}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}

export { Tabs };
