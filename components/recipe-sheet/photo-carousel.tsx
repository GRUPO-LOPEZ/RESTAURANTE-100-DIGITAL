"use client";

import { useState } from "react";
import { ChevronLeft, ChevronRight, Plus } from "lucide-react";

import { RecipePhotoImage } from "@/components/recipe-photo-image";
import { RecipePhotoUpload } from "@/components/recipe-photo-upload";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";
import { MEDIA_KIND_LABELS } from "@/lib/recipe-format";
import type { PhotoSet } from "@/lib/recipes";

// Las fotos de la versión, una por vez, con ‹ › para pasar (ficha única, ADR-0042). «Agregar foto» abre el mismo
// formulario de siempre en un modal; solo se ofrece en un borrador.
export function PhotoCarousel({
  id,
  recipeId,
  set,
  canAdd,
  hint,
}: {
  // El ancla de las fotos en la ficha.
  id: string;
  recipeId: string;
  set: PhotoSet;
  canAdd: boolean;
  // Por qué no se puede agregar una foto (por ejemplo, se ve la versión vigente).
  hint?: string;
}) {
  const [index, setIndex] = useState(0);
  const [adding, setAdding] = useState(false);
  const total = set.photos.length;
  const photo = set.photos[Math.min(index, Math.max(total - 1, 0))];
  const kind = photo ? MEDIA_KIND_LABELS[photo.kind] : "";
  return (
    <figure id={id} className="flex w-full flex-col gap-2 desk:max-w-sm" aria-label="Fotos">
      {photo ? (
        <div className="relative">
          <RecipePhotoImage
            url={photo.url}
            alt={`Foto: ${kind}${photo.description ? ` – ${photo.description}` : ""}`}
          />
          {total > 1 ? (
            <>
              <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label="Foto anterior"
                className="absolute top-1/2 left-2 -translate-y-1/2 rounded-sm bg-surface"
                onClick={() => setIndex((i) => (i - 1 + total) % total)}
              >
                <ChevronLeft aria-hidden="true" />
              </Button>
              <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label="Foto siguiente"
                className="absolute top-1/2 right-2 -translate-y-1/2 rounded-sm bg-surface"
                onClick={() => setIndex((i) => (i + 1) % total)}
              >
                <ChevronRight aria-hidden="true" />
              </Button>
            </>
          ) : null}
        </div>
      ) : (
        <div className="flex aspect-[4/3] w-full items-center justify-center rounded-sm border border-dashed border-line p-4 text-center text-base text-ink-muted">
          {set.failed ? "No pudimos cargar las fotos. Recargá la página." : "Sin fotos todavía."}
        </div>
      )}
      <figcaption className="flex flex-wrap items-center justify-between gap-2 text-sm text-ink-muted">
        <span role="status">
          {total > 0
            ? `Foto ${Math.min(index, total - 1) + 1} de ${total} · ${kind}${photo?.description ? ` · ${photo.description}` : ""}`
            : ""}
        </span>
        {canAdd ? (
          <Modal
            open={adding}
            onOpenChange={setAdding}
            title="Agregar foto"
            description="Producto final, emplatado o un punto crítico. Va con este borrador."
            trigger={
              <Button type="button" variant="ghost">
                <Plus aria-hidden="true" />
                Agregar foto
              </Button>
            }
          >
            <RecipePhotoUpload recipeId={recipeId} />
          </Modal>
        ) : hint ? (
          <span className="text-sm text-ink-muted">{hint}</span>
        ) : null}
      </figcaption>
    </figure>
  );
}
