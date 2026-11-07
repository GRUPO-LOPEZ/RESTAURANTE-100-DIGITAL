import { createClient } from "@/lib/supabase/server";

// El tablero de Inicio (ADR-0033). Todo con la sesión de la persona: la base decide qué secciones ve.

export type HomeRow = {
  kind: string;
  id: string | null;
  item: string;
  amount: number | null;
  detail: string | null;
};

export type HomeBoard = {
  preparations: number | null;
  mostUsed: HomeRow[];
  reliability: HomeRow[];
  topPortion: HomeRow[];
  topIngredient: HomeRow[];
  priceAffected: HomeRow[];
  // Las secciones que la persona puede ver, aunque estén vacías.
  sections: Set<string>;
};

export async function getHomeBoard(restaurantId: string): Promise<HomeBoard | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("home_board", { p_restaurant_id: restaurantId });
  if (error?.code === "42501") return null;
  if (error) throw new Error("No pudimos cargar el tablero.");
  const of = (section: string): HomeRow[] =>
    data
      .filter((r) => r.section === section)
      .map((r) => ({
        kind: r.kind,
        id: r.item_id,
        item: r.item,
        // La base puede mandar sin importe: una receta que recién tiene costo no tiene diferencia.
        amount: (r.amount as number | null) === null ? null : Number(r.amount),
        detail: r.detail,
      }));
  return {
    preparations: of("preparations")[0]?.amount ?? null,
    mostUsed: of("most_used"),
    reliability: of("reliability"),
    topPortion: of("top_portion"),
    topIngredient: of("top_ingredient"),
    priceAffected: of("price_affected"),
    sections: new Set(of("allowed").map((r) => r.item)),
  };
}

export type RecentImport = { id: string; file: string; status: string; createdAt: string };

// Las últimas importaciones que la sesión ve: la base filtra por marca o grupo.
export async function getRecentImports(limit = 3): Promise<RecentImport[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("imports")
    .from("import_jobs")
    .select("id, file_name, status, created_at")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw new Error("No pudimos cargar las importaciones.");
  return data.map((j) => ({
    id: j.id,
    file: j.file_name,
    status: j.status,
    createdAt: j.created_at,
  }));
}
