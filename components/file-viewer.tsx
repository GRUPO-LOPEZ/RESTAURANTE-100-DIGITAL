"use client";

import * as React from "react";
import { Maximize, Minus, Plus } from "lucide-react";

import { Button } from "@/components/ui/button";

// El archivo de la lista a la izquierda de la planilla (pantalla dividida, decisión 16 de Soy, ADR-0071): una foto con
// zoom (− / + / ajustar) que se mueve arrastrando, o un PDF escaneado con el visor del navegador (que ya trae zoom). El
// archivo no sale de la computadora hasta que se carga la lista.
export function FileViewer({
  url,
  kind,
  name,
}: {
  url: string;
  kind: "image" | "pdf";
  name: string;
}) {
  const [zoom, setZoom] = React.useState(1);
  const box = React.useRef<HTMLDivElement>(null);
  const drag = React.useRef<{ x: number; y: number; left: number; top: number } | null>(null);

  if (kind === "pdf")
    return (
      <iframe
        src={url}
        title={`El archivo de la lista: ${name}`}
        className="size-full min-h-0 rounded-sm border border-line bg-surface"
      />
    );

  const pct = Math.round(zoom * 100);
  return (
    <div className="flex size-full min-h-0 flex-col gap-2">
      <div role="group" aria-label="Zoom de la foto" className="flex items-center gap-2">
        <Button
          type="button"
          variant="outline"
          size="icon"
          aria-label="Achicar"
          disabled={zoom <= 0.5}
          onClick={() => setZoom((z) => Math.max(0.5, Math.round((z - 0.25) * 100) / 100))}
        >
          <Minus aria-hidden="true" />
        </Button>
        <span className="w-14 text-center text-sm text-ink tabular-nums" aria-live="polite">
          {pct} %
        </span>
        <Button
          type="button"
          variant="outline"
          size="icon"
          aria-label="Agrandar"
          disabled={zoom >= 4}
          onClick={() => setZoom((z) => Math.min(4, Math.round((z + 0.25) * 100) / 100))}
        >
          <Plus aria-hidden="true" />
        </Button>
        <Button type="button" variant="outline" onClick={() => setZoom(1)}>
          <Maximize aria-hidden="true" />
          Ajustar
        </Button>
      </div>
      {/* Con zoom, la foto se mueve arrastrando (o con las barras y las flechas del teclado). */}
      <div
        ref={box}
        tabIndex={0}
        aria-label={`La foto de la lista: ${name}`}
        role="region"
        className="relative min-h-0 flex-[1_1_0px] cursor-grab overflow-auto rounded-sm border border-line bg-app focus-visible:outline-2 focus-visible:outline-primary active:cursor-grabbing"
        onPointerDown={(e) => {
          const el = box.current;
          if (!el) return;
          drag.current = { x: e.clientX, y: e.clientY, left: el.scrollLeft, top: el.scrollTop };
          el.setPointerCapture(e.pointerId);
        }}
        onPointerMove={(e) => {
          const el = box.current;
          const d = drag.current;
          if (!el || !d) return;
          el.scrollLeft = d.left - (e.clientX - d.x);
          el.scrollTop = d.top - (e.clientY - d.y);
        }}
        onPointerUp={() => (drag.current = null)}
        onPointerCancel={() => (drag.current = null)}
      >
        {/* eslint-disable-next-line @next/next/no-img-element -- una foto local (blob:), no se optimiza */}
        <img
          src={url}
          alt=""
          draggable={false}
          style={{ width: `${pct}%`, maxWidth: "none" }}
          className="block select-none"
        />
      </div>
    </div>
  );
}
