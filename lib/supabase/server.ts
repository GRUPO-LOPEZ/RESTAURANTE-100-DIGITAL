import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { connection } from "next/server";

import type { Database } from "@/lib/database.types";
import { supabaseEnv } from "@/lib/supabase/env";

// Cliente de Supabase para el servidor (componentes, acciones y rutas), con la sesión de la
// persona en cookies. Usa la clave pública: lo que puede hacer lo decide la base (RLS).
export async function createClient() {
  // El cliente de Supabase lee la hora (vencimiento de la sesión): con Cache Components eso solo
  // puede pasar en el momento del pedido, nunca al prerenderizar (guía de Next 16).
  await connection();
  const cookieStore = await cookies();
  const { url, key } = supabaseEnv();

  return createServerClient<Database>(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Un componente de servidor no puede escribir cookies: las renueva proxy.ts.
        }
      },
    },
  });
}
