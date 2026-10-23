import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import type { Database } from "@/lib/database.types";
import { supabaseEnv } from "@/lib/supabase/env";
import { REMEMBER_COOKIE, sessionCookieOptions } from "@/lib/supabase/remember";

// El enlace del correo de recuperación vuelve acá con un código de un solo uso. Se canjea por una
// sesión de recuperación y se pasa a elegir la contraseña nueva. Si la cuenta está bloqueada,
// suspendida o desactivada, el hook de Auth niega la sesión y el canje falla.
// Las cookies de la sesión se escriben en la misma respuesta de la redirección (como en proxy.ts),
// y la redirección usa el mismo host del pedido, para que las cookies queden en ese dominio.
export async function GET(request: NextRequest) {
  const host = request.headers.get("host") ?? request.nextUrl.host;
  const proto =
    request.headers.get("x-forwarded-proto") ?? request.nextUrl.protocol.replace(":", "");
  const base = `${proto}://${host}`;
  const code = request.nextUrl.searchParams.get("code");

  if (code && /^[0-9a-zA-Z-]{8,200}$/.test(code)) {
    const response = NextResponse.redirect(`${base}/ingresar/nueva-contrasena`);
    const { url, key } = supabaseEnv();
    const supabase = createServerClient<Database>(url, key, {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          // La sesión de recuperación dura lo que el navegador abierto.
          for (const { name, value, options } of cookiesToSet)
            response.cookies.set(name, value, sessionCookieOptions(options, false));
        },
      },
    });
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      response.cookies.set(REMEMBER_COOKIE, "0", {
        httpOnly: true,
        sameSite: "lax",
        secure: process.env.NODE_ENV === "production",
        path: "/",
      });
      return response;
    }
  }
  return NextResponse.redirect(`${base}/ingresar/recuperar?enlace=vencido`);
}
