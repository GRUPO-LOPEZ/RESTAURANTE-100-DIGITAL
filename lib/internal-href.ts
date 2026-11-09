// Solo rutas internas (revisión de seguridad del rediseño): "/algo", nunca "//otro-sitio" ni "https://…".
// Los componentes que arman enlaces con lo que reciben (tabla, paginación, KPI) lo usan para no abrir una
// redirección a otro sitio si un día alguien les pasa un valor tomado de la dirección.
export function internalHref(href: string): string {
  return /^\/(?![\/\\])/.test(href) ? href : "/";
}
