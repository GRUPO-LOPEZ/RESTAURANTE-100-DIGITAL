import { getKitchenCard, getPublishedPhotos } from "@/lib/recipes";
import { STEP_KIND_LABELS, formatMinutes } from "@/lib/recipe-format";

// Lo que la ficha técnica suma a la lista de ingredientes: el paso a paso, las fotos y las notas. No va en el Excel ni
// en el CSV, que son una tabla: va en la pantalla y en el papel. Se muestra solo después de que la base controló que
// la receta es una vigente del local (costing.require_report_recipe).

// "después del paso 1", "después de los pasos 1 y 3".
function after(steps: number[]) {
  if (steps.length === 1) return `después del paso ${steps[0]}`;
  return `después de los pasos ${steps.slice(0, -1).join(", ")} y ${steps.at(-1)}`;
}
export async function RecipeCardExtras({ recipeId }: { recipeId: string }) {
  const [card, photos] = await Promise.all([
    getKitchenCard(recipeId),
    getPublishedPhotos(recipeId),
  ]);
  if (!card) return null;
  const shown = photos.photos.filter((p) => p.url);
  return (
    <>
      <section className="flex flex-col gap-2 print:break-inside-avoid-page">
        <h3 className="text-xl font-semibold text-ink">Paso a paso</h3>
        {card.steps.length === 0 ? (
          <p className="text-base text-ink-muted">Esta versión no tiene pasos cargados.</p>
        ) : (
          <ol className="flex flex-col gap-3" aria-label="Paso a paso">
            {card.steps.map((s) => (
              <li
                key={s.number}
                className="flex flex-col gap-1 border-b border-line pb-3 last:border-0 print:break-inside-avoid"
              >
                <span className="text-sm font-medium text-ink-muted tabular-nums">
                  Paso {s.number} · {STEP_KIND_LABELS[s.kind]} ·{" "}
                  {formatMinutes(s.active_minutes + s.passive_minutes)}
                  {s.depends_on.length > 0 ? ` · ${after(s.depends_on)}` : ""}
                </span>
                <span className="text-base text-ink">{s.instructions}</span>
                {s.equipment ? (
                  <span className="text-sm text-ink-muted">Equipo: {s.equipment}</span>
                ) : null}
                {s.control_point ? (
                  <span className="text-sm text-ink-muted">Control: {s.control_point}</span>
                ) : null}
              </li>
            ))}
          </ol>
        )}
      </section>
      {card.presentationNotes ? (
        <section className="flex flex-col gap-2 print:break-inside-avoid">
          <h3 className="text-xl font-semibold text-ink">Presentación</h3>
          <p className="text-base text-ink">{card.presentationNotes}</p>
        </section>
      ) : null}
      {card.storageNotes ? (
        <section className="flex flex-col gap-2 print:break-inside-avoid">
          <h3 className="text-xl font-semibold text-ink">Conservación</h3>
          <p className="text-base text-ink">{card.storageNotes}</p>
        </section>
      ) : null}
      <section className="flex flex-col gap-2">
        <h3 className="text-xl font-semibold text-ink">Fotos</h3>
        {photos.failed ? (
          <p className="text-base text-ink-muted">No pudimos cargar las fotos.</p>
        ) : shown.length === 0 ? (
          <p className="text-base text-ink-muted">Esta versión no tiene fotos.</p>
        ) : (
          <p className="text-sm text-ink-muted print:hidden">
            Si una foto no se ve, volvé a abrir la ficha: el enlace dura diez minutos.
          </p>
        )}
        {shown.length > 0 ? (
          <ul className="grid gap-4 sm:grid-cols-2" aria-label="Fotos">
            {shown.map((p) => (
              <li key={p.id} className="flex flex-col gap-1 print:break-inside-avoid">
                {/* Enlace firmado de Storage, de diez minutos: alcanza para imprimir. */}
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={p.url ?? ""}
                  alt={p.description ? `Foto: ${p.description}` : "Foto de la receta"}
                  className="max-h-72 w-full rounded-lg border border-line bg-app object-contain"
                />
                {p.description ? (
                  <span className="text-sm text-ink-muted">{p.description}</span>
                ) : null}
              </li>
            ))}
          </ul>
        ) : null}
      </section>
    </>
  );
}
