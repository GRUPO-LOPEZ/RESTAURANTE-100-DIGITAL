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
  compact = false,
}: {
  // El ancla de las fotos en la ficha.
  id: string;
  recipeId: string;
  set: PhotoSet;
  canAdd: boolean;
  // Por qué no se puede agregar una foto (por ejemplo, se ve la versión vigente).
  hint?: string;
  // La miniatura de la ficha sin scroll (ADR-0047): 96 × 72 con ‹ › y «+» encima. En el celular, la foto grande de
  // siempre.
  compact?: boolean;
}) {
  const [index, setIndex] = useState(0);
  const [adding, setAdding] = useState(false);
  const total = set.photos.length;
  const photo = set.photos[Math.min(index, Math.max(total - 1, 0))];
  const kind = photo ? MEDIA_KIND_LABELS[photo.kind] : "";
  const addModal = (trigger: React.ReactNode) => (
    <Modal
      open={adding}
      onOpenChange={setAdding}
      title="Agregar foto"
      description="Producto final, emplatado o un punto crítico. Va con este borrador."
      trigger={trigger}
    >
      <RecipePhotoUpload recipeId={recipeId} />
    </Modal>
  );
  if (compact) {
    const label =
      total > 0
        ? `Foto ${Math.min(index, total - 1) + 1} de ${total} · ${kind}${photo?.description ? ` · ${photo.description}` : ""}`
        : set.failed
          ? "No pudimos cargar las fotos. Recargá la página."
          : "Sin fotos todavía.";
    // Los controles van sobre la miniatura (32 px, ADR-0046), así la tarjeta no crece: ‹ › a los costados y «+» arriba
    // a la derecha. Sin fotos, la miniatura vacía es el botón «Agregar foto».
    const overlay = "absolute size-8 min-h-8 rounded-sm bg-surface px-0 desk:min-h-8";
    return (
      <figure id={id} className="relative w-24 shrink-0" aria-label="Fotos">
        {photo ? (
          <RecipePhotoImage
            url={photo.url}
            alt={`Foto: ${kind}${photo.description ? ` – ${photo.description}` : ""}`}
          />
        ) : canAdd ? (
          <Button
            type="button"
            variant="outline"
            aria-haspopup="dialog"
            className="flex aspect-[4/3] h-auto min-h-0 w-24 flex-col gap-1 border-dashed px-1 text-xs desk:min-h-0"
            onClick={() => setAdding(true)}
          >
            <Plus aria-hidden="true" />
            Agregar foto
          </Button>
        ) : (
          <div className="flex aspect-[4/3] w-24 items-center justify-center rounded-sm border border-dashed border-line p-1 text-center text-xs text-ink-muted">
            {set.failed ? "No cargaron" : "Sin fotos"}
          </div>
        )}
        <figcaption className="sr-only" role="status">
          {label}
        </figcaption>
        {total > 1 ? (
          <>
            <Button
              type="button"
              variant="outline"
              aria-label="Foto anterior"
              className={`${overlay} bottom-1 left-1`}
              onClick={() => setIndex((i) => (i - 1 + total) % total)}
            >
              <ChevronLeft aria-hidden="true" />
            </Button>
            <Button
              type="button"
              variant="outline"
              aria-label="Foto siguiente"
              className={`${overlay} right-1 bottom-1`}
              onClick={() => setIndex((i) => (i + 1) % total)}
            >
              <ChevronRight aria-hidden="true" />
            </Button>
          </>
        ) : null}
        {photo && canAdd ? (
          <Button
            type="button"
            variant="outline"
            aria-label="Agregar foto"
            aria-haspopup="dialog"
            className={`${overlay} top-1 right-1`}
            onClick={() => setAdding(true)}
          >
            <Plus aria-hidden="true" />
          </Button>
        ) : null}
        {/* Un solo modal, fuera de los dos botones: al subir la primera foto, la miniatura vacía (el primer botón) se va
            y el modal sigue abierto con su aviso. */}
        {canAdd ? addModal(null) : null}
      </figure>
    );
  }
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
          addModal(
            <Button type="button" variant="ghost">
              <Plus aria-hidden="true" />
              Agregar foto
            </Button>,
          )
        ) : hint ? (
          <span className="text-sm text-ink-muted">{hint}</span>
        ) : null}
      </figcaption>
    </figure>
  );
}
