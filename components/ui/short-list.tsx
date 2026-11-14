import * as React from "react";

import { cn } from "@/lib/utils";

// Una lista cortada (pantallas sin scroll, ADR-0046): muestra las primeras filas y, si hay más, «Ver los N …» (un enlace
// a otra pantalla o un panel lateral con la lista completa). Así la pantalla no crece con los datos. Sin filas, el texto
// vacío de esa lista.
export function shownCount(total: number, limit: number): number {
  return Math.min(Math.max(total, 0), Math.max(limit, 0));
}

export function ShortList<T>({
  label,
  items,
  limit = 3,
  itemKey,
  renderItem,
  empty,
  more,
  className,
}: {
  // El nombre de la lista para los lectores de pantalla («Productos de compra»).
  label: string;
  items: T[];
  limit?: number;
  itemKey: (item: T) => string;
  renderItem: (item: T) => React.ReactNode;
  empty: React.ReactNode;
  // Lo que se muestra si hay más filas que el límite: el enlace o el panel con la lista completa.
  more?: React.ReactNode;
  className?: string;
}) {
  if (items.length === 0) return <>{empty}</>;
  const shown = items.slice(0, shownCount(items.length, limit));
  return (
    <div className={cn("flex min-w-0 flex-col gap-1", className)}>
      <ul className="flex flex-col divide-y divide-line" aria-label={label}>
        {shown.map((item) => (
          <li key={itemKey(item)}>{renderItem(item)}</li>
        ))}
      </ul>
      {items.length > shown.length && more ? more : null}
    </div>
  );
}
