import * as React from "react";
import Link from "next/link";

import { cn } from "@/lib/utils";

// Tarjeta compacta de las pantallas de una sola vista (Inicio, ADR-0045; fichas sin scroll, ADR-0046): título de 16 px,
// un dato chico o una acción a la derecha, el contenido y, abajo, el enlace «Ver …». Con id, los enlaces de antes
// (#ancla) llevan el foco a la tarjeta y la marcan (FocusTarget).
export function Tile({
  title,
  titleExtra,
  aside,
  footer,
  id,
  className,
  children,
}: {
  title: string;
  // Al lado del título: un tooltip de ayuda.
  titleExtra?: React.ReactNode;
  // A la derecha del título: un dato chico («Demo Café Centro») o un estado.
  aside?: React.ReactNode;
  footer?: { href: string; label: string };
  id?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <section
      id={id}
      tabIndex={id ? -1 : undefined}
      aria-label={title}
      className={cn(
        "flex min-w-0 flex-col gap-2 rounded-md border border-line bg-surface p-4",
        id &&
          "scroll-mt-24 target:outline-2 target:outline-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        className,
      )}
    >
      <div className="flex flex-wrap items-baseline justify-between gap-x-2 gap-y-1">
        <div className="flex items-center gap-1">
          <h2 className="text-base font-semibold text-ink">{title}</h2>
          {titleExtra}
        </div>
        {typeof aside === "string" ? (
          <span className="text-xs text-ink-muted">{aside}</span>
        ) : (
          (aside ?? null)
        )}
      </div>
      {children}
      {footer ? (
        <Link
          href={footer.href}
          className="mt-auto inline-flex min-h-touch w-fit items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
        >
          {footer.label}
        </Link>
      ) : null}
    </section>
  );
}
