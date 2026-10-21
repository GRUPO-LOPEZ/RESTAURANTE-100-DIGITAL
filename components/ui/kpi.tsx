import * as React from "react";

import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

// Tarjeta de KPI (reglas de tableros): valor grande con números de ancho fijo, una etiqueta
// y un estado en pastel con texto (nunca solo el color).
function Kpi({
  label,
  value,
  status,
  statusLabel,
  className,
}: {
  label: string;
  value: number | string;
  status?: BadgeStatus;
  statusLabel?: string;
  className?: string;
}) {
  return (
    <div
      data-slot="kpi"
      className={cn("flex flex-col gap-2 rounded-lg border border-line bg-surface p-4", className)}
    >
      <p className="text-sm font-medium text-ink-muted">{label}</p>
      <p className="text-kpi font-semibold text-ink tabular-nums">{value}</p>
      {status && statusLabel ? <Badge status={status}>{statusLabel}</Badge> : null}
    </div>
  );
}

function EmptyState({ title, children }: { title: string; children?: React.ReactNode }) {
  return (
    <div
      data-slot="empty-state"
      className="rounded-lg border border-dashed border-line bg-surface p-6 text-center"
    >
      <p className="text-base font-medium text-ink">{title}</p>
      {children ? <div className="mt-2 text-sm text-ink-muted">{children}</div> : null}
    </div>
  );
}

export { EmptyState, Kpi };
