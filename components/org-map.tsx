"use client";

import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";

import { cn } from "@/lib/utils";

// Mapa de los locales (ADR-0061, decisión 3 de Soy): Leaflet con las teselas de OpenStreetMap, sin claves ni costo.
// Respeta la política de uso de OSM: atribución visible, pocas teselas (un puñado de locales, pocas personas) y sin
// descargas masivas. Si el uso crece, se cambia de proveedor de teselas (queda en el ADR). Leaflet se carga solo en el
// navegador. Los puntos van con los tonos fuertes de los gráficos (3:1 sobre el fondo), leídos de las variables de la
// paleta: el código no tiene colores propios. Cada punto lleva el nombre del local (el color no es la única señal) y
// la lista de los locales está siempre al lado, para quien no ve el mapa.

export type MapPoint = {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  // Cocina central o producción se dibujan con otro tono (y el nombre lo dice).
  kind: "restaurant" | "other";
};

const TILES = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
const ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright">colaboradores de OpenStreetMap</a>';
// Buenos Aires, si no hay ningún punto.
const CENTER: [number, number] = [-34.6037, -58.3816];

function token(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

export function OrgMap({
  points,
  label,
  zoom = 11,
  className,
}: {
  points: MapPoint[];
  // Nombre accesible del mapa («Mapa con los 4 locales»).
  label: string;
  zoom?: number;
  className?: string;
}) {
  const box = useRef<HTMLDivElement>(null);
  const key = points.map((p) => `${p.id}:${p.latitude}:${p.longitude}`).join("|");

  useEffect(() => {
    let cancelled = false;
    let map: import("leaflet").Map | null = null;
    void import("leaflet").then((L) => {
      if (cancelled || !box.current) return;
      map = L.map(box.current, {
        zoomControl: false,
        attributionControl: false,
        scrollWheelZoom: false,
        keyboard: true,
      });
      L.control.zoom({ zoomInTitle: "Acercar", zoomOutTitle: "Alejar" }).addTo(map);
      // La atribución que pide OpenStreetMap, sin el prefijo de Leaflet.
      L.control.attribution({ prefix: false }).addTo(map);
      L.tileLayer(process.env.NEXT_PUBLIC_MAP_TILES_URL || TILES, {
        maxZoom: 19,
        attribution: ATTRIBUTION,
      }).addTo(map);
      const main = token("--color-chart-strong-1");
      const other = token("--color-chart-strong-3");
      const surface = token("--color-surface");
      const markers = points.map((p) => {
        // El nombre va como texto, nunca como HTML (auditoría de seguridad: un nombre con etiquetas no se ejecuta).
        const tip = document.createElement("span");
        tip.textContent = p.name;
        // Restaurante: punto lleno; cocina o producción: círculo vacío de otro tono (el color no es la única señal).
        const restaurant = p.kind === "restaurant";
        return L.circleMarker([p.latitude, p.longitude], {
          radius: 8,
          color: restaurant ? main : other,
          weight: 3,
          fillColor: restaurant ? main : surface,
          fillOpacity: 1,
        })
          .bindTooltip(tip, { direction: "top", offset: [0, -8] })
          .addTo(map as import("leaflet").Map);
      });
      if (markers.length === 0) map.setView(CENTER, zoom);
      else if (markers.length === 1 && points[0])
        map.setView([points[0].latitude, points[0].longitude], 15);
      else map.fitBounds(L.featureGroup(markers).getBounds(), { padding: [24, 24], maxZoom: 14 });
    });
    return () => {
      cancelled = true;
      map?.remove();
    };
    // Se rehace solo si cambian los puntos.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, zoom]);

  const kinds = new Set(points.map((p) => p.kind));
  return (
    <div className={cn("flex min-h-0 flex-col gap-1", className)}>
      <div
        ref={box}
        role="region"
        aria-label={label}
        className="org-map relative z-0 min-h-40 w-full flex-[1_1_0px] overflow-hidden rounded-sm border border-line"
      />
      {kinds.size > 1 ? (
        <p className="flex flex-wrap gap-x-4 text-xs text-ink-muted">
          <span className="inline-flex items-center gap-1">
            <span
              aria-hidden="true"
              className="inline-block size-3 rounded-full bg-chart-strong-1"
            />
            Restaurante
          </span>
          <span className="inline-flex items-center gap-1">
            <span
              aria-hidden="true"
              className="inline-block size-3 rounded-full border-2 border-chart-strong-3 bg-surface"
            />
            Cocina o producción
          </span>
        </p>
      ) : null}
    </div>
  );
}
