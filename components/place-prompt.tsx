import Link from "next/link";

import { EmptyState } from "@/components/ui/states";

// Con «Todos mis locales» en la barra de arriba, una pantalla que necesita un local lo pide (ADR-0036: el
// selector de local es único y global). Los enlaces llevan ?local=, que la pantalla entiende igual.
export function PlacePrompt({
  title,
  places,
  path,
}: {
  title: string;
  places: { id: string; name: string }[];
  // La pantalla a la que lleva cada local ("/costos").
  path: string;
}) {
  return (
    <EmptyState title={title}>
      <p>Elegí uno en «Local», en la barra de arriba, o entrá directo:</p>
      <ul className="mt-2 flex flex-wrap justify-center gap-x-4 gap-y-1" aria-label="Tus locales">
        {places.map((p) => (
          <li key={p.id}>
            <Link
              href={`${path}?local=${p.id}`}
              className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-control-sm"
            >
              {p.name}
            </Link>
          </li>
        ))}
      </ul>
    </EmptyState>
  );
}
