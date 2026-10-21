import { createBrowserClient } from "@supabase/ssr";

import type { Database } from "@/lib/database.types";
import { supabaseEnv } from "@/lib/supabase/env";

// Cliente de Supabase para el navegador. Solo se usa donde hace falta (aceptar una invitación).
export function createClient() {
  const { url, key } = supabaseEnv();
  return createBrowserClient<Database>(url, key);
}
