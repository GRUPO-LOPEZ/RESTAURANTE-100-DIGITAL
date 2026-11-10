// Listados (ADR-0036, pantallas tipo C): página, filas por página y orden viajan en la dirección, así el
// detalle vuelve "sin perder filtros ni página" y el orden lo hace el servidor sobre todos los registros
// (ordenar en el navegador ordenaría solo la página visible). Sin acceso a la base: se prueba con Vitest.

export const PAGE_SIZES = [10, 15, 25, 50] as const;
export const DEFAULT_PAGE_SIZE = 15;

export type SortDir = "asc" | "desc";
export type ListState = { page: number; size: number; sort: string | null; dir: SortDir };
type Params = Record<string, string | string[] | undefined>;

function one(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

// "pagina" empieza en 1 en la dirección; "filas" es una de PAGE_SIZES; "orden" es "nombre" o "-nombre".
// Lo que no se entiende vuelve al valor por defecto (un enlace viejo no rompe la pantalla).
export function parseList(
  params: Params,
  sortKeys: readonly string[],
  defaultSort: string | null = null,
): ListState {
  const page = Number.parseInt(one(params.pagina) ?? "1", 10);
  const size = Number.parseInt(one(params.filas) ?? "", 10);
  const raw = one(params.orden) ?? "";
  const dir: SortDir = raw.startsWith("-") ? "desc" : "asc";
  const key = raw.replace(/^-/, "");
  const fallback = defaultSort?.replace(/^-/, "") ?? null;
  return {
    page: Number.isFinite(page) && page >= 1 ? Math.min(page, 1_000) : 1,
    size: (PAGE_SIZES as readonly number[]).includes(size) ? size : DEFAULT_PAGE_SIZE,
    sort: sortKeys.includes(key) ? key : fallback,
    dir: sortKeys.includes(key) ? dir : defaultSort?.startsWith("-") ? "desc" : "asc",
  };
}

// La dirección de la misma pantalla con algunos parámetros cambiados (undefined o "" los saca).
export function listHref(
  path: string,
  params: Record<string, string | undefined>,
  patch: Record<string, string | undefined>,
): string {
  // Solo rutas internas: nunca "//otro-sitio" (revisión de seguridad del rediseño).
  if (!/^\/(?![\/\\])/.test(path)) path = "/";
  const next = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...params, ...patch })) {
    if (v !== undefined && v !== "") next.set(k, v);
  }
  const query = next.toString();
  return query ? `${path}?${query}` : path;
}

// Al tocar el encabezado de una columna: si ya ordenaba por ella, invierte; si no, de menor a mayor.
// Cambiar el orden vuelve a la primera página.
export function sortPatch(state: ListState, key: string): Record<string, string | undefined> {
  const desc = state.sort === key && state.dir === "asc";
  return { orden: desc ? `-${key}` : key, pagina: undefined };
}

export function pageCount(total: number, size: number): number {
  return Math.max(1, Math.ceil(Math.max(0, total) / size));
}

// "Filas 16 a 30 de 42" (o "Sin registros").
export function rangeLabel(state: ListState, total: number, shown: number): string {
  if (total <= 0 || shown <= 0) return "Sin registros";
  const from = (state.page - 1) * state.size + 1;
  return `Filas ${from} a ${from + shown - 1} de ${total.toLocaleString("es-AR")}`;
}

// Los parámetros de la dirección como texto simple (para armar enlaces que conservan los filtros).
export function plainParams(params: Params): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(params)) {
    const value = one(v);
    if (value !== undefined && value !== "") out[k] = value;
  }
  return out;
}
