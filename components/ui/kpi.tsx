import * as React from "react";
import Link from "next/link";

import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { internalHref } from "@/lib/internal-href";
import { cn } from "@/lib/utils";

// Tarjeta de KPI (ADR-0036): nombre, valor grande con números de ancho fijo, unidad, período, variación
// contra el período anterior, estado en pastel con texto (nunca solo el color) y enlace a los registros.
function Kpi({
  label,
  value,
  unit,
  period,
  status,
  statusLabel,
  detail,
  href,
  hrefLabel = "Ver detalle",
  compact = false,
  className,
}: {
  label: string;
  value: number | string;
  unit?: string;
  period?: string;
  status?: BadgeStatus;
  statusLabel?: string;
  // Variación contra el período anterior o un dato que acompaña al valor.
  detail?: string;
  // Los registros que originan el número.
  href?: string;
  hrefLabel?: string;
  // Compacta (tableros de una pantalla, ADR-0045): el dato que acompaña va al lado del número, no debajo.
  compact?: boolean;
  className?: string;
}) {
  const detailText = detail ? (
    <span className="text-sm font-normal text-ink-muted tabular-nums">{detail}</span>
  ) : null;
  return (
    <div
      data-slot="kpi"
      className={cn(
        "flex flex-col rounded-md border border-line bg-surface p-4",
        compact ? "gap-1" : "gap-2",
        className,
      )}
    >
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-sm font-medium text-ink-muted">{label}</p>
        {period ? <p className="text-xs text-ink-muted">{period}</p> : null}
      </div>
      <p className="flex flex-wrap items-baseline gap-x-2 text-kpi font-semibold text-ink tabular-nums">
        <span>
          {value}
          {unit ? <span className="ml-1 text-base font-normal text-ink-muted">{unit}</span> : null}
        </span>
        {compact ? detailText : null}
      </p>
      {detail && !compact ? <p className="text-sm text-ink-muted tabular-nums">{detail}</p> : null}
      <div
        className={cn(
          "mt-auto flex flex-wrap items-center justify-between gap-2",
          compact && "desk:min-h-8",
        )}
      >
        {status && statusLabel ? <Badge status={status}>{statusLabel}</Badge> : <span />}
        {href ? (
          <Link
            href={internalHref(href)}
            className={cn(
              "inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline",
              compact ? "desk:min-h-8" : "desk:min-h-control-sm",
            )}
          >
            {hrefLabel}
            <span className="sr-only"> ({label})</span>
          </Link>
        ) : null}
      </div>
    </div>
  );
}

// El estado vacío vive con los demás estados (components/ui/states.tsx); se reexporta por las pantallas de siempre.
export { EmptyState } from "@/components/ui/states";
export { Kpi };
