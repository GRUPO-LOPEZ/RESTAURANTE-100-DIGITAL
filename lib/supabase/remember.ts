// "Recordar sesión" (sección 9: pantalla de ingreso). Sin marcarlo, las cookies de la sesión de
// Supabase son de sesión del navegador: se borran al cerrarlo. Marcado, duran lo que dura la
// sesión de Supabase. La preferencia viaja en una cookie propia, sin datos personales.
export const REMEMBER_COOKIE = "lf-recordar";

export type CookieOptions = { maxAge?: number; expires?: Date; [key: string]: unknown };

export function rememberFromCookie(value: string | undefined): boolean {
  return value !== "0";
}

// Quita la duración a las cookies que se guardan; las que se borran (maxAge 0) quedan igual.
export function sessionCookieOptions<T extends CookieOptions>(options: T, remember: boolean): T {
  if (remember || options.maxAge === 0) return options;
  const rest = { ...options };
  delete rest.maxAge;
  delete rest.expires;
  return rest;
}
