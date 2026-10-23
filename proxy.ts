import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { supabaseEnv } from "@/lib/supabase/env";
import { REMEMBER_COOKIE, rememberFromCookie, sessionCookieOptions } from "@/lib/supabase/remember";

// Proxy de Next 16 (antes "middleware"): renueva la sesión de Supabase en las cookies y manda
// a /ingresar a quien no tiene sesión. Es solo una comodidad: la seguridad real está en la base
// y cada acción de servidor vuelve a validar (docs de Next: no depender solo del proxy).
const PUBLIC_PATHS = ["/ingresar", "/sin-acceso"];

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { url, key } = supabaseEnv();
  const remember = rememberFromCookie(request.cookies.get(REMEMBER_COOKIE)?.value);

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet)
          response.cookies.set(name, value, sessionCookieOptions(options, remember));
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  const path = request.nextUrl.pathname;
  const isPublic = PUBLIC_PATHS.some((p) => path === p || path.startsWith(`${p}/`));

  if (!data?.claims && !isPublic) {
    const login = request.nextUrl.clone();
    login.pathname = "/ingresar";
    login.search = "";
    return NextResponse.redirect(login);
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|ico|webmanifest)$).*)"],
};
