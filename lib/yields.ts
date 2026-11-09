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
