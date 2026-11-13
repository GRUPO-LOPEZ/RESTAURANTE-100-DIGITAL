import * as React from "react";

import { Kpi } from "@/components/ui/kpi";
import { metricView, type MetricInput } from "@/lib/metrics";

// Métrica confiable (ADR-0036): una tarjeta de KPI que nunca muestra un estado positivo sin datos.
// La regla vive en lib/metrics.ts (con Vitest); este componente solo la dibuja.
function Metric({
  label,
  unit,
  period,
  href,
  hrefLabel,
  comparison,
  compact,
  className,
  ...input
}: MetricInput & {
  label: string;
  // Variación contra el período anterior ("+4 % contra octubre"): solo cuando el dato es confiable.
  comparison?: string;
  unit?: string;
  period?: string;
  href?: string;
  hrefLabel?: string;
  compact?: boolean;
  className?: string;
}) {
  const view = metricView(input);
  return (
    <Kpi
      label={label}
      value={view.value}
      unit={view.value === "—" ? undefined : unit}
      period={period}
      status={view.status}
      statusLabel={view.statusLabel}
      detail={view.detail ?? comparison}
      href={href}
      hrefLabel={hrefLabel}
      compact={compact}
      className={className}
    />
  );
}

export { Metric };
