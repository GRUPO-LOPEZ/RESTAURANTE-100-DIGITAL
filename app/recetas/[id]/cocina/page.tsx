import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Card, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import { RecipePhotos } from "@/components/recipe-photos";
import { UUID, formatDateTime } from "@/lib/data";
import {
  ALLERGEN_LABELS,
  BASIS_LABELS,
  STEP_KIND_LABELS,
  formatMinutes,
  formatQuantity,
  getKitchenCard,
  getPublishedPhotos,
} from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Vista de cocina (secciones 13 y 17): la versión vigente, con letra grande (20 px) para leerla de
// lejos en una tablet o un celular. Sin ningún valor económico: la base no los manda (caso 24).
export default function CocinaPage({ params }: PageProps<"/recetas/[id]/cocina">) {
  return (
    <AppShell title="Ficha de cocina" description="La versión vigente, para preparar la receta.">
      <Suspense fallback={<Loading />}>
        <Kitchen params={params} />
      </Suspense>
    </AppShell>
  );
}

const ALLERGEN_BADGE: Record<string, BadgeStatus> = {
  contains: "bad",
  may_contain: "warn",
};

const linkClass =
  "inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline";

// "después del paso 1", "después de los pasos 1 y 3".
function after(steps: number[]) {
  if (steps.length === 1) return `después del paso ${steps[0]}`;
  return `después de los pasos ${steps.slice(0, -1).join(", ")} y ${steps.at(-1)}`;
}

async function Kitchen({ params }: { params: PageProps<"/recetas/[id]/cocina">["params"] }) {
  await requireMenu("recipes");
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const [card, menus, photos] = await Promise.all([
    getKitchenCard(id),
    getMenus(),
    getPublishedPhotos(id),
  ]);
  const back = (
    <div className="flex flex-wrap gap-x-4">
      <Link href="/recetas" className={linkClass}>
        Volver a recetas
      </Link>
      {/* Quien trabaja recetas vuelve a la ficha; si no la trabaja, la ficha lo trae de nuevo acá. */}
      {menus.recipesDraft ? (
        <Link href={`/recetas/${id}`} className={linkClass}>
          Volver a la ficha
        </Link>
      ) : null}
    </div>
  );
  if (!card) {
    return (
      <>
        {back}
        <EmptyState title="Esta receta no tiene una versión vigente para tu cocina.">
          Puede estar en preparación, archivada o no asignada a tu local.
        </EmptyState>
      </>
    );
  }
  // Primero lo que sí contiene; lo no verificado, en una sola línea (que no tape lo importante).
  const warnings = card.allergens.filter(
    (a) => a.status === "contains" || a.status === "may_contain",
  );
  const unverified = card.allergens.filter((a) => a.status === "not_verified");
  return (
    <>
      {back}
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <CardTitle className="text-2xl">{card.name}</CardTitle>
          <span className="text-base text-ink-muted tabular-nums">
            {card.code} · versión {card.versionNumber} · vigente desde{" "}
            {formatDateTime(card.publishedAt)}
          </span>
        </div>
        {card.description ? <p className="text-xl text-ink">{card.description}</p> : null}
        <dl className="grid gap-4 text-xl sm:grid-cols-3">
          <div className="flex flex-col">
            <dt className="text-base font-medium text-ink-muted">Rinde</dt>
            <dd className="text-ink tabular-nums">
              {card.yieldQuantity
                ? `${formatQuantity(card.yieldQuantity)} ${card.yieldUnit ?? ""}`
                : "—"}
              {card.portions
                ? ` · ${card.portions} ${card.portions === 1 ? "porción" : "porciones"}`
                : ""}
              {card.portionGrams ? ` de ${formatQuantity(card.portionGrams)} g` : ""}
            </dd>
          </div>
          <div className="flex flex-col">
            <dt className="text-base font-medium text-ink-muted">Tiempo total</dt>
            <dd className="text-ink tabular-nums">{formatMinutes(card.totalMinutes)}</dd>
          </div>
          <div className="flex flex-col">
            <dt className="text-base font-medium text-ink-muted">Trabajando</dt>
            <dd className="text-ink tabular-nums">{formatMinutes(card.activeMinutes)}</dd>
          </div>
        </dl>
        <div className="flex flex-col gap-2">
          <h3 className="text-base font-medium text-ink">Alérgenos</h3>
          {card.allergens.length === 0 ? (
            <p className="text-base text-ink-muted">No hay alérgenos cargados en el catálogo.</p>
          ) : (
            <>
              {warnings.length > 0 ? (
                <ul className="flex flex-wrap gap-2" aria-label="Alérgenos que contiene">
                  {warnings.map((a) => (
                    <li key={a.name}>
                      <Badge
                        status={ALLERGEN_BADGE[a.status]}
                        className="text-base whitespace-normal"
                      >
                        {a.name}: {ALLERGEN_LABELS[a.status]}
                      </Badge>
                    </li>
                  ))}
                </ul>
              ) : null}
              {unverified.length > 0 ? (
                <p className="text-base text-ink">
                  <span className="font-medium">Sin verificar:</span>{" "}
                  {unverified.map((a) => a.name).join(", ")}.
                </p>
              ) : null}
              {warnings.length === 0 && unverified.length === 0 ? (
                <Badge status="ok" className="text-base whitespace-normal">
                  Todo verificado: no contiene ningún alérgeno de la lista
                </Badge>
              ) : null}
            </>
          )}
        </div>
      </Card>

      <Card className="flex flex-col gap-4">
        <CardTitle>Ingredientes</CardTitle>
        <ul className="flex flex-col gap-3 text-xl" aria-label="Ingredientes">
          {card.components.map((c) => (
            <li
              key={c.line}
              className="flex flex-wrap justify-between gap-2 border-b border-line pb-3 last:border-0"
            >
              <span className="text-ink">
                {c.ingredient}
                {c.basis !== "purchase" ? (
                  <span className="text-base text-ink-muted">
                    {" "}
                    ({BASIS_LABELS[c.basis].toLowerCase()})
                  </span>
                ) : null}
                {c.notes ? <span className="block text-base text-ink-muted">{c.notes}</span> : null}
              </span>
              <span className="font-semibold text-ink tabular-nums">
                {formatQuantity(c.quantity)} {c.unit}
              </span>
            </li>
          ))}
        </ul>
      </Card>

      <Card className="flex flex-col gap-4">
        <CardTitle>Paso a paso</CardTitle>
        <ol className="flex flex-col gap-4 text-xl" aria-label="Paso a paso">
          {card.steps.map((s) => (
            <li
              key={s.number}
              className="flex flex-col gap-1 border-b border-line pb-4 last:border-0"
            >
              <span className="text-base font-medium text-ink-muted">
                Paso {s.number} · {STEP_KIND_LABELS[s.kind]} ·{" "}
                {formatMinutes(s.active_minutes + s.passive_minutes)}
                {s.depends_on.length > 0 ? ` · ${after(s.depends_on)}` : ""}
              </span>
              <span className="text-ink">{s.instructions}</span>
              {s.equipment ? (
                <span className="text-base text-ink-muted">Equipo: {s.equipment}</span>
              ) : null}
              {s.control_point ? (
                <span className="text-base text-ink-muted">Control: {s.control_point}</span>
              ) : null}
            </li>
          ))}
        </ol>
      </Card>

      {photos.photos.length > 0 || photos.failed ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Fotos</CardTitle>
          <RecipePhotos recipeId={id} set={photos} canRemove={false} />
        </Card>
      ) : null}

      {card.storageNotes || card.presentationNotes ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Conservación y presentación</CardTitle>
          {card.presentationNotes ? (
            <p className="text-xl text-ink">{card.presentationNotes}</p>
          ) : null}
          {card.storageNotes ? <p className="text-xl text-ink">{card.storageNotes}</p> : null}
        </Card>
      ) : null}
    </>
  );
}
