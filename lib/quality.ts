import { QUALITY_PAGE } from "@/lib/quality-labels";
import { createClient } from "@/lib/supabase/server";

// Lecturas de la calidad de datos (ADR-0033). Todo con la sesión de la persona: la base decide qué
// locales entra y qué indicadores ve en cada uno.

export type QualityPlaceName = { id: string; name: string };
export type QualityCount = { indicator: string; done: number; total: number; hidden: number };
export type QualityPlace = QualityPlaceName & { counts: QualityCount[] };

// Los locales donde la persona entra: una consulta liviana, para elegir.
export async function getQualityPlaces(): Promise<QualityPlaceName[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("quality_places");
  if (error) throw new Error("No pudimos cargar tus locales.");
  return data;
}

// Los indicadores de un local. Sin permiso en ese local, nada: la pantalla responde que no existe.
export async function getQuality(restaurantId: string): Promise<QualityCount[] | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("data_quality", { p_restaurant_id: restaurantId });
  if (error?.code === "42501") return null;
  if (error) throw new Error("No pudimos calcular la calidad de datos.");
  return data.map((r) => ({
    indicator: r.indicator,
    done: Number(r.done),
    total: Number(r.total),
    hidden: Number(r.hidden),
  }));
}

// Los primeros locales, para compararlos: cada uno tarda, así que van aparte.
export async function getQualityCompare(): Promise<QualityPlace[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("data_quality_places");
  if (error) throw new Error("No pudimos comparar los locales.");
  const places = new Map<string, QualityPlace>();
  for (const row of data) {
    const place = places.get(row.restaurant_id) ?? {
      id: row.restaurant_id,
      name: row.restaurant,
      counts: [],
    };
    place.counts.push({
      indicator: row.indicator,
      done: Number(row.done),
      total: Number(row.total),
      hidden: 0,
    });
    places.set(row.restaurant_id, place);
  }
  return [...places.values()];
}

export type QualityItem = { id: string; kind: string; item: string; detail: string | null };

// La lista de lo que falta. Sin permiso para ese indicador o ese local, nada.
export async function getQualityItems(
  restaurantId: string,
  indicator: string,
  page: number,
): Promise<{ items: QualityItem[]; total: number } | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("data_quality_items", {
    p_restaurant_id: restaurantId,
    p_indicator: indicator,
    p_limit: QUALITY_PAGE,
    p_offset: page * QUALITY_PAGE,
  });
  if (error?.code === "42501") return null;
  if (error) throw new Error("No pudimos cargar la lista.");
  return {
    items: data.map((r) => ({ id: r.item_id, kind: r.kind, item: r.item, detail: r.detail })),
    total: Number(data[0]?.total_rows ?? 0),
  };
}
