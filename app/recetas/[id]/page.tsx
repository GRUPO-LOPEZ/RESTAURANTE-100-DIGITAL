import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense, cache } from "react";
import { ChefHat } from "lucide-react";

import {
  archiveRecipeAction,
  assignAction,
  createVariantAction,
  newVersionAction,
  requestReviewAction,
  saveDraftAction,
  updateRecipeAction,
  withdrawReviewAction,
} from "@/app/recetas/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { RecipeLinesEditor } from "@/components/recipe-lines-editor";
import { RecipePhotoUpload } from "@/components/recipe-photo-upload";
import { RecipePhotos } from "@/components/recipe-photos";
import { RecipeStepsEditor } from "@/components/recipe-steps-editor";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { RELIABILITY, getLiveCost, resolveCostPlace } from "@/lib/costs";
import { formatMoney, perBaseLabel } from "@/lib/money";
import { Metric } from "@/components/ui/metric";
import type { MetricStatus } from "@/lib/metrics";
import { formatLoss } from "@/lib/yields";
import type { Reliability } from "@/lib/cost-labels";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { Notice } from "@/components/ui/notice";
import { codeNoticeFromQuery } from "@/lib/codes";
import { createdRecently } from "@/lib/recipes";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { UUID, first, formatDateTime } from "@/lib/data";
import {
  ALLERGEN_LABELS,
  BASIS_LABELS,
  LINE_UNITS,
  RECIPE_TYPE_LABELS,
  SCOPE_LABELS,
  STEP_KIND_LABELS,
  VERSION_STATUS_LABELS,
  unitDimension,
  unitGroups,
  unitOptionLabel,
  formatMinutes,
  formatQuantity,
  getAssignments,
  getRecipe,
  getRecipeCategories,
  getCookingLoss,
  getRecipeUsage,
  getVariantDiff,
  getVariants,
  getVersionContent,
  getVersionDiff,
  getVersionSummary,
  getVersionPhotos,
  type CookingLoss,
  type DiffRow,
  type RecipeDetail,
  type RecipeVersion,
  type VersionStatus,
} from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

// Ficha de una receta (secciones 13 y 14; ficha por pestañas del rediseño, ADR-0036): nunca un formulario
// interminable. Quien la trabaja ve el borrador y lo edita; quien solo la ve va a la vista de cocina.
// La pestaña va en la dirección (?seccion=), así se puede volver o compartir.
export default function RecetaPage({ params, searchParams }: PageProps<"/recetas/[id]">) {
  return (
    <AppShell
      title="Receta"
      heading={
        <Suspense fallback="Receta">
          <RecipeName params={params} />
        </Suspense>
      }
      description="Componentes, procedimiento, rendimiento y versiones."
    >
      <Suspense fallback={<Loading />}>
        <Recipe params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// Una sola lectura por pedido: la usan el título y la ficha.
const recipeById = cache(getRecipe);

// El h1 de la ficha es el nombre de la receta (rediseño, ADR-0036); la ruta de arriba dice "Receta".
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

function Row({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col sm:flex-row sm:gap-2">
      <dt className="text-sm font-medium text-ink sm:w-40 sm:shrink-0">{label}</dt>
      <dd className="text-sm break-words text-ink-muted">{value || "—"}</dd>
    </div>
  );
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

// Una línea de diferencias, en palabras ("Se agrega…", "de 120 a 160 g").
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

// El rendimiento final destacado (pedido de Soy, ADR-0040). Sin dato, «—» y el motivo (Metric).
function YieldKpis({
  quantity,
  unit,
  unitLabel,
  perBaseUnit,
  reliability,
  place,
  canSeeCosts,
  cookingLoss,
}: {
  quantity: number | null;
  unit: string | null;
  unitLabel: string;
  perBaseUnit: number | null;
  reliability: Reliability | null;
  place: string | null;
  canSeeCosts: boolean;
  cookingLoss: CookingLoss | null;
}) {
  const dimension = unitDimension(unit ?? "");
  const base = dimension === "mass" ? "g" : dimension === "volume" ? "ml" : "unit";
  const per = perBaseLabel(base);
  // El estado del costo es el de la receta (métricas confiables): desactualizado, con estimaciones o completo.
  const costState = reliability ? RELIABILITY[reliability] : null;
  return (
    <div className="grid gap-4 sm:grid-cols-2 desk:grid-cols-3">
      <Metric
        label="Rendimiento final"
        value={quantity ? formatQuantity(quantity) : null}
        unit={quantity ? unitLabel : undefined}
        missingReason="Falta cargarlo: sin rendimiento no se pide la revisión."
        status="ok"
        statusLabel="Cargado"
        emptyLabel="Sin datos"
      />
      {canSeeCosts ? (
        <Metric
          label={dimension ? `Costo ${per.label}` : "Costo"}
          value={perBaseUnit !== null ? formatMoney(perBaseUnit * per.factor) : null}
          missingReason={
            place ? "Falta un dato para calcularlo." : "Elegí un local arriba para ver el costo."
          }
          period={place ?? undefined}
          stale={reliability === "stale"}
          // RELIABILITY usa solo ok, info, warn y bad: todos son estados de una métrica.
          status={(costState?.status ?? "none") as MetricStatus}
          statusLabel={costState?.label ?? "Sin datos"}
          emptyLabel="Sin datos"
        />
      ) : null}
      <Metric
        label="Merma de cocción"
        value={
          cookingLoss?.factor == null
            ? null
            : cookingLoss.factor > 1
              ? `Se expande ×${cookingLoss.factor.toLocaleString("es-AR", { maximumFractionDigits: 2 })}`
              : formatLoss(cookingLoss.factor)
        }
        missingReason={cookingLoss?.missing ?? "Falta un dato."}
        status="info"
        statusLabel="Calculada"
        emptyLabel="Sin datos"
      />
    </div>
  );
}

// Las pestañas de la ficha, en el orden del prompt de rediseño.
const SECTIONS = [
  { key: "datos", label: "Datos generales" },
  { key: "ingredientes", label: "Ingredientes y subrecetas" },
  { key: "rendimientos", label: "Rendimientos" },
  { key: "procedimiento", label: "Procedimiento" },
  { key: "costos", label: "Costos" },
  { key: "alergenos", label: "Alérgenos" },
  { key: "fotos", label: "Fotos" },
  { key: "versiones", label: "Versiones y aprobaciones" },
  { key: "uso", label: "Dónde se usa" },
] as const;
type Section = (typeof SECTIONS)[number]["key"];

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

  const version = recipe.open ?? recipe.current;
  const editable = version?.status === "draft" && recipe.can.draft && recipe.isActive;
  const returned =
    version?.status === "in_review" &&
    (version.requestStatus === "rejected" || version.requestStatus === "cancelled");
  // Las diferencias con la maestra solo si la sesión la ve (la base también lo controla).
  const showMasterDiff = Boolean(recipe.variantOf?.name);
  const [content, summary, diff, assignments, categories, photos, usage, variants, masterDiff] =
    await Promise.all([
      version ? getVersionContent(version.id) : Promise.resolve({ lines: [], steps: [] }),
      version
        ? getVersionSummary(version.id)
        : Promise.resolve({ totalMinutes: 0, activeMinutes: 0, allergens: [] }),
      // Solo hay diferencias si existe una versión anterior (en la v1 todo sería "se agrega").
      recipe.open && recipe.open.number > 1 ? getVersionDiff(recipe.open.id) : Promise.resolve([]),
      getAssignments(recipe),
      recipe.can.draft ? getRecipeCategories() : Promise.resolve([]),
      version ? getVersionPhotos(version.id) : Promise.resolve({ photos: [], failed: false }),
      getRecipeUsage(recipe.id),
      recipe.scope !== "restaurant" ? getVariants(recipe.id) : Promise.resolve([]),
      showMasterDiff ? getVariantDiff(recipe.id) : Promise.resolve([]),
    ]);
  // Un local con una variante activa no ofrece crear otra (la base tampoco la deja).
  const variantPlaces = recipe.can.variantPlaces.filter(
    (p) => !variants.some((v) => v.restaurantId === p.restaurantId),
  );
  // El costo en el local, también de un borrador. El detalle está en /costos, que ve también quien no la trabaja.
  const query0 = await searchParams;
  const menus = await getMenus();
  const costPlace = menus.costs ? (await resolveCostPlace(session.user_id)).place : null;
  const cost = version && costPlace ? await getLiveCost(version.id, costPlace.id) : null;
  // La merma de cocción, solo en la pestaña de rendimientos (ADR-0040).
  const cookingLoss =
    version && first(query0.seccion) === "rendimientos" ? await getCookingLoss(version.id) : null;
  const unitLabel = (code: string | null) =>
    LINE_UNITS.find((u) => u.code === code)?.label ?? code ?? "";
  // Costos solo para quien los ve.
  const tabs = SECTIONS.filter((t) => t.key !== "costos" || menus.costs);
  const query = query0;
  const wanted = first(query.seccion);
  // "← Volver" a la lista con sus filtros y su página: solo la lista de recetas de esta aplicación.
  const volver = first(query.volver);
  const back = volver && /^\/recetas(\?|$)/.test(volver) ? volver : "/recetas";
  const section: Section = tabs.find((t) => t.key === wanted)?.key ?? "datos";
  const show = (key: Section) => section === key;
  // Las pestañas conservan el "volver" a la lista.
  const tabHref = (key: Section) => {
    const q = new URLSearchParams();
    if (key !== "datos") q.set("seccion", key);
    if (back !== "/recetas") q.set("volver", back);
    return q.size ? `/recetas/${recipe.id}?${q}` : `/recetas/${recipe.id}`;
  };
  const noVersion = (
    <EmptyState title="Esta receta todavía no tiene una versión.">
      Se crea con «Crear una versión nueva», en «Versiones y aprobaciones».
    </EmptyState>
  );

  // Recién creada con otro código que el de la vista previa (alguien creó otra en el medio, ADR-0041).
  const codeNotice =
    first(query.aviso) === "codigo" && (await createdRecently("recipe", recipe.id))
      ? codeNoticeFromQuery(first(query.aviso), first(query.previsto), recipe.code)
      : null;

  return (
    <>
      <BackLink href={back}>Volver a recetas</BackLink>
      {codeNotice ? <Notice status="info">{codeNotice}</Notice> : null}

      {/* Encabezado: siempre a la vista, en todas las pestañas. */}
      <Card className="flex flex-col gap-3">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex min-w-0 flex-col">
            {/* El nombre ya es el título de la pantalla: acá van sus datos. */}
            <span className="text-base text-ink tabular-nums">
              {recipe.code} · {RECIPE_TYPE_LABELS[recipe.type]} · {recipe.place}
            </span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {recipe.current ? (
              <Button asChild variant="outline">
                <Link href={`/recetas/${recipe.id}/cocina`}>
                  <ChefHat aria-hidden="true" />
                  Ver la ficha de cocina
                </Link>
              </Button>
            ) : null}
          </div>
        </div>
        <span className="flex flex-wrap gap-1">
          {!recipe.isActive ? <Badge status="none">Archivada</Badge> : null}
          {recipe.variantOf ? <Badge status="info">Variante</Badge> : null}
          {recipe.current ? <Badge status="ok">Vigente v{recipe.current.number}</Badge> : null}
          {recipe.open ? (
            <Badge status={STATUS_BADGE[recipe.open.status]}>
              {VERSION_STATUS_LABELS[recipe.open.status]} v{recipe.open.number}
            </Badge>
          ) : null}
        </span>
        {returned && version ? (
          <Notice status="warn" role="status">
            La revisión {version.requestStatus === "rejected" ? "fue rechazada" : "se retiró"}:
            corregí la versión y pedí la revisión de nuevo.
          </Notice>
        ) : version?.status === "in_review" ? (
          <Notice status="info">
            Está en revisión: la tiene que aprobar otra persona con permiso de publicar, en
            Aprobaciones. Mientras tanto no se edita.
          </Notice>
        ) : null}
        {recipe.open && recipe.current ? (
          <CardDescription>
            La versión vigente (v{recipe.current.number}) sigue en las cocinas hasta que se publique
            esta.
          </CardDescription>
        ) : null}
      </Card>

      <Tabs
        label="Secciones de la receta"
        items={tabs.map((t) => ({ href: tabHref(t.key), label: t.label, current: show(t.key) }))}
      />

      {show("datos") ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Datos generales</CardTitle>
          <dl className="flex flex-col gap-2">
            <Row label="Tipo" value={RECIPE_TYPE_LABELS[recipe.type]} />
            <Row label="Alcance" value={`${SCOPE_LABELS[recipe.scope]} · ${recipe.place}`} />
            {recipe.variantOf ? (
              <div className="flex flex-col sm:flex-row sm:items-center sm:gap-2">
                <dt className="text-sm font-medium text-ink sm:w-40 sm:shrink-0">Variante de</dt>
                <dd className="text-sm break-words text-ink-muted">
                  {recipe.variantOf.name ? (
                    <Link
                      href={`/recetas/${recipe.variantOf.id}`}
                      className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline"
                    >
                      {recipe.variantOf.name}
                    </Link>
                  ) : (
                    "una receta maestra"
                  )}
                </dd>
              </div>
            ) : null}
            <Row label="Nombre corto" value={recipe.shortName} />
            <Row label="Sector" value={recipe.sector} />
            <Row label="Partida" value={recipe.station} />
          </dl>
          {recipe.can.draft && recipe.isActive ? (
            <Disclosure summary="Editar los datos">
              <ActionForm
                action={updateRecipeAction}
                schema="recipeEdit"
                submitLabel="Guardar datos"
                warnUnsaved
              >
                <Ids recipe={recipe} />
                <FormInput
                  id={`rec-${recipe.id}-nombre`}
                  label="Nombre"
                  name="name"
                  required
                  maxLength={120}
                  defaultValue={recipe.name}
                />
                <div className="grid gap-4 sm:grid-cols-2">
                  <FormInput
                    id={`rec-${recipe.id}-nombre-corto`}
                    label="Nombre corto"
                    hint="Para la cocina y las comandas."
                    name="short_name"
                    maxLength={40}
                    defaultValue={recipe.shortName ?? ""}
                  />
                  <FormSelect
                    id={`rec-${recipe.id}-categoria`}
                    label="Categoría"
                    name="category_id"
                    defaultValue={recipe.categoryId ?? ""}
                  >
                    <option value="">Sin categoría</option>
                    {/* Un plato va en un rubro de menú; lo demás, en uno de sub-recetas (ADR-0038). */}
                    {categories
                      .filter(
                        (c) =>
                          c.id === recipe.categoryId ||
                          (c.isActive &&
                            c.kind === (recipe.type === "dish" ? "menu" : "subrecipe")),
                      )
                      .map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.label}
                        </option>
                      ))}
                  </FormSelect>
                  <FormInput
                    id={`rec-${recipe.id}-sector`}
                    label="Sector"
                    name="sector"
                    maxLength={60}
                    defaultValue={recipe.sector ?? ""}
                  />
                  <FormInput
                    id={`rec-${recipe.id}-partida`}
                    label="Partida"
                    name="station"
                    maxLength={60}
                    defaultValue={recipe.station ?? ""}
                  />
                </div>
                <Reason id={`rec-${recipe.id}-motivo-datos`} />
              </ActionForm>
            </Disclosure>
          ) : null}
        </Card>
      ) : null}

      {/* La versión que se trabaja */}
      {!version &&
      ["ingredientes", "rendimientos", "procedimiento", "costos", "alergenos"].includes(section)
        ? noVersion
        : null}
      {version ? (
        <>
          {show("rendimientos") ? (
            <>
              <Card className="flex flex-col gap-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <CardTitle>
                    {version.status === "published" ? "Versión vigente" : "Versión en preparación"}{" "}
                    (v
                    {version.number})
                  </CardTitle>
                  <Badge status={STATUS_BADGE[version.status]}>
                    {VERSION_STATUS_LABELS[version.status]}
                  </Badge>
                </div>
                {/* Lo que importa para usarla dentro de otra receta (ADR-0040): cuánto rinde terminada, cuánto
                    cuesta el kg (o el litro, o la unidad) y cuánto pierde al cocinarse. */}
                <YieldKpis
                  quantity={version.yieldQuantity}
                  unit={version.yieldUnit}
                  unitLabel={unitLabel(version.yieldUnit)}
                  perBaseUnit={cost?.perBaseUnit ?? null}
                  reliability={cost?.reliability ?? null}
                  place={costPlace?.name ?? null}
                  canSeeCosts={menus.costs}
                  cookingLoss={cookingLoss}
                />
                <dl className="flex flex-col gap-2">
                  <Row
                    label="Tiene"
                    value={`${content.lines.length} ${content.lines.length === 1 ? "componente" : "componentes"} · ${content.steps.length} ${content.steps.length === 1 ? "paso" : "pasos"}`}
                  />
                  <Row
                    label="Porciones"
                    value={version.portions ? String(version.portions) : null}
                  />
                  <Row
                    label="Peso por porción"
                    value={
                      version.portionGrams ? `${formatQuantity(version.portionGrams)} g` : null
                    }
                  />
                  <Row label="Tiempo total" value={formatMinutes(summary.totalMinutes)} />
                  <Row label="Tiempo trabajando" value={formatMinutes(summary.activeMinutes)} />
                </dl>
                {editable ? (
                  <Disclosure summary="Rendimiento, descripción y presentación">
                    <ActionForm
                      action={saveDraftAction}
                      schema="recipeDraft"
                      submitLabel="Guardar"
                      warnUnsaved
                    >
                      <Ids recipe={recipe} version={version} />
                      <div className="grid gap-4 sm:grid-cols-2">
                        <FormInput
                          id={`rec-${recipe.id}-rinde`}
                          label="Rinde"
                          name="yield_quantity"
                          required
                          inputMode="decimal"
                          defaultValue={
                            version.yieldQuantity
                              ? String(version.yieldQuantity).replace(".", ",")
                              : ""
                          }
                        />
                        <FormSelect
                          id={`rec-${recipe.id}-rinde-unidad`}
                          label="Unidad"
                          name="yield_unit"
                          required
                          defaultValue={version.yieldUnit ?? ""}
                        >
                          <option value="" disabled>
                            Elegí la unidad
                          </option>
                          {unitGroups().map((g) => (
                            <optgroup key={g.dimension} label={g.label}>
                              {g.units.map((u) => (
                                <option key={u.code} value={u.code}>
                                  {unitOptionLabel(u.code)}
                                </option>
                              ))}
                            </optgroup>
                          ))}
                        </FormSelect>
                        <FormInput
                          id={`rec-${recipe.id}-porciones`}
                          label="Porciones"
                          name="portions"
                          inputMode="numeric"
                          defaultValue={version.portions ? String(version.portions) : ""}
                        />
                        <FormInput
                          id={`rec-${recipe.id}-peso-porcion`}
                          label="Peso por porción (g)"
                          name="portion_grams"
                          inputMode="decimal"
                          defaultValue={
                            version.portionGrams
                              ? String(version.portionGrams).replace(".", ",")
                              : ""
                          }
                        />
                      </div>
                      <FormTextarea
                        id={`rec-${recipe.id}-descripcion`}
                        label="Descripción"
                        name="description"
                        maxLength={2000}
                        defaultValue={version.description ?? ""}
                      />
                      <FormTextarea
                        id={`rec-${recipe.id}-conservacion`}
                        label="Conservación"
                        hint="Solo desde un procedimiento validado, con su referencia. El sistema nunca la propone."
                        name="storage_notes"
                        maxLength={2000}
                        defaultValue={version.storageNotes ?? ""}
                      />
                      <FormTextarea
                        id={`rec-${recipe.id}-presentacion`}
                        label="Presentación"
                        name="presentation_notes"
                        maxLength={2000}
                        defaultValue={version.presentationNotes ?? ""}
                      />
                      <FormTextarea
                        id={`rec-${recipe.id}-cambio`}
                        label="Qué cambió en esta versión"
                        name="change_summary"
                        maxLength={1000}
                        defaultValue={version.changeSummary ?? ""}
                      />
                      <Reason id={`rec-${recipe.id}-motivo-borrador`} />
                    </ActionForm>
                  </Disclosure>
                ) : (
                  <dl className="flex flex-col gap-2">
                    <Row label="Descripción" value={version.description} />
                    <Row label="Conservación" value={version.storageNotes} />
                    <Row label="Presentación" value={version.presentationNotes} />
                    <Row label="Qué cambió" value={version.changeSummary} />
                  </dl>
                )}
              </Card>

              {recipe.current ? (
                <Link
                  href={`/recetas/${recipe.id}/escalar`}
                  className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
                >
                  Escalar
                </Link>
              ) : null}
            </>
          ) : null}
          {show("costos") && !(cost && costPlace) ? (
            <EmptyState
              title={
                costPlace
                  ? `Esta receta no tiene costo en ${costPlace.name}.`
                  : "Elegí un local en la barra de arriba para ver el costo."
              }
            >
              {costPlace
                ? "El local no la usa, o la acaban de asignar: los costos se actualizan en un minuto."
                : null}
            </EmptyState>
          ) : null}
          {show("costos") && cost && costPlace ? (
            <Card className="flex flex-col gap-2">
              <div className="flex flex-wrap items-center gap-2">
                <CardTitle>Costo en {costPlace.name}</CardTitle>
                <Badge status={RELIABILITY[cost.reliability].status}>
                  {RELIABILITY[cost.reliability].label}
                </Badge>
              </div>
              <p className="text-base text-ink tabular-nums">
                {cost.total === null && cost.gross === null
                  ? "Sin costo todavía"
                  : `${formatMoney(cost.total)} sin IVA · ${formatMoney(cost.gross)} con IVA`}
                {cost.perPortion !== null ? ` · ${formatMoney(cost.perPortion)} por porción` : ""}
              </p>
              {version?.status !== "published" ? (
                <CardDescription>
                  Con los precios de hoy, si esta versión se publicara.
                </CardDescription>
              ) : null}
              <Link
                href={`/costos/${recipe.id}?local=${costPlace.id}`}
                className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
              >
                Ver el costo línea por línea
              </Link>
            </Card>
          ) : null}
          {show("ingredientes") ? (
            <Card className="flex flex-col gap-4">
              <CardTitle>Componentes</CardTitle>
              {editable ? (
                <RecipeLinesEditor
                  recipeId={recipe.id}
                  versionId={version.id}
                  expectedUpdatedAt={version.updatedAt}
                  initial={content.lines}
                />
              ) : content.lines.length === 0 ? (
                <p className="text-base text-ink-muted">Sin componentes.</p>
              ) : (
                <ol className="flex flex-col gap-2" aria-label="Componentes">
                  {content.lines.map((l, i) => (
                    <li
                      key={`${l.ingredientId}-${i}`}
                      className="flex flex-wrap justify-between gap-2 border-b border-line pb-2 last:border-0"
                    >
                      {l.subRecipeId ? (
                        <span className="flex flex-wrap items-center gap-2">
                          <Link
                            href={`/recetas/${l.subRecipeId}`}
                            className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline"
                          >
                            {l.ingredient}
                          </Link>
                          <Badge status="info">Preparación</Badge>
                        </span>
                      ) : (
                        <span className="text-ink">{l.ingredient}</span>
                      )}
                      <span className="text-ink-muted tabular-nums">
                        {formatQuantity(l.quantity)} {unitLabel(l.unit)} ·{" "}
                        {BASIS_LABELS[l.basis].toLowerCase()}
                      </span>
                    </li>
                  ))}
                </ol>
              )}
            </Card>
          ) : null}

          {show("procedimiento") ? (
            <Card className="flex flex-col gap-4">
              <CardTitle>Procedimiento</CardTitle>
              <CardDescription>
                El tiempo total cuenta los pasos que se esperan entre sí; los que van en paralelo no
                se suman.
              </CardDescription>
              {editable ? (
                <RecipeStepsEditor
                  yieldLabel={LINE_UNITS.find((u) => u.code === version?.yieldUnit)?.label}
                  recipeId={recipe.id}
                  versionId={version.id}
                  expectedUpdatedAt={version.updatedAt}
                  initial={content.steps}
                />
              ) : content.steps.length === 0 ? (
                <p className="text-base text-ink-muted">Sin pasos.</p>
              ) : (
                <ol className="flex flex-col gap-3" aria-label="Pasos">
                  {content.steps.map((s) => (
                    <li
                      key={s.number}
                      className="flex flex-col gap-1 border-b border-line pb-3 last:border-0"
                    >
                      <span className="font-medium text-ink">
                        {s.number}. {STEP_KIND_LABELS[s.kind]} ·{" "}
                        {formatMinutes(s.activeMinutes + s.passiveMinutes)}
                      </span>
                      <span className="text-ink">{s.instructions}</span>
                      {s.dependsOn.length > 0 ? (
                        <span className="text-sm text-ink-muted">
                          Empieza cuando terminan los pasos {s.dependsOn.join(", ")}.
                        </span>
                      ) : null}
                    </li>
                  ))}
                </ol>
              )}
            </Card>
          ) : null}

          {show("alergenos") ? (
            <Card className="flex flex-col gap-4">
              <CardTitle>Alérgenos</CardTitle>
              <CardDescription>
                Salen de las materias primas. Si alguna no tiene el dato, el alérgeno queda «no
                verificado»: nunca «sin alérgenos» por falta de datos.
              </CardDescription>
              {summary.allergens.length === 0 ? (
                <p className="text-base text-ink-muted">
                  No hay alérgenos cargados en el catálogo.
                </p>
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
          ) : null}

          {show("ingredientes") && recipe.open && diff.length > 0 ? (
            <Card className="flex flex-col gap-4">
              <CardTitle>Cambios contra la versión anterior</CardTitle>
              <DiffList rows={diff} label="Cambios" />
            </Card>
          ) : null}
        </>
      ) : null}

      {show("fotos") ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Fotos</CardTitle>
          <CardDescription>
            Producto final, emplatado y puntos críticos. Las fotos van con la versión: la cocina ve
            las de la vigente, y las del borrador cuando se publique.
          </CardDescription>
          {editable ? (
            <Disclosure summary="Subir una foto">
              <RecipePhotoUpload recipeId={recipe.id} />
            </Disclosure>
          ) : recipe.can.draft && recipe.isActive && !recipe.open ? (
            <p className="text-base text-ink-muted">
              Para agregar o quitar fotos, creá una versión nueva (en «Versiones y aprobaciones»).
            </p>
          ) : null}
          <RecipePhotos recipeId={recipe.id} set={photos} canRemove={editable} />
        </Card>
      ) : null}

      {/* Lo que se puede hacer con la receta */}
      {show("versiones") ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Versiones y aprobaciones</CardTitle>
          <div className="flex flex-col gap-2">
            {version?.status === "draft" && recipe.can.review && recipe.isActive ? (
              <Disclosure summary="Pedir la revisión">
                <p className="text-base text-ink">
                  Otra persona con permiso de publicar la revisa en Aprobaciones. Al aprobarla,
                  queda vigente en las cocinas. Se manda lo que está guardado: si hay cambios sin
                  guardar en los componentes o los pasos, guardalos antes.
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
            ) : null}
            {version?.status === "in_review" && !returned ? (
              <Disclosure summary="Retirar de revisión">
                <p className="text-base text-ink">
                  Solo la retira quien pidió la revisión. Vuelve a borrador.
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
                  Copia la vigente en un borrador. La vigente sigue en las cocinas hasta que se
                  publique la nueva.
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
          <ul className="flex flex-col gap-2" aria-label="Versiones">
            {recipe.versions.map((v) => (
              <li
                key={v.id}
                className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-0"
              >
                <span className="text-ink">
                  Versión {v.number}
                  {v.publishedAt ? ` · publicada ${formatDateTime(v.publishedAt)}` : ""}
                </span>
                <Badge status={STATUS_BADGE[v.status]}>{VERSION_STATUS_LABELS[v.status]}</Badge>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      {show("ingredientes") && showMasterDiff ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Diferencias con la maestra</CardTitle>
          <CardDescription>
            Qué cambia este local respecto de «{recipe.variantOf?.name}» (su versión vigente).
          </CardDescription>
          {masterDiff.length === 0 ? (
            <p className="text-base text-ink-muted">No cambia nada respecto de la maestra.</p>
          ) : (
            <DiffList rows={masterDiff} label="Diferencias con la maestra" />
          )}
        </Card>
      ) : null}

      {show("uso") && (usage.length > 0 || recipe.type === "preparation") ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Recetas que la usan como preparación</CardTitle>
          <CardDescription>
            Cuando publicás una versión nueva, estas recetas pasan a usarla solas y avisamos a sus
            locales.
          </CardDescription>
          {usage.length === 0 ? (
            <p className="text-base text-ink-muted">Ninguna receta la usa todavía.</p>
          ) : (
            <ul className="flex flex-col gap-2" aria-label="Recetas que la usan">
              {usage.map((u) => (
                <li
                  key={u.id}
                  className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-0"
                >
                  <Link
                    href={`/recetas/${u.id}`}
                    className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline"
                  >
                    {u.name}
                  </Link>
                  <Badge status={STATUS_BADGE[u.status]}>{VERSION_STATUS_LABELS[u.status]}</Badge>
                </li>
              ))}
            </ul>
          )}
        </Card>
      ) : null}

      {show("uso") && (variants.length > 0 || variantPlaces.length > 0) ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Variantes de local</CardTitle>
          <CardDescription>
            Un local puede tener su versión de esta receta. Cuando se publica, ese local deja de
            usar la maestra.
          </CardDescription>
          {variants.length === 0 ? (
            <p className="text-base text-ink-muted">No tiene variantes.</p>
          ) : (
            <ul className="flex flex-col gap-2" aria-label="Variantes">
              {variants.map((v) => (
                <li
                  key={v.id}
                  className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-0"
                >
                  <Link
                    href={`/recetas/${v.id}`}
                    className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline"
                  >
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
                -V01 (o el siguiente). Después la ajustás y pedís la revisión.
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
        </Card>
      ) : null}

      {show("uso") ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Locales que la usan</CardTitle>
          {assignments.current.length === 0 ? (
            <p className="text-base text-ink-muted">Todavía no se usa en ningún local.</p>
          ) : (
            <ul className="flex flex-col gap-2" aria-label="Locales que la usan">
              {assignments.current.map((a) => (
                <li
                  key={a.restaurantId}
                  className="flex flex-col gap-2 border-b border-line pb-2 last:border-0"
                >
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
        </Card>
      ) : null}
    </>
  );
}
