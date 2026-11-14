import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { searchComponents } from "@/lib/recipe-search";
import { createClient } from "@/lib/supabase/server";

// La búsqueda de la planilla de la ficha (ADR-0047): ?q=texto&receta=id. Es una ruta GET y no una acción de servidor
// porque Next corre las acciones de a una, y la búsqueda quedaba esperando detrás del cálculo de la planilla. Lee con la
// sesión de la persona (la base decide qué ve); sin sesión, 401; sin recipes.view en ningún alcance, 403. No se guarda
// en caché.
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return new NextResponse("Sin sesión", { status: 401 });
  // Lo mismo que pide la pantalla (el menú de recetas), con una sola consulta: la búsqueda corre en cada tecla.
  const { data: canView } = await supabase
    .schema("core")
    .rpc("has_permission_anywhere", { p_permission: "recipes.view" });
  if (canView !== true) return new NextResponse("Sin permiso", { status: 403 });
  const params = request.nextUrl.searchParams;
  const result = await searchComponents(params.get("q") ?? "", params.get("receta") ?? "");
  return NextResponse.json(result, { headers: { "cache-control": "no-store" } });
}
