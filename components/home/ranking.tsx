"use client";

import Link from "next/link";
import { useState } from "react";

import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

export type RankingRow = { key: string; name: string; value: string; href: string };
export type RankingList = { key: string; label: string; empty: string; rows: RankingRow[] };

// Un solo ranking con botones a la vista (ADR-0045; pocas opciones = botones, ADR-0039). Las listas llegan todas juntas
// del servidor: cambiar de lista no consulta nada. Los botones son de un formulario GET (?ranking=): antes de que cargue
// el JavaScript, o sin él, la página vuelve con la lista elegida; con él, cambia al instante y anota la elección en la
// dirección sin navegar, así al volver de una receta sigue elegida.
export function Ranking({
  lists,
  initial,
  placeId,
}: {
  lists: RankingList[];
  initial: string;
  placeId: string;
}) {
  const [selected, setSelected] = useState(
    lists.some((l) => l.key === initial) ? initial : (lists[0]?.key ?? ""),
  );
  const list = lists.find((l) => l.key === selected);
  if (!list) return null;

  function pick(event: React.MouseEvent<HTMLButtonElement>, key: string) {
    event.preventDefault();
    setSelected(key);
    try {
      const url = new URL(window.location.href);
      url.searchParams.set("ranking", key);
      window.history.replaceState(window.history.state, "", url);
    } catch {
      // Sin la dirección, la elección vale igual mientras la pantalla esté abierta.
    }
  }

  return (
    <section
      aria-labelledby="ranking-titulo"
      className="flex min-w-0 flex-col gap-1.5 rounded-md border border-line bg-surface p-4"
    >
      <h2 id="ranking-titulo" className="sr-only">
        Ranking
      </h2>
      <form method="get" action="/">
        <input type="hidden" name="local" value={placeId} />
        <div role="group" aria-label="Qué ranking ver" className="flex flex-wrap gap-1.5">
          {lists.map((l) => (
            <button
              key={l.key}
              type="submit"
              name="ranking"
              value={l.key}
              aria-pressed={l.key === selected}
              onClick={(event) => pick(event, l.key)}
              className={cn(
                "inline-flex min-h-touch items-center rounded-sm border px-2.5 text-xs desk:min-h-8",
                "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                l.key === selected
                  ? "border-primary bg-nav-active font-medium text-nav-active-ink"
                  : "border-line bg-surface text-ink hover:bg-line/50",
              )}
            >
              {l.label}
            </button>
          ))}
        </div>
      </form>
      {list.rows.length === 0 ? (
        <p className="flex flex-wrap items-center gap-2 text-sm text-ink">
          <Badge status="none">Sin datos</Badge>
          {list.empty}
        </p>
      ) : (
        <ul className="flex flex-col divide-y divide-line" aria-label={list.label}>
          {list.rows.map((row) => (
            <li key={row.key}>
              <Link
                href={row.href}
                className="flex min-h-touch items-center justify-between gap-4 text-sm underline-offset-4 hover:underline desk:min-h-7"
              >
                <span className="min-w-0 truncate text-primary">{row.name}</span>
                <span className="shrink-0 text-ink tabular-nums">{row.value}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
