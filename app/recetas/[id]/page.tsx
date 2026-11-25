import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense, cache, type ReactNode } from "react";
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
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { Disclosure } from "@/components/disclosure";
import { FocusTarget } from "@/components/focus-target";
import { PhotoCarousel } from "@/components/recipe-sheet/photo-carousel";
import { ReviewBox } from "@/components/recipe-sheet/review-box";
import { SheetEditor } from "@/components/recipe-sheet/sheet-editor";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { codeNoticeFromQuery } from "@/lib/codes";
import { resolveCostPlace } from "@/lib/costs";
import { UUID, first, formatDate, formatDateTime, getInbox } from "@/lib/data";
import { parseTimes, reviewMark } from "@/lib/recipe-sheet";
import { unitOptionsAction } from "@/app/recetas/actions";
import {
  ALLERGEN_LABELS,
  RECIPE_TYPE_LABELS,
  SCOPE_LABELS,
  VERSION_STATUS_LABELS,
  versionChip,
  createdRecently,
  formatQuantity,
  getAssignments,
  getRecipe,
  getRecipeCategories,
  getRecipeUsage,
  getVariantDiff,
  getVariants,
  getVersionContent,
  getKitchenLists,
  getMeasureMarks,
  getRecipeIngredientCategories,
  getVersionDiff,
  getVersionPhotos,
  getVersionSummary,
  hasPermissionIn,
  type DiffRow,
  type RecipeDetail,
  type RecipeVersion,
  type VersionStatus,
} from "@/lib/recipes";

// Ficha de receta en una pantalla (ADR-0047; antes, la ficha única del ADR-0042 con un índice y 7 secciones): encabezado
// en una línea, 4 indicadores y dos columnas que ocupan el alto que queda. La planilla de ingredientes es la única parte
// con scroll propio, como una hoja de cálculo. Lo que no entra se abre en un panel (datos, pasos, alérgenos, dónde se
// usa y versiones). Quien la trabaja edita donde ve y guarda todo junto; quien revisa la ve en solo lectura con los
// cambios marcados y decide en la barra de abajo; quien solo la ve va a las fichas técnicas. En el celular, consulta.
export default function RecetaPage({ params, searchParams }: PageProps<"/recetas/[id]">) {
  return (
    <AppShell
      title="Receta"
      fill
      heading={
        <Suspense fallback="Receta">
          <RecipeName params={params} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back searchParams={searchParams} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <HeaderActions params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Recipe params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const recipeById = cache(getRecipe);
const categoriesOnce = cache(getRecipeCategories);

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

// Las direcciones de antes (?seccion=, Calidad) llevan el foco a la tarjeta que corresponde (FocusTarget).
const OLD_SECTION: Record<string, string> = {
  datos: "datos",
  fotos: "datos",
  ingredientes: "ingredientes",
  costos: "ingredientes",
  rendimiento: "rendimiento",
  rendimientos: "rendimiento",
  procedimiento: "procedimiento",
  alergenos: "alergenos",
  uso: "uso",
  versiones: "versiones",
};

// Los avisos después de guardar o decidir. En la computadora, quien edita los ve en la barra de abajo (pantalla sin
// scroll, ADR-0046); en el celular, y quien no edita, arriba.
type SavedNotice = { status: "ok" | "info" | "warn"; text: string };
function savedNotice(aviso: string | undefined, recipe: RecipeDetail): SavedNotice | null {
  switch (aviso) {
    case "guardado":
      return {
        status: "ok",
        text:
          recipe.open && recipe.current
            ? "Cambios guardados. Van en el borrador: la vigente sigue igual hasta que se publique."
            : "Cambios guardados.",
      };
    case "porciones":
      return {
        status: "warn",
        text: "Cambios guardados, pero las porciones no se recalcularon: falta pasar algún ingrediente a gramos (densidad o peso por unidad, en su ficha). Para enviarla a revisión hace falta.",
      };
    case "aprobada":
      return {
        status: "ok",
        text: "Aprobada y publicada: ya es la versión vigente en las cocinas.",
      };
    case "no-aprobada":
      return { status: "warn", text: "No aprobada: vuelve a borrador con tus observaciones." };
    case "revision":
      return recipe.open?.status === "in_review"
        ? {
            status: "info",
            text: "Cambios guardados y enviados a revisión: la tiene que aprobar otra persona con permiso de publicar.",
          }
        : null;
    default:
      return null;
  }
}

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

// A dónde vuelve «← Recetas»: el listado con sus filtros, si vino de ahí.
function backHref(volver: string | undefined): string {
  return volver && /^\/recetas(\?|$)/.test(volver) ? volver : "/recetas";
}

async function Back({
  searchParams,
}: {
  searchParams: PageProps<"/recetas/[id]">["searchParams"];
}) {
  const query = await searchParams;
  return (
    <BackLink href={backHref(first(query.volver))} label="Volver a recetas">
      Recetas
    </BackLink>
  );
}

// La versión que se ve (la abierta o, si no hay, la vigente) y si quien mira la trabaja.
function versionOf(recipe: RecipeDetail) {
  return recipe.open ?? recipe.current;
}

// La línea del nombre: código · rubro · Plato o Preparación, y los estados con palabra.
async function Meta({ params }: { params: PageProps<"/recetas/[id]">["params"] }) {
  await requireMenu("recipes");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  const [recipe, categories] = await Promise.all([recipeById(id), categoriesOnce()]);
  if (!recipe) return null;
  const category = categories.find((c) => c.id === recipe.categoryId);
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">
        <span>{recipe.code}</span>
        {` · ${category?.label ?? "Sin rubro"} · ${RECIPE_TYPE_LABELS[recipe.type]}`}
      </span>
      {!recipe.isActive ? <Badge status="none">Archivada</Badge> : null}
      {recipe.variantOf ? (
        // De qué receta maestra es la variante, con su enlace.
        <span className="inline-flex items-center gap-1 text-sm text-ink-muted">
          <Badge status="info">Variante</Badge>
          {recipe.variantOf.name ? (
            <>
              de
              <Link href={`/recetas/${recipe.variantOf.id}`} className={linkClass}>
                {recipe.variantOf.name}
              </Link>
            </>
          ) : null}
        </span>
      ) : null}
      {/* «Versión 3 · Borrador» y, al lado, cuál está vigente y desde cuándo (ADR-0064). */}
      {recipe.open ? (
        <Badge status={STATUS_BADGE[recipe.open.status]}>
          {versionChip(recipe.open.number, recipe.open.status)}
        </Badge>
      ) : recipe.current ? (
        <Badge status="ok">{versionChip(recipe.current.number, "published")}</Badge>
      ) : null}
      {recipe.current ? (
        <span className="inline-flex items-center text-xs text-ink-muted">
          {recipe.open ? `vigente: versión ${recipe.current.number} del ` : "desde el "}
          {recipe.current.publishedAt ? formatDate(recipe.current.publishedAt) : "—"}
          {recipe.open ? (
            <InfoTip label="las versiones" className="desk:size-8">
              La versión {recipe.open.number} está en preparación. La vigente (versión{" "}
              {recipe.current.number}) sigue en las cocinas hasta que se publique la nueva.
            </InfoTip>
          ) : recipe.can.draft && recipe.isActive ? (
            <InfoTip label="la versión vigente" className="desk:size-8">
              Ves la versión vigente. Si la cambiás, al guardar se crea un borrador: la vigente
              sigue igual hasta que se publique.
            </InfoTip>
          ) : null}
        </span>
      ) : null}
    </>
  );
}

// «Fichas técnicas» y «Hacer varias», a la derecha del nombre (solo con una versión vigente).
async function HeaderActions({ params }: { params: PageProps<"/recetas/[id]">["params"] }) {
  await requireMenu("recipes");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  const recipe = await recipeById(id);
  if (!recipe?.current) return null;
  return (
    <div className="flex flex-wrap gap-2 desk:shrink-0 desk:flex-nowrap">
      <Button asChild variant="outline" size="sm">
        <Link href={`/recetas/${recipe.id}/fichas`}>
          <ChefHat aria-hidden="true" />
          Fichas técnicas
        </Link>
      </Button>
      <Button asChild variant="outline" size="sm">
        <Link href={`/recetas/${recipe.id}/escalar`}>
          <Scale aria-hidden="true" />
          Hacer varias
        </Link>
      </Button>
    </div>
  );
}

// Quién pidió la revisión, cuándo y por qué (la bandeja de aprobaciones, workflow.inbox). Si no se puede leer, la
// franja dice lo que sabe, sin inventar el resto. La bandeja devuelve hasta 100 pendientes: con más, puede faltar y la
// franja muestra solo la versión (pendiente: una lectura puntual por id, que pide una migración).
async function reviewRequest(requestId: string | null) {
  if (!requestId) return null;
  try {
    const rows = await getInbox(true, 100);
    return rows.find((r) => r.id === requestId) ?? null;
  } catch {
    return null;
  }
}

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
  // Quien solo ve la receta, la ve en sus fichas técnicas.
  if (!works) redirect(`/recetas/${recipe.id}/fichas`);

  const query = await searchParams;
  // Cada tarjeta lleva el comienzo del id de la receta: Next guarda oculta la ficha anterior, y con dos «#uso» un
  // enlace podría llevar a la oculta.
  const anchor = (key: string) => `${key}-${recipe.id.slice(0, 8)}`;
  const back = backHref(first(query.volver));
  const old = first(query.seccion);
  if (old && OLD_SECTION[old]) {
    const q = back !== "/recetas" ? `?${new URLSearchParams({ volver: back })}` : "";
    redirect(`/recetas/${recipe.id}${q}#${anchor(OLD_SECTION[old])}`);
  }

  const version = versionOf(recipe);
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
      categoriesOnce(),
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
  const ingredientIds = content.lines.flatMap((l) => (l.ingredientId ? [l.ingredientId] : []));
  const [unitInfo, lists, ingredientCategories, measureMarks, prices, request] = await Promise.all([
    unitOptionsAction(ingredientIds),
    getKitchenLists(recipe.groupId),
    editable && menus.createIngredients
      ? getRecipeIngredientCategories(recipe.groupId)
      : Promise.resolve([]),
    reviewing && version ? getMeasureMarks(version.id) : Promise.resolve({}),
    costPlace ? hasPermissionIn("prices.view", costPlace.id) : Promise.resolve(false),
    version?.status === "in_review" ? reviewRequest(version.requestId) : Promise.resolve(null),
  ]);
  const [timesA, timesB] = (first(query.hacer) ?? "").split(",");
  const times: [number, number] = [parseTimes(timesA ?? "") ?? 4, parseTimes(timesB ?? "") ?? 10];
  // Un plato va en un rubro de menú; lo demás, en uno de sub-recetas (ADR-0038).
  const categoryOptions = categories
    .filter(
      (c) =>
        c.id === recipe.categoryId ||
        (c.isActive && c.kind === (recipe.type === "dish" ? "menu" : "subrecipe")),
    )
    .map((c) => ({ id: c.id, label: c.label }));
  // Lo que cambió contra la versión anterior, marcado en la planilla de quien revisa («antes 380 g» o «Nueva»).
  const marks: Record<string, string> = { ...measureMarks };
  for (const d of diff) {
    const label = reviewMark(d);
    if (label) marks[d.ingredient] = [label, marks[d.ingredient]].filter(Boolean).join(" · ");
  }
  const codeNotice =
    first(query.aviso) === "codigo" && (await createdRecently("recipe", recipe.id))
      ? codeNoticeFromQuery(first(query.aviso), first(query.previsto), recipe.code)
      : null;
  const saved = savedNotice(first(query.aviso), recipe);

  // La franja de una versión en revisión: quién la pidió, cuándo y el motivo, en una línea.
  const requestLine = request
    ? ` v${version?.number} pedida${request.requested_by_name ? ` por ${request.requested_by_name}` : ""} el ${formatDate(request.requested_at)} · Motivo: «${request.reason}».`
    : ` v${version?.number}.`;

  return (
    <>
      <FocusTarget />
      {codeNotice ? <Notice status="info">{codeNotice}</Notice> : null}
      {saved ? (
        <Notice status={saved.status} className={editable ? "desk:hidden" : undefined}>
          {saved.text}
        </Notice>
      ) : null}
      {returned && version ? (
        <Notice status="warn" className="py-2 text-sm">
          La revisión {version.requestStatus === "rejected" ? "fue rechazada" : "se retiró"}:
          corregí la versión y enviala a revisión de nuevo.
        </Notice>
      ) : version?.status === "in_review" ? (
        <Notice status="review" className="py-2 text-sm">
          <span className="font-semibold">Está en revisión:</span>
          {requestLine}{" "}
          {reviewing
            ? "Ves la ficha sin poder editarla; los cambios están marcados."
            : "La tiene que aprobar otra persona con permiso de publicar. Mientras tanto no se edita."}
        </Notice>
      ) : null}
      {/* Quien revisa en el celular decide acá (las aprobaciones son de celular, ADR-0036); en la computadora, en la
          barra de abajo. */}
      {reviewing && version?.requestId ? (
        <div className="desk:hidden">
          <ReviewBox recipeId={recipe.id} requestId={version.requestId} />
        </div>
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
            sectorId: recipe.sectorId,
            stationId: recipe.stationId,
            groupId: recipe.groupId,
          }}
          version={version}
          categories={categoryOptions}
          scopeLabel={SCOPE_LABELS[recipe.scope]}
          lines={content.lines}
          steps={content.steps}
          unitOptions={Object.fromEntries(Object.entries(unitInfo).map(([k, v]) => [k, v.dims]))}
          unitWeights={Object.fromEntries(
            Object.entries(unitInfo).flatMap(([k, v]) =>
              v.unitWeight === null ? [] : [[k, v.unitWeight]],
            ),
          )}
          lists={lists}
          canAddIngredient={Boolean(editable && menus.createIngredients)}
          canAddToLists={Boolean(editable && menus.kitchenLists)}
          ingredientCategories={ingredientCategories}
          editable={Boolean(editable)}
          canSubmit={recipe.can.review && recipe.isActive}
          place={costPlace}
          money={menus.costs}
          prices={prices}
          totalMinutes={summary.totalMinutes}
          marks={reviewing ? marks : {}}
          review={
            reviewing && version.requestId
              ? {
                  requestId: version.requestId,
                  // Lo que se ve marcado en la planilla (filas nuevas o cambiadas); lo quitado se cuenta aparte.
                  changes: Object.keys(marks).length,
                  removed: diff.filter((d) => d.change === "removed").length,
                }
              : null
          }
          notice={editable ? saved : null}
          times={times}
          photos={
            <PhotoCarousel
              compact
              id={anchor("fotos")}
              recipeId={recipe.id}
              set={photos}
              canAdd={Boolean(editable && version.status !== "published")}
            />
          }
          mobilePhotos={
            <PhotoCarousel
              id={`${anchor("fotos")}-celular`}
              recipeId={recipe.id}
              set={photos}
              canAdd={Boolean(editable && version.status !== "published")}
            />
          }
          summary={
            <Summary
              anchor={anchor}
              recipe={recipe}
              version={version}
              returned={Boolean(returned)}
              allergens={summary.allergens}
              usage={usage}
              assignments={assignments}
              variants={variants}
              variantPlaces={variantPlaces}
              masterDiff={showMasterDiff ? masterDiff : null}
              diff={diff}
            />
          }
        />
      ) : (
        <EmptyState title="Esta receta todavía no tiene una versión.">
          {recipe.can.draft && recipe.isActive ? (
            <ActionModal label="Crear una versión nueva" title="Crear una versión nueva">
              <ActionForm
                action={newVersionAction}
                schema="reason"
                submitLabel="Crear versión nueva"
              >
                <Ids recipe={recipe} />
                <Reason id={`rec-${recipe.id}-motivo-version-vacia`} />
              </ActionForm>
            </ActionModal>
          ) : (
            "La tiene que crear alguien que trabaje la receta."
          )}
        </EmptyState>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// La franja de resumen de la columna derecha: Alérgenos, Dónde se usa y Versiones, cada uno con su panel
// ---------------------------------------------------------------------------

function SummaryRow({
  id,
  label,
  value,
  panel,
}: {
  id: string;
  label: string;
  value: ReactNode;
  panel: ReactNode;
}) {
  return (
    // Los enlaces de antes (#alergenos, #uso, #versiones) llevan el foco a su fila (FocusTarget).
    <div
      id={id}
      tabIndex={-1}
      className="flex min-h-touch items-center gap-2 border-b border-line text-sm text-ink last:border-0 target:outline-2 target:outline-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:min-h-8"
    >
      {/* Una línea: lo que no entra se corta y se ve entero en su panel. */}
      <span className="shrink-0 font-medium">{label}</span>
      <span className="flex min-w-0 flex-1 items-center justify-end gap-2 overflow-hidden text-right whitespace-nowrap">
        {value}
      </span>
      <span className="shrink-0">{panel}</span>
    </div>
  );
}

function Summary({
  anchor,
  recipe,
  version,
  returned,
  allergens,
  usage,
  assignments,
  variants,
  variantPlaces,
  masterDiff,
  diff,
}: {
  anchor: (key: string) => string;
  recipe: RecipeDetail;
  version: RecipeVersion;
  returned: boolean;
  allergens: Awaited<ReturnType<typeof getVersionSummary>>["allergens"];
  usage: Awaited<ReturnType<typeof getRecipeUsage>>;
  assignments: Awaited<ReturnType<typeof getAssignments>>;
  variants: Awaited<ReturnType<typeof getVariants>>;
  variantPlaces: RecipeDetail["can"]["variantPlaces"];
  masterDiff: DiffRow[] | null;
  diff: DiffRow[];
}) {
  const contains = allergens.filter((a) => a.status === "contains");
  const may = allergens.filter((a) => a.status === "may_contain").length;
  const unverified = allergens.filter((a) => a.status === "not_verified").length;
  const viewPanel = (name: string, title: string, children: ReactNode, description?: string) => (
    <ActionModal
      label="Ver"
      accessibleName={`Ver (${name})`}
      variant="link"
      icon="none"
      size="sm"
      className="desk:min-h-8"
      title={title}
      description={description}
    >
      {children}
    </ActionModal>
  );
  const versionsLine = [
    recipe.current ? `v${recipe.current.number} vigente` : null,
    recipe.open
      ? `v${recipe.open.number} ${VERSION_STATUS_LABELS[recipe.open.status].toLowerCase()}`
      : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <section
      aria-label="Resumen de la receta"
      className="flex shrink-0 flex-col rounded-md border border-line bg-surface px-4 py-1 desk:px-3"
    >
      <SummaryRow
        id={anchor("alergenos")}
        label="Alérgenos"
        value={
          // Vacío es «sin datos» (sin ingredientes todavía), nunca «sin alérgenos». Cada estado con su palabra.
          allergens.length === 0 ? (
            <Badge status="none">Sin datos</Badge>
          ) : contains.length > 0 ? (
            // El primero que contiene y cuántos más contiene; la lista entera (con los que puede contener o no están
            // verificados) en «Ver».
            <>
              <Badge status="bad" className="min-w-0 shrink">
                <span className="truncate">Contiene: {contains[0]?.name}</span>
              </Badge>
              {contains.length > 1 ? (
                <span className="shrink-0 text-ink-muted tabular-nums">
                  +{contains.length - 1}
                  <span className="sr-only"> más que contiene</span>
                </span>
              ) : null}
            </>
          ) : may > 0 || unverified > 0 ? (
            <>
              {may > 0 ? (
                <Badge status="warn" className="min-w-0 shrink">
                  <span className="truncate">Puede contener: {may}</span>
                </Badge>
              ) : null}
              {/* Nunca «sin alérgenos» por falta de datos. */}
              {unverified > 0 ? (
                <Badge status="none" className="min-w-0 shrink">
                  <span className="truncate">Sin verificar</span>
                </Badge>
              ) : null}
            </>
          ) : (
            <Badge status="ok">Sin alérgenos</Badge>
          )
        }
        panel={viewPanel(
          "Alérgenos",
          "Alérgenos",
          allergens.length === 0 ? (
            <p className="text-base text-ink-muted">
              Sin datos todavía: los alérgenos salen de los ingredientes de la receta.
            </p>
          ) : (
            <ul className="flex flex-wrap gap-2" aria-label="Alérgenos">
              {allergens.map((a) => (
                <li key={a.name}>
                  <Badge status={ALLERGEN_BADGE[a.status] ?? "neutral"}>
                    {a.name}: {ALLERGEN_LABELS[a.status] ?? a.status}
                  </Badge>
                </li>
              ))}
            </ul>
          ),
          "Salen solos de las materias primas y preparaciones de la lista. Si alguna no tiene el dato, queda «no verificado»: nunca «sin alérgenos» por falta de datos.",
        )}
      />

      <SummaryRow
        id={anchor("uso")}
        label="Dónde se usa"
        value={
          <span className="truncate text-ink-muted tabular-nums">
            {recipe.type !== "dish" || usage.length > 0
              ? `En ${usage.length} ${usage.length === 1 ? "receta" : "recetas"} · `
              : ""}
            {assignments.current.length} {assignments.current.length === 1 ? "local" : "locales"}
          </span>
        }
        panel={viewPanel(
          "Dónde se usa",
          "Dónde se usa",
          <UsagePanel
            anchor={anchor}
            recipe={recipe}
            usage={usage}
            assignments={assignments}
            variants={variants}
            variantPlaces={variantPlaces}
            masterDiff={masterDiff}
          />,
        )}
      />

      <SummaryRow
        id={anchor("versiones")}
        label="Versiones"
        value={<span className="truncate text-ink-muted">{versionsLine || "Sin versiones"}</span>}
        panel={
          <ActionModal
            label="Ver"
            accessibleName="Ver el historial (Versiones y aprobaciones)"
            variant="link"
            icon="none"
            size="sm"
            className="desk:min-h-8"
            title="Versiones y aprobaciones"
          >
            <VersionsPanel
              anchor={anchor}
              recipe={recipe}
              version={version}
              returned={returned}
              diff={diff}
            />
          </ActionModal>
        }
      />
    </section>
  );
}

function UsagePanel({
  anchor,
  recipe,
  usage,
  assignments,
  variants,
  variantPlaces,
  masterDiff,
}: {
  anchor: (key: string) => string;
  recipe: RecipeDetail;
  usage: Awaited<ReturnType<typeof getRecipeUsage>>;
  assignments: Awaited<ReturnType<typeof getAssignments>>;
  variants: Awaited<ReturnType<typeof getVariants>>;
  variantPlaces: RecipeDetail["can"]["variantPlaces"];
  masterDiff: DiffRow[] | null;
}) {
  return (
    <div className="flex flex-col gap-4">
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
                  <Badge status={STATUS_BADGE[u.status]}>{VERSION_STATUS_LABELS[u.status]}</Badge>
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
                Hacemos una copia de la receta vigente para ese local, con el código {recipe.code}
                -V01 (o el siguiente). Después la ajustás y la enviás a revisión.
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

      {masterDiff ? (
        <section className="flex flex-col gap-2" aria-labelledby={anchor("uso-maestra")}>
          <h3 id={anchor("uso-maestra")} className="text-base font-semibold text-ink">
            Diferencias con la maestra
          </h3>
          {recipe.variantOf ? (
            <p className="text-sm text-ink-muted">
              Es una variante de{" "}
              <Link href={`/recetas/${recipe.variantOf.id}`} className={linkClass}>
                {recipe.variantOf.name}
              </Link>
              .
            </p>
          ) : null}
          {masterDiff.length === 0 ? (
            <p className="text-base text-ink-muted">No cambia nada respecto de la maestra.</p>
          ) : (
            <DiffList rows={masterDiff} label="Diferencias con la maestra" />
          )}
        </section>
      ) : null}
    </div>
  );
}

function VersionsPanel({
  anchor,
  recipe,
  version,
  returned,
  diff,
}: {
  anchor: (key: string) => string;
  recipe: RecipeDetail;
  version: RecipeVersion;
  returned: boolean;
  diff: DiffRow[];
}) {
  return (
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
        {version.status === "draft" && recipe.can.review && recipe.isActive ? (
          <div className="desk:hidden">
            <Disclosure summary="Pedir la revisión">
              <p className="text-base text-ink">
                Otra persona con permiso de publicar la revisa. Al aprobarla, queda vigente en las
                cocinas.
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
        {version.status === "in_review" && !returned ? (
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
            <ActionForm action={newVersionAction} schema="reason" submitLabel="Crear versión nueva">
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
  );
}
