// Variables públicas de Supabase. Solo la URL y la clave pública (publishable): la clave de
// servidor nunca llega a la app (security.md). En local salen de .env.local; en CI y en las
// pruebas, de los valores públicos de desarrollo de .env.example.
export function supabaseEnv(): { url: string; key: string } {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) {
    throw new Error("Faltan NEXT_PUBLIC_SUPABASE_URL o NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.");
  }
  return { url, key };
}
