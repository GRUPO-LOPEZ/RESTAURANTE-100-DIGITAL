// Estado de la constancia de inscripción de ARCA de una razón social (ADR-0061). La misma regla está en la base
// (org.document_status): Al día si se emitió hace 12 meses o menos, Vencida (Atención) si hace más, Sin constancia si
// no hay ninguna. ARCA no les pone vencimiento: es una regla nuestra para que se actualicen una vez por año.

export type DocumentStatus = "current" | "stale" | "missing";

export const DOCUMENT_STATUS_LABEL: Record<DocumentStatus, string> = {
  current: "Al día",
  stale: "Vencida",
  missing: "Sin constancia",
};

/** El estado de una constancia según su fecha de emisión (AAAA-MM-DD) y el día de hoy en la Argentina. */
export function documentStatus(issuedOn: string | null, today: string): DocumentStatus {
  if (!issuedOn) return "missing";
  const [y = 0, m = 1, d = 1] = today.split("-").map(Number);
  // Hace 12 meses, con el mismo criterio que Postgres (31/03 menos un año da 31/03; 29/02 da 28/02).
  const lastDay = new Date(Date.UTC(y - 1, m, 0)).getUTCDate();
  const limit = `${y - 1}-${String(m).padStart(2, "0")}-${String(Math.min(d, lastDay)).padStart(2, "0")}`;
  return issuedOn >= limit ? "current" : "stale";
}
