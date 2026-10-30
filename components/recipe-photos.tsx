import { removePhotoAction } from "@/app/recetas/actions";
import { ActionForm } from "@/components/action-form";
import { Disclosure } from "@/components/disclosure";
import { RecipePhotoImage } from "@/components/recipe-photo-image";
import { FormTextarea } from "@/components/ui/form";
import { Notice } from "@/components/ui/notice";
import { MEDIA_KIND_LABELS } from "@/lib/recipe-format";
import type { PhotoSet } from "@/lib/recipes";

// Fotos de una versión, en grilla (una columna en el celular). La imagen ya llega achicada, así que no
// se procesa de nuevo (unoptimized). Quitar una foto solo se ofrece en un borrador.
export function RecipePhotos({
  recipeId,
  set,
  canRemove,
}: {
  recipeId: string;
  set: PhotoSet;
  canRemove: boolean;
}) {
  if (set.failed && set.photos.length === 0)
    return (
      <Notice status="warn" role="status">
        No pudimos cargar las fotos. Recargá la página.
      </Notice>
    );
  if (set.photos.length === 0)
    return <p className="text-base text-ink-muted">Esta versión no tiene fotos.</p>;
  return (
    <ul className="grid gap-4 sm:grid-cols-2" aria-label="Fotos">
      {set.photos.map((p) => {
        const kind = MEDIA_KIND_LABELS[p.kind];
        return (
          <li key={p.id} className="flex flex-col gap-2">
            <figure className="flex flex-col gap-2">
              <RecipePhotoImage
                url={p.url}
                alt={`Foto: ${kind}${p.description ? ` – ${p.description}` : ""}`}
              />
              <figcaption aria-hidden="true" className="text-base text-ink">
                <span className="font-medium">{kind}</span>
                {p.description ? ` · ${p.description}` : ""}
              </figcaption>
            </figure>
            {canRemove ? (
              <Disclosure summary={`Quitar la foto «${p.description ?? kind}»`}>
                <ActionForm
                  action={removePhotoAction}
                  schema="reason"
                  submitLabel="Quitar foto"
                  variant="outline"
                >
                  <input type="hidden" name="recipeId" value={recipeId} />
                  <input type="hidden" name="mediaId" value={p.id} />
                  <FormTextarea
                    id={`rec-foto-quitar-${p.id}`}
                    name="reason"
                    label="Motivo"
                    hint="La foto sigue en las versiones anteriores y en el historial."
                    required
                    maxLength={500}
                  />
                </ActionForm>
              </Disclosure>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}
