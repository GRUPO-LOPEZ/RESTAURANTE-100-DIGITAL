// Tablero de compras (Fase 3, Prompt 6, ADR-0060): lo que se arma en la pantalla a partir de lo que devuelve
// purchasing.purchasing_dashboard. Sin acceso a la base, para probarlo con Vitest.

export type SpendKind = "recipes" | "other" | "freight" | "perception";
export type SpendInput = { label: string; kind: SpendKind; amount: number };
export type SpendBar = { label: string; kind: SpendKind | "rest"; amount: number };

export const SPEND_KIND_LABELS: Record<SpendBar["kind"], string> = {
  recipes: "Va a recetas",
  other: "No va a recetas",
  freight: "Fletes y servicios",
  perception: "Percepciones",
  rest: "Otros rubros",
};

// Hasta 5 rubros (los que más gastaron), lo demás en «Otros rubros», y aparte fletes y percepciones. Nunca más de 7
// barras: con más, en la tarjeta no se lee ninguna.
export function spendBars(rows: SpendInput[], top = 5): SpendBar[] {
  const products = rows
    .filter((r) => r.kind === "recipes" || r.kind === "other")
    .sort((a, b) => b.amount - a.amount);
  const extras = rows.filter((r) => r.kind === "freight" || r.kind === "perception");
  const shown: SpendBar[] = products.slice(0, top);
  const rest = products.slice(top).reduce((s, r) => s + r.amount, 0);
  if (rest > 0.005) shown.push({ label: "Otros rubros", kind: "rest", amount: rest });
  return [...shown, ...extras.filter((r) => r.amount > 0.005)];
}

// Las líneas de «Cómo subieron los insumos»: una fila por fecha con el % de cada materia prima. La que no cambió de
// precio ese día queda vacía y la línea la une (connectNulls).
export type HistoryInput = {
  ingredient_id: string;
  name: string;
  points: { on: string; change_pct: number | null }[] | null;
};
export function historyRows(series: HistoryInput[]): Record<string, number | string | null>[] {
  const days = [...new Set(series.flatMap((s) => (s.points ?? []).map((p) => p.on)))].sort();
  return days.map((on) => {
    const row: Record<string, number | string | null> = { on };
    for (const s of series) {
      row[s.ingredient_id] = s.points?.find((p) => p.on === on)?.change_pct ?? null;
    }
    return row;
  });
}

// La última variación de cada materia prima (lo que dice la tabla de «Ver los números» y el texto para lectores).
export function lastChange(s: HistoryInput): number | null {
  const pts = (s.points ?? []).filter((p) => p.change_pct !== null);
  return pts.at(-1)?.change_pct ?? null;
}

// «Requiere atención»: las alarmas agrupadas por tipo, de la más grave, en palabras («2 facturas observadas»).
const ALERT_WORDS: [kind: string, one: string, many: string][] = [
  ["invoice_observed", "factura observada", "facturas observadas"],
  ["payment_overdue", "pago vencido", "pagos vencidos"],
  ["payment_due", "pago por vencer", "pagos por vencer"],
  ["order_news", "OC con novedad", "OC con novedad"],
  ["receipt_differences", "recepción con diferencias", "recepciones con diferencias"],
  ["price_list_expired", "lista vencida", "listas vencidas"],
  ["cash_to_confirm", "efectivo para confirmar", "efectivos para confirmar"],
  ["unmapped_article", "artículo sin mapear", "artículos sin mapear"],
];
export function alertParts(kinds: Record<string, number>, limit = 3): string[] {
  return ALERT_WORDS.filter(([k]) => (kinds[k] ?? 0) > 0)
    .slice(0, limit)
    .map(([k, one, many]) => {
      const n = kinds[k] ?? 0;
      return `${n.toLocaleString("es-AR")} ${n === 1 ? one : many}`;
    });
}

// Las alarmas que pide «Requiere atención»: los artículos sin mapear tienen su tarjeta, no tapan la franja.
export function urgentCount(kinds: Record<string, number>): number {
  return Object.entries(kinds)
    .filter(([k]) => k !== "unmapped_article")
    .reduce((s, [, n]) => s + n, 0);
}
