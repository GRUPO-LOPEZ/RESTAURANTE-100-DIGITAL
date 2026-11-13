import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense, cache } from "react";
import { ChefHat, Scale } from "lucide-react";

import {
  archiveRecipeAction,
  assignAction,
  createVariantAction,
  newVersionAction,
  requestReviewAction,
  withdrawReviewAction,
} from "@/app/recetas/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { Disclosure } from "@/components/disclosure";
import { PhotoCarousel } from "@/components/recipe-sheet/photo-carousel";
import { ReviewBox } from "@/components/recipe-sheet/review-box";
import { SheetEditor } from "@/components/recipe-sheet/sheet-editor";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { codeNoticeFromQuery } from "@/lib/codes";
import { resolveCostPlace } from "@/lib/costs";
import { UUID, first, formatDateTime } from "@/lib/data";
import { parseTimes } from "@/lib/recipe-sheet";
import { unitOptionsAction } from "@/app/recetas/actions";
import {
  ALLERGEN_LABELS,
  RECIPE_TYPE_LABELS,
  SCOPE_LABELS,
  VERSION_STATUS_LABELS,
  createdRecently,
  formatQuantity,
  getAssignments,
  getRecipe,
  getRecipeCategories,
  getRecipeUsage,
  getVariantDiff,
  getVariants,
  getVersionContent,
  getVersionDiff,
  getVersionPhotos,
  getVersionSummary,
  hasPermissionIn,
  type DiffRow,
  type RecipeDetail,
  type RecipeVersion,
  type VersionStatus,
} from "@/lib/recipes";

// Ficha única de una receta (ADR-0042, reemplaza las 9 pestañas del ADR-0036): todo en una sola pantalla, de arriba
// hacia abajo, con un índice que baja a cada sección. Quien la trabaja edita donde ve y guarda todo junto; quien
// revisa la ve en solo lectura con los cambios marcados; quien solo la ve va a la vista de cocina.
export default function RecetaPage({ params, searchParams }: PageProps<"/recetas/[id]">) {
  return (
    <AppShell
      title="Receta"
      heading={
        <Suspense fallback="Receta">
          <RecipeName params={params} />
        </Suspense>
      }
      description="Datos, ingredientes y costos, rendimiento, procedimiento y versiones."
    >
      <Suspense fallback={<Loading />}>
        <Recipe params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const recipeById = cache(getRecipe);

async function RecipeName({ params }: { params: PageProps<"/recetas/[id]">["params"] }) {
  await requireMenu("recipes");
  const { id } = await params;
  if (!UUID.test(id)) return "Receta";
  return (await recipeById(id))?.name ?? "Receta";
}

const STATUS_BADGE: Record<VersionStatus, BadgeStatus> = {
  draft: "draft",
  in_review: "review",
  approved: "ok",
  published: "ok",
  archived: "neutral",
};

const ALLERGEN_BADGE: Record<string, BadgeStatus> = {
  contains: "bad",
  may_contain: "warn",
  free_verified: "ok",
  not_verified: "neutral",
};

// El índice de la ficha (enlaces que bajan a cada sección).
const SECTIONS = [
  { key: "datos", label: "Datos generales" },
  { key: "ingredientes", label: "Ingredientes y costos" },
  { key: "rendimiento", label: "Rendimiento" },
  { key: "procedimiento", label: "Procedimiento" },
  { key: "alergenos", label: "Alérgenos" },
  { key: "uso", label: "Dónde se usa" },
  { key: "versiones", label: "Versiones y aprobaciones" },
] as const;

// Las direcciones de antes (?seccion=) bajan a la sección que corresponde.
const OLD_SECTION: Record<string, string> = {
  datos: "datos",
  ingredientes: "ingredientes",
  rendimientos: "rendimiento",
  procedimiento: "procedimiento",
  costos: "ingredientes",
  alergenos: "alergenos",
  fotos: "fotos",
  versiones: "versiones",
  uso: "uso",
};

function Reason({ id, label = "Motivo" }: { id: string; label?: string }) {
  return (
    <FormTextarea
      id={id}
      name="reason"
      label={label}
      hint="Queda en el historial."
      required
      maxLength={500}
    />
  );
}

function DiffList({ rows, label }: { rows: DiffRow[]; label: string }) {
  return (
    <ul className="flex flex-col gap-2" aria-label={label}>
      {rows.map((d) => (
        <li key={`${d.change}-${d.ingredient}-${d.unit}`} className="text-ink">
          {d.change === "added"
            ? `Se agrega ${d.ingredient}: ${formatQuantity(d.newQuantity)} ${d.unit}`
            : d.change === "removed"
              ? `Se quita ${d.ingredient} (${formatQuantity(d.oldQuantity)} ${d.unit})`
              : `${d.ingredient}: de ${formatQuantity(d.oldQuantity)} a ${formatQuantity(d.newQuantity)} ${d.unit}`}
        </li>
      ))}
    </ul>
  );
}

function Ids({ recipe, version }: { recipe: RecipeDetail; version?: RecipeVersion | null }) {
  return (
    <>
      <input type="hidden" name="recipeId" value={recipe.id} />
      {version ? <input type="hidden" name="versionId" value={version.id} /> : null}
      {version ? <input type="hidden" name="expectedUpdatedAt" value={version.updatedAt} /> : null}
    </>
  );
}

const linkClass =
  "inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-control";

async function Recipe({
  params,
  searchParams,
}: {
  params: PageProps<"/recetas/[id]">["params"];
  searchParams: PageProps<"/recetas/[id]">["searchParams"];
}) {
  const session = await requireMenu("recipes");
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const recipe = await recipeById(id);
  if (!recipe) notFound();
  const works = recipe.can.draft || recipe.can.review || recipe.can.publish;
  // Quien solo ve la receta, la ve como en la cocina.
  if (!works) redirect(`/recetas/${recipe.id}/cocina`);

  const query = await searchParams;
  // Cada ancla lleva el comienzo del id de la receta: Next guarda oculta la ficha anterior, y con dos «#uso» un
  // enlace podría bajar a la oculta.
  const anchor = (key: string) => `${key}-${recipe.id.slice(0, 8)}`;
  const old = first(query.seccion);
  if (old && OLD_SECTION[old]) redirect(`/recetas/${recipe.id}#${anchor(OLD_SECTION[old])}`);

  const version = recipe.open ?? recipe.current;
  const returned =
    version?.status === "in_review" &&
    (version.requestStatus === "rejected" || version.requestStatus === "cancelled");
  // Se edita un borrador, uno que volvió de la revisión o la vigente sin borrador abierto (al guardar, nace el
  // borrador). En revisión no se edita: la base tampoco lo deja.
  const editable =
    Boolean(version) &&
    recipe.can.draft &&
    recipe.isActive &&
    (version?.status === "draft" || returned || (version?.status === "published" && !recipe.open));
  const reviewing =
    version?.status === "in_review" &&
    !returned &&
    recipe.can.publish &&
    Boolean(version.requestId);
  const showMasterDiff = Boolean(recipe.variantOf?.name);
  const [content, summary, diff, assignments, categories, photos, usage, variants, masterDiff] =
    await Promise.all([
      version ? getVersionContent(version.id) : Promise.resolve({ lines: [], steps: [] }),
      version
        ? getVersionSummary(version.id)
        : Promise.resolve({ totalMinutes: 0, activeMinutes: 0, allergens: [] }),
      recipe.open && recipe.open.number > 1 ? getVersionDiff(recipe.open.id) : Promise.resolve([]),
      getAssignments(recipe),
      getRecipeCategories(),
      version ? getVersionPhotos(version.id) : Promise.resolve({ photos: [], failed: false }),
      getRecipeUsage(recipe.id),
      recipe.scope !== "restaurant" ? getVariants(recipe.id) : Promise.resolve([]),
      showMasterDiff ? getVariantDiff(recipe.id) : Promise.resolve([]),
    ]);
  const variantPlaces = recipe.can.variantPlaces.filter(
    (p) => !variants.some((v) => v.restaurantId === p.restaurantId),
  );
  const menus = await getMenus();
  const costPlace = menus.costs ? (await resolveCostPlace(session.user_id)).place : null;
  const [unitOptions, prices] = await Promise.all([
    unitOptionsAction(content.lines.flatMap((l) => (l.ingredientId ? [l.ingredientId] : []))),
    costPlace ? hasPermissionIn("prices.view", costPlace.id) : Promise.resolve(false),
  ]);
  const volver = first(query.volver);
  const back = volver && /^\/recetas(\?|$)/.test(volver) ? volver : "/recetas";
  const [timesA, timesB] = (first(query.hacer) ?? "").split(",");
  const times: [number, number] = [parseTimes(timesA ?? "") ?? 4, parseTimes(timesB ?? "") ?? 10];
  const category = categories.find((c) => c.id === recipe.categoryId);
  // Un plato va en un rubro de menú; lo demás, en uno de sub-recetas (ADR-0038).
  const categoryOptions = categories
    .filter(
      (c) =>
        c.id === recipe.categoryId ||
        (c.isActive && c.kind === (recipe.type === "dish" ? "menu" : "subrecipe")),
    )
    .map((c) => ({ id: c.id, label: c.label }));
  // Lo que cambió contra la versión anterior, marcado en la grilla de quien revisa.
  const marks = Object.fromEntries(
    diff
      .filter((d) => d.change === "added" || d.change === "changed")
      .map((d) => [d.ingredient, d.change as "added" | "changed"]),
  );
  const codeNotice =
    first(query.aviso) === "codigo" && (await createdRecently("recipe", recipe.id))
      ? codeNoticeFromQuery(first(query.aviso), first(query.previsto), recipe.code)
      : null;

  return (
    <>
      <BackLink href={back}>Volver a recetas</BackLink>
      {codeNotice ? <Notice status="info">{codeNotice}</Notice> : null}
      {first(query.aviso) === "guardado" ? (
        <Notice status="ok" role="status">
          Cambios guardados.
          {recipe.open && recipe.current
            ? " Van en el borrador: la versión vigente sigue igual hasta que se publique."
            : ""}
        </Notice>
      ) : first(query.aviso) === "porciones" ? (
        <Notice status="warn" role="status">
          Cambios guardados, pero las porciones no se recalcularon: falta pasar algún ingrediente a
          gramos (densidad o peso por unidad, en su ficha). Para enviarla a revisión hace falta.
        </Notice>
      ) : first(query.aviso) === "aprobada" ? (
        <Notice status="ok" role="status">
          Aprobada y publicada: ya es la versión vigente en las cocinas.
        </Notice>
      ) : first(query.aviso) === "no-aprobada" ? (
        <Notice status="warn" role="status">
          No aprobada: vuelve a borrador con tus observaciones.
        </Notice>
      ) : first(query.aviso) === "revision" && recipe.open?.status === "in_review" ? (
        <Notice status="info" role="status">
          Cambios guardados y enviados a revisión: la tiene que aprobar otra persona con permiso de
          publicar.
        </Notice>
      ) : null}

      {/* 1. Encabezado: datos a la izquierda, fotos a la derecha. */}
      <Card className="flex flex-col gap-4 desk:flex-row desk:items-start desk:justify-between">
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          <span className="flex flex-wrap items-center gap-2">
            {!recipe.isActive ? <Badge status="none">Archivada</Badge> : null}
            {recipe.variantOf ? <Badge status="info">Variante</Badge> : null}
            {recipe.open ? (
              <Badge status={STATUS_BADGE[recipe.open.status]}>
                {VERSION_STATUS_LABELS[recipe.open.status]} v{recipe.open.number}
              </Badge>
            ) : null}
            {recipe.current ? <Badge status="ok">Vigente v{recipe.current.number}</Badge> : null}
          </span>
          {/* El nombre ya es el título de la pantalla: acá van sus datos. */}
          <span className="text-base text-ink tabular-nums">
            {recipe.code} · {RECIPE_TYPE_LABELS[recipe.type]} · {recipe.place}
          </span>
          <span className="text-sm text-ink-muted">
            Rubro: {category?.label ?? "sin rubro"} · Alcance: {SCOPE_LABELS[recipe.scope]}
            {recipe.variantOf?.name ? (
              <>
                {" · Variante de "}
                <Link href={`/recetas/${recipe.variantOf.id}`} className={linkClass}>
                  {recipe.variantOf.name}
                </Link>
              </>
            ) : null}
          </span>
          <nav aria-label="Secciones de la receta">
            <ul className="flex flex-wrap gap-2">
              {SECTIONS.map((s) => (
                <li key={s.key}>
                  <a
                    href={`#${anchor(s.key)}`}
                    className="inline-flex min-h-touch items-center rounded-sm border border-line px-3 text-sm text-ink hover:bg-line/50 desk:min-h-control-sm"
                  >
                    {s.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
          <div className="flex flex-wrap gap-2">
            {recipe.current ? (
              <Button asChild variant="outline">
                <Link href={`/recetas/${recipe.id}/cocina`}>
                  <ChefHat aria-hidden="true" />
                  Ver la ficha de cocina
                </Link>
              </Button>
            ) : null}
            {recipe.current ? (
              <Button asChild variant="outline">
                <Link href={`/recetas/${recipe.id}/escalar`}>
                  <Scale aria-hidden="true" />
                  Escalar
                </Link>
              </Button>
            ) : null}
          </div>
        </div>
        <PhotoCarousel
          id={anchor("fotos")}
          recipeId={recipe.id}
          set={photos}
          canAdd={Boolean(editable && version?.status !== "published")}
          hint={
            editable && version?.status === "published"
              ? "Las fotos van en el borrador: guardá un cambio y se agregan desde acá."
              : undefined
          }
        />
      </Card>

      {returned && version ? (
        <Notice status="warn" role="status">
          La revisión {version.requestStatus === "rejected" ? "fue rechazada" : "se retiró"}:
          corregí la versión y enviala a revisión de nuevo.
        </Notice>
      ) : version?.status === "in_review" ? (
        <Notice status="info">
          Está en revisión: la tiene que aprobar otra persona con permiso de publicar. Mientras
          tanto no se edita.
        </Notice>
      ) : null}
      {recipe.open && recipe.current ? (
        <p className="text-sm text-ink-muted">
          Versión en preparación (v{recipe.open.number}). La vigente (v{recipe.current.number})
          sigue en las cocinas hasta que se publique esta.
        </p>
      ) : editable && version?.status === "published" ? (
        <p className="text-sm text-ink-muted">
          Ves la versión vigente (v{version.number}). Si la cambiás, al guardar se crea un borrador:
          la vigente sigue igual hasta que se publique.
        </p>
      ) : null}

      {version ? (
        <SheetEditor
          anchorSuffix={recipe.id.slice(0, 8)}
          key={`${version.id}-${version.updatedAt}`}
          recipe={{
            id: recipe.id,
            type: recipe.type,
            name: recipe.name,
            shortName: recipe.shortName,
            categoryId: recipe.categoryId,
            sector: recipe.sector,
            station: recipe.station,
          }}
          version={version}
          categories={categoryOptions}
          lines={content.lines}
          steps={content.steps}
          unitOptions={unitOptions}
          editable={Boolean(editable)}
          canSubmit={recipe.can.review && recipe.isActive}
          place={costPlace}
          money={menus.costs}
          prices={prices}
          totalMinutes={summary.totalMinutes}
          marks={reviewing ? marks : {}}
          times={times}
        />
      ) : (
        <EmptyState title="Esta receta todavía no tiene una versión.">
          Se crea con «Crear una versión nueva», en «Versiones y aprobaciones».
        </EmptyState>
      )}

      {/* 6. Alérgenos y Dónde se usa */}
      <div className="grid gap-4 desk:grid-cols-2">
        <Card id={anchor("alergenos")} className="flex scroll-mt-24 flex-col gap-4">
          <CardTitle>Alérgenos</CardTitle>
          <CardDescription>
            Salen solos de las materias primas y preparaciones de la lista. Si alguna no tiene el
            dato, queda «no verificado»: nunca «sin alérgenos» por falta de datos.
          </CardDescription>
          {summary.allergens.length === 0 ? (
            <p className="text-base text-ink-muted">Contiene: ninguno declarado.</p>
          ) : (
            <ul className="flex flex-wrap gap-2" aria-label="Alérgenos">
              {summary.allergens.map((a) => (
                <li key={a.name}>
                  <Badge status={ALLERGEN_BADGE[a.status] ?? "neutral"}>
                    {a.name}: {ALLERGEN_LABELS[a.status] ?? a.status}
                  </Badge>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card id={anchor("uso")} className="flex scroll-mt-24 flex-col gap-4">
          <CardTitle>Dónde se usa</CardTitle>
          {usage.length > 0 || recipe.type !== "dish" ? (
            <section className="flex flex-col gap-2" aria-labelledby={anchor("uso-recetas")}>
              <h3 id={anchor("uso-recetas")} className="text-base font-semibold text-ink">
                Recetas que la usan como preparación
              </h3>
              {usage.length === 0 ? (
                <p className="text-base text-ink-muted">Ninguna receta la usa todavía.</p>
              ) : (
                <ul className="flex flex-col gap-1" aria-label="Recetas que la usan">
                  {usage.map((u) => (
                    <li key={u.id} className="flex flex-wrap items-center justify-between gap-2">
                      <Link href={`/recetas/${u.id}`} className={linkClass}>
                        {u.name}
                      </Link>
                      <Badge status={STATUS_BADGE[u.status]}>
                        {VERSION_STATUS_LABELS[u.status]}
                      </Badge>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          ) : null}

          <section className="flex flex-col gap-2" aria-labelledby={anchor("uso-locales")}>
            <h3 id={anchor("uso-locales")} className="text-base font-semibold text-ink">
              Locales que la usan
            </h3>
            {assignments.current.length === 0 ? (
              <p className="text-base text-ink-muted">Todavía no se usa en ningún local.</p>
            ) : (
              <ul className="flex flex-col gap-2" aria-label="Locales que la usan">
                {assignments.current.map((a) => (
                  <li key={a.restaurantId} className="flex flex-col gap-2">
                    <span className="text-ink">{a.restaurant}</span>
                    {recipe.can.assign && recipe.scope !== "restaurant" ? (
                      <Disclosure summary={`Dejar de usarla en ${a.restaurant}`}>
                        <ActionForm
                          action={assignAction}
                          schema="assignment"
                          submitLabel="Dejar de usarla"
                          variant="outline"
                        >
                          <Ids recipe={recipe} />
                          <input type="hidden" name="restaurant_id" value={a.restaurantId} />
                          <input type="hidden" name="assigned" value="false" />
                          <Reason id={`rec-${recipe.id}-motivo-desasignar-${a.restaurantId}`} />
                        </ActionForm>
                      </Disclosure>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
            {recipe.can.assign && recipe.isActive && assignments.available.length > 0 ? (
              <Disclosure summary="Asignar a un local">
                <ActionForm action={assignAction} schema="assignment" submitLabel="Asignar">
                  <Ids recipe={recipe} />
                  <FormSelect
                    id={`rec-${recipe.id}-asignar-local`}
                    label="Local"
                    name="restaurant_id"
                    required
                    defaultValue=""
                  >
                    <option value="" disabled>
                      Elegí el local
                    </option>
                    {assignments.available.map((a) => (
                      <option key={a.restaurantId} value={a.restaurantId}>
                        {a.restaurant}
                      </option>
                    ))}
                  </FormSelect>
                  <Reason id={`rec-${recipe.id}-motivo-asignar`} />
                </ActionForm>
              </Disclosure>
            ) : null}
          </section>

          {variants.length > 0 || variantPlaces.length > 0 ? (
            <section className="flex flex-col gap-2" aria-labelledby={anchor("uso-variantes")}>
              <h3 id={anchor("uso-variantes")} className="text-base font-semibold text-ink">
                Variantes de local
              </h3>
              <p className="text-sm text-ink-muted">
                Un local puede tener su versión de esta receta. Cuando se publica, ese local deja de
                usar la maestra.
              </p>
              {variants.length === 0 ? (
                <p className="text-base text-ink-muted">No tiene variantes.</p>
              ) : (
                <ul className="flex flex-col gap-1" aria-label="Variantes">
                  {variants.map((v) => (
                    <li key={v.id} className="flex flex-wrap items-center justify-between gap-2">
                      <Link href={`/recetas/${v.id}`} className={linkClass}>
                        {v.name}
                      </Link>
                      <span className="text-sm text-ink-muted">{v.restaurant}</span>
                    </li>
                  ))}
                </ul>
              )}
              {variantPlaces.length > 0 ? (
                <Disclosure summary="Crear una variante para un local">
                  <p className="text-base text-ink">
                    Hacemos una copia de la receta vigente para ese local, con el código{" "}
                    {recipe.code}-V01 (o el siguiente). Después la ajustás y la enviás a revisión.
                  </p>
                  <ActionForm
                    action={createVariantAction}
                    schema="variant"
                    submitLabel="Crear variante"
                  >
                    <Ids recipe={recipe} />
                    <FormSelect
                      id={`rec-${recipe.id}-variante-local`}
                      label="Local"
                      name="restaurant_id"
                      required
                      defaultValue=""
                    >
                      <option value="" disabled>
                        Elegí el local
                      </option>
                      {variantPlaces.map((a) => (
                        <option key={a.restaurantId} value={a.restaurantId}>
                          {a.restaurant}
                        </option>
                      ))}
                    </FormSelect>
                    <FormInput
                      id={`rec-${recipe.id}-variante-nombre`}
                      label="Nombre de la variante"
                      name="name"
                      hint={`Por ejemplo: «${recipe.name} (Centro)».`}
                      required
                      maxLength={120}
                    />
                    <Reason id={`rec-${recipe.id}-motivo-variante`} />
                  </ActionForm>
                </Disclosure>
              ) : null}
            </section>
          ) : null}

          {showMasterDiff ? (
            <section className="flex flex-col gap-2" aria-labelledby={anchor("uso-maestra")}>
              <h3 id={anchor("uso-maestra")} className="text-base font-semibold text-ink">
                Diferencias con la maestra
              </h3>
              {masterDiff.length === 0 ? (
                <p className="text-base text-ink-muted">No cambia nada respecto de la maestra.</p>
              ) : (
                <DiffList rows={masterDiff} label="Diferencias con la maestra" />
              )}
            </section>
          ) : null}
        </Card>
      </div>

      {/* 7. Versiones y aprobaciones */}
      <Card id={anchor("versiones")} className="flex scroll-mt-24 flex-col gap-4">
        <CardTitle>Versiones y aprobaciones</CardTitle>
        <div className="grid gap-4 desk:grid-cols-2">
          <div className="flex flex-col gap-4">
            <ul className="flex flex-col gap-2" aria-label="Versiones">
              {recipe.versions.map((v) => (
                <li
                  key={v.id}
                  className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-0"
                >
                  <span className="text-ink">
                    Versión {v.number}
                    {v.changeSummary ? ` · ${v.changeSummary}` : ""}
                    {v.publishedAt ? ` · publicada ${formatDateTime(v.publishedAt)}` : ""}
                  </span>
                  <Badge status={STATUS_BADGE[v.status]}>{VERSION_STATUS_LABELS[v.status]}</Badge>
                </li>
              ))}
            </ul>
            {recipe.open && diff.length > 0 ? (
              <section className="flex flex-col gap-2" aria-labelledby={anchor("cambios-version")}>
                <h3 id={anchor("cambios-version")} className="text-base font-semibold text-ink">
                  Cambios contra la versión anterior
                </h3>
                <DiffList rows={diff} label="Cambios" />
              </section>
            ) : null}
            <div className="flex flex-col gap-2">
              {/* En la computadora se envía con la barra de la ficha; en el celular, desde acá. */}
              {version?.status === "draft" && recipe.can.review && recipe.isActive ? (
                <div className="desk:hidden">
                  <Disclosure summary="Pedir la revisión">
                    <p className="text-base text-ink">
                      Otra persona con permiso de publicar la revisa. Al aprobarla, queda vigente en
                      las cocinas.
                    </p>
                    <ActionForm
                      action={requestReviewAction}
                      schema="reason"
                      submitLabel="Pedir la revisión"
                    >
                      <Ids recipe={recipe} version={version} />
                      <Reason id={`rec-${recipe.id}-motivo-revision`} />
                    </ActionForm>
                  </Disclosure>
                </div>
              ) : null}
              {version?.status === "in_review" && !returned ? (
                <Disclosure summary="Retirar de revisión">
                  <p className="text-base text-ink">
                    Solo la retira quien la envió a revisión. Vuelve a borrador.
                  </p>
                  <ActionForm
                    action={withdrawReviewAction}
                    schema="reason"
                    submitLabel="Retirar"
                    variant="outline"
                  >
                    <Ids recipe={recipe} version={version} />
                    <Reason id={`rec-${recipe.id}-motivo-retiro`} />
                  </ActionForm>
                </Disclosure>
              ) : null}
              {!recipe.open && recipe.can.draft && recipe.isActive ? (
                <Disclosure summary="Crear una versión nueva">
                  <p className="text-base text-ink">
                    Copia la vigente en un borrador (también se crea sola al guardar un cambio). La
                    vigente sigue en las cocinas hasta que se publique la nueva.
                  </p>
                  <ActionForm
                    action={newVersionAction}
                    schema="reason"
                    submitLabel="Crear versión nueva"
                  >
                    <Ids recipe={recipe} />
                    <Reason id={`rec-${recipe.id}-motivo-version`} />
                  </ActionForm>
                </Disclosure>
              ) : null}
              {recipe.can.archive && recipe.isActive ? (
                <Disclosure summary="Archivar la receta">
                  <p className="text-base text-ink">
                    Deja de usarse en todas las cocinas. Su historia se conserva.
                  </p>
                  <ActionForm
                    action={archiveRecipeAction}
                    schema="reason"
                    submitLabel="Archivar"
                    variant="destructive"
                  >
                    <Ids recipe={recipe} />
                    <Reason id={`rec-${recipe.id}-motivo-archivo`} label="Motivo del archivo" />
                  </ActionForm>
                </Disclosure>
              ) : null}
            </div>
          </div>
          {reviewing && version?.requestId ? (
            <ReviewBox recipeId={recipe.id} requestId={version.requestId} />
          ) : null}
        </div>
      </Card>
    </>
  );
}
