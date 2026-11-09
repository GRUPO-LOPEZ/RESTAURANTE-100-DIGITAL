import * as React from "react";

import { cn } from "@/lib/utils";

// Encabezado de página (ADR-0036): título, una línea de contexto y la acción principal a la derecha.
// Mismo lugar para los botones en todo el sistema. Los títulos no compiten con los números.
function PageHeader({
  title,
  description,
  actions,
  className,
}: {
  title: string;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      data-slot="page-header"
      className={cn(
        "flex flex-col gap-3 desk:flex-row desk:items-start desk:justify-between print:hidden",
        className,
      )}
    >
      <div className="flex min-w-0 flex-col gap-1">
        <h1 className="text-2xl text-ink">{title}</h1>
        {description ? <p className="text-base text-ink-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}

export { PageHeader };
