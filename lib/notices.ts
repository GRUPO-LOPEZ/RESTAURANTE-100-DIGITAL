// A dónde lleva un aviso (sin base de datos: lo prueba Vitest).

// Solo rutas internas, con la misma regla que el check de la base (revisión de seguridad). Un aviso de
// rendimiento abre la ficha de la materia prima directo en su pestaña «Rendimientos» (ADR-0036).
export function noticeLink(kind: string, link: string | null): string | null {
  if (!link || !/^\/[A-Za-z][A-Za-z0-9/_?=&-]*$/.test(link)) return null;
  if (kind === "yield_deviation" && /^\/materias-primas\/[0-9a-f-]{36}$/.test(link))
    return `${link}?seccion=rendimientos`;
  return link;
}
