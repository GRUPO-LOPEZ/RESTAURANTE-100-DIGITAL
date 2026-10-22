import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { connection } from "next/server";

import type { Database } from "@/lib/database.types";
import { supabaseEnv } from "@/lib/supabase/env";
import { REMEMBER_COOKIE, rememberFromCookie, sessionCookieOptions } from "@/lib/supabase/remember";

// Cliente de Supabase para el servidor (componentes, acciones y rutas), con la sesión de la
// persona en cookies. Usa la clave pública: lo que puede hacer lo decide la base (RLS).
// `remember` lo pasa el ingreso; si no, sale de la cookie de "recordar sesión".
export async function createClient(options: { remember?: boolean } = {}) {
  // El cliente de Supabase lee la hora (vencimiento de la sesión): con Cache Components eso solo
  // puede pasar en el momento del pedido, nunca al prerenderizar (guía de Next 16).
  await connection();
  const cookieStore = await cookies();
  const { url, key } = supabaseEnv();
  const remember = options.remember ?? rememberFromCookie(cookieStore.get(REMEMBER_COOKIE)?.value);

  return createServerClient<Database>(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options: cookieOptions } of cookiesToSet) {
            cookieStore.set(name, value, sessionCookieOptions(cookieOptions, remember));
          }
        } catch {
          // Un componente de servidor no puede escribir cookies: las renueva proxy.ts.
        }
      },
    },
  });
}
