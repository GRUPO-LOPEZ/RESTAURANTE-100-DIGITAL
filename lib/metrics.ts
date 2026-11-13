// Métricas confiables (ADR-0036): un indicador nunca muestra un estado positivo cuando no hay datos.
// Decide qué texto y qué estado lleva un número. Sin acceso a la base: se prueba con Vitest.

export type MetricStatus = "ok" | "warn" | "bad" | "info" | "none";

export type MetricInput = {
  // El valor a mostrar, ya formateado o como número. null = no se calculó o falta el dato.
  value: number | string | null;
  // El denominador, si el indicador es "N de total". 0 = no hay sobre qué medir.
  total?: number | null;
  // Qué se dice cuando el denominador es 0: "Sin recetas con costo calculado".
  emptyLabel: string;
  // Por qué falta el dato, si falta.
  missingReason?: string;
  // Si el dato está vencido, y desde cuándo vale (para mostrar su fecha).
  stale?: boolean;
  asOf?: string | null;
  // El estado según la regla del indicador, cuando el dato está completo y vigente.
  status: MetricStatus;
  statusLabel: string;
};

export type MetricView = {
  value: string;
  status: MetricStatus;
  statusLabel: string;
  detail: string | null;
};

const number = new Intl.NumberFormat("es-AR");

// Lo que falta de un total (decisión de Soy, 2026-11-13): una sola regla para todo el sistema (Inicio, Calidad,
// accesos y celular). Sin total no hay datos; sin faltas, completo; si falta más de la mitad, crítico; si no, atención.
export type MissingState = { status: "ok" | "warn" | "bad" | "none"; label: string };

export function missingState(missing: number, total: number): MissingState {
  if (total <= 0) return { status: "none", label: "Sin datos" };
  if (missing <= 0) return { status: "ok", label: "Completo" };
  const label = missing === 1 ? "Falta 1" : `Faltan ${number.format(missing)}`;
  return { status: missing * 2 > total ? "bad" : "warn", label };
}

export function metricView(m: MetricInput): MetricView {
  // Sin denominador no hay porcentaje ni "todo al día": no hay datos.
  if (m.total === 0) {
    return { value: "—", status: "none", statusLabel: "Sin datos", detail: m.emptyLabel };
  }
  if (m.value === null || m.value === "") {
    return {
      value: "—",
      status: "none",
      statusLabel: "Sin datos",
      detail: m.missingReason ?? "Falta el dato.",
    };
  }
  const value = typeof m.value === "number" ? number.format(m.value) : m.value;
  if (m.stale) {
    const detail = m.asOf ? `Dato del ${m.asOf}` : "Dato vencido";
    // Lo más grave primero (decisión de Joaco, 2026-11-09): un dato vencido que además es crítico dice «Crítico».
    if (m.status === "bad") return { value, status: "bad", statusLabel: "Crítico", detail };
    return { value, status: "warn", statusLabel: "Desactualizado", detail };
  }
  return { value, status: m.status, statusLabel: m.statusLabel, detail: null };
}
