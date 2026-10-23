import { UUID } from "@/lib/data";

// Filtro de local de las pantallas: si la URL no dice nada, se usa el local elegido en el
// selector; "todos" lo deja sin filtro. Solo arma el pedido: la base decide qué se ve.
export function restaurantFilter(
  param: string | undefined,
  activeId: string | null,
): { restaurantId?: string; fromSelector: boolean } {
  if (param === "todos") return { fromSelector: false };
  if (param && UUID.test(param)) return { restaurantId: param, fromSelector: false };
  return activeId ? { restaurantId: activeId, fromSelector: true } : { fromSelector: false };
}

// Una fecha AAAA-MM-DD válida, o nada.
export function dateParam(value: string | undefined): string | undefined {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  return Number.isNaN(Date.parse(`${value}T00:00:00Z`)) ? undefined : value;
}
