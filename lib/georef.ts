import { z } from "zod";

// Georef: el servicio de normalización de direcciones del gobierno argentino (https://apis.datos.gob.ar/georef/),
// gratis y sin claves (ADR-0061, decisión 3 de Soy). Se consulta solo desde el servidor y solo cuando la persona toca
// «Buscar», nunca en cada tecla. Si no encuentra la dirección o el servicio no responde, el local se guarda igual y
// queda «Sin ubicar en el mapa»: nada se traba. La URL se puede cambiar con GEOREF_URL (las pruebas usan un servidor
// de mentira, así no dependen de la API del gobierno).

const DEFAULT_URL = "https://apis.datos.gob.ar/georef/api";
const TIMEOUT_MS = 5000;

const response = z.object({
  direcciones: z
    .array(
      z.object({
        nomenclatura: z.string(),
        ubicacion: z.object({ lat: z.number().nullable(), lon: z.number().nullable() }),
        provincia: z.object({ id: z.string(), nombre: z.string() }).nullable().optional(),
        localidad_censal: z.object({ nombre: z.string() }).nullable().optional(),
        departamento: z.object({ nombre: z.string() }).nullable().optional(),
      }),
    )
    .default([]),
});

export type GeorefMatch = {
  label: string;
  latitude: number;
  longitude: number;
  provinceCode: string | null;
  locality: string | null;
};

export type GeorefResult =
  { status: "found"; match: GeorefMatch } | { status: "not_found" } | { status: "unavailable" };

export async function findAddress(input: {
  address: string;
  locality?: string;
  provinceCode?: string;
}): Promise<GeorefResult> {
  const base = process.env.GEOREF_URL || DEFAULT_URL;
  const query = new URLSearchParams({
    direccion: input.address.trim(),
    max: "1",
    aplanar: "false",
  });
  if (input.locality?.trim()) query.set("localidad", input.locality.trim());
  if (input.provinceCode?.trim()) query.set("provincia", input.provinceCode.trim());
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${base}/direcciones?${query}`, {
      cache: "no-store",
      signal: controller.signal,
      headers: { Accept: "application/json" },
    });
    if (!res.ok) return { status: "unavailable" };
    const parsed = response.safeParse(await res.json());
    if (!parsed.success) return { status: "unavailable" };
    const hit = parsed.data.direcciones[0];
    if (!hit || hit.ubicacion.lat === null || hit.ubicacion.lon === null)
      return { status: "not_found" };
    return {
      status: "found",
      match: {
        label: hit.nomenclatura,
        latitude: Math.round(hit.ubicacion.lat * 1e6) / 1e6,
        longitude: Math.round(hit.ubicacion.lon * 1e6) / 1e6,
        provinceCode: hit.provincia?.id ?? null,
        locality: hit.localidad_censal?.nombre ?? hit.departamento?.nombre ?? null,
      },
    };
  } catch {
    return { status: "unavailable" };
  } finally {
    clearTimeout(timer);
  }
}
