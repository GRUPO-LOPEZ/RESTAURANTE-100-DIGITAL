// Cómo se muestran los rendimientos (documento de Soy, sección 9). Sin acceso a la base: se prueban
// con Vitest. Los rendimientos se guardan con 4 decimales y se muestran en % con 1 decimal.

const oneDecimal = new Intl.NumberFormat("es-AR", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});
const factor = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 2 });

// El % se arma a mano: el formato de porcentaje de Intl cambia entre Node y los navegadores (con
// o sin espacio). Siempre "80,0 %", como en el documento de Soy.
function percent(value: number): string {
  return `${oneDecimal.format(value * 100)} %`;
}

// Limpieza: 0,8 → "80,0 %".
export function formatCleaning(value: number): string {
  return percent(value);
}

// Cocción: si pierde peso es merma; si gana (pasta, arroz), es expansión. Nunca "merma negativa".
export function describeCooking(value: number): string {
  if (value === 1) return "sin cambio en la cocción";
  if (value < 1) return `merma de cocción ${percent(1 - value)}`;
  return `se expande ×${factor.format(value)}`;
}

// Lo que dio un ensayo, con los pesos en gramos. Vacío si falta el par.
export function measuredCleaning(gross?: number, clean?: number): number | undefined {
  return gross && clean && gross > 0 ? clean / gross : undefined;
}
export function measuredCooking(before?: number, after?: number): number | undefined {
  return before && after && before > 0 ? after / before : undefined;
}

// Desvío relativo contra el estándar, en %: 0,68 contra 0,80 es −15. Es el que usa el aviso de rendimiento
// (ADR-0035), igual que catalog.yield_deviation en la base.
export function yieldDeviationPct(measured: number, standard: number): number {
  return (measured / standard - 1) * 100;
}

// Si un desvío pasa el umbral. Justo en el umbral no avisa ("más que el umbral").
export function exceedsYieldAlert(
  measured: number,
  standard: number,
  thresholdPct: number,
): boolean {
  return Math.abs(yieldDeviationPct(measured, standard)) > thresholdPct + 1e-9;
}

// Diferencia del promedio de ensayos contra el estándar, dicha para la cocina:
// "3,0 puntos menos que el estándar", "1,5 puntos más que el estándar" o "igual al estándar".
export function cleaningDifference(measured: number, standard: number): string {
  const points = Math.round((measured - standard) * 1000) / 10;
  if (points === 0) return "igual al estándar";
  const amount = `${oneDecimal.format(Math.abs(points))} ${Math.abs(points) === 1 ? "punto" : "puntos"}`;
  return `${amount} ${points > 0 ? "más" : "menos"} que el estándar`;
}

// Texto con coma o punto decimal ("78,5" o "78.5") → número, como en las acciones del catálogo.
// Sin separador de miles: el formulario los rechaza antes (positiveNumber).
export function parseDecimal(value: string): number {
  return Number(value.trim().replace(",", "."));
}

// ---------------------------------------------------------------------------
// Mermas en % y rendimiento neto (ADR-0040)
// ---------------------------------------------------------------------------
// Una merma escrita en % ("12,5") → entre 0 y 1. Vacío → null (no se cargó). Inválida → NaN.
export function parseLossPercent(text: string | null | undefined): number | null {
  const value = (text ?? "").trim();
  if (value === "") return null;
  if (!/^[0-9]{1,2}([.,][0-9]{1,2})?$/.test(value)) return Number.NaN;
  return Number(value.replace(",", ".")) / 100;
}

// Merma de un rendimiento (0,8 → "20,0 %").
export function formatLoss(yieldValue: number): string {
  return percent(1 - yieldValue);
}

export type NetYield = { value: number | null; missing: string | null };

// El rendimiento neto que usa el costo: limpieza × descongelado (si se compra congelada), con 4 decimales como la base
// (catalog.costing_yield). Nunca supone: sin la limpieza aprobada, o congelada sin el descongelado, falta el dato.
export function netYield(input: {
  cleaning: number | null;
  thawing: number | null;
  requiresThawing: boolean;
}): NetYield {
  if (input.cleaning === null) return { value: null, missing: "Falta la merma de limpieza." };
  if (input.requiresThawing && input.thawing === null)
    return { value: null, missing: "Falta la merma de descongelado." };
  if (!input.requiresThawing) return { value: input.cleaning, missing: null };
  // En diezmilésimos enteros, como round(…, 4) de la base: con decimales de coma flotante, los empates redondean
  // distinto (0,5035 × 0,9).
  const a = Math.round(input.cleaning * 10000);
  const b = Math.round((input.thawing ?? 1) * 10000);
  return { value: Math.round((a * b) / 10000) / 10000, missing: null };
}

// La vista previa del formulario de mermas: con lo que se escribe y, si falta, lo que ya está aprobado.
export function previewNetYield(input: {
  cleaningLoss: string;
  thawingLoss: string;
  requiresThawing: boolean;
  approvedCleaning: number | null;
  approvedThawing: number | null;
}): NetYield {
  const cleaning = parseLossPercent(input.cleaningLoss);
  const thawing = parseLossPercent(input.thawingLoss);
  if (Number.isNaN(cleaning) || Number.isNaN(thawing))
    return { value: null, missing: "Revisá los porcentajes." };
  return netYield({
    cleaning: cleaning === null ? input.approvedCleaning : 1 - cleaning,
    thawing: thawing === null ? input.approvedThawing : 1 - thawing,
    requiresThawing: input.requiresThawing,
  });
}

// "Rinde 72,0 % neto".
export function formatNetYield(value: number): string {
  return `Rinde ${percent(value)} neto`;
}
