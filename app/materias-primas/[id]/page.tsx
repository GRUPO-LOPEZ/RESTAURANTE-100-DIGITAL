import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense, cache } from "react";

import {
  createProductAction,
  createSupplierAction,
  proposeWasteAction,
  proposeYieldAction,
  recordYieldTestAction,
  setActiveAction,
  updateProductAction,
} from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal, ProposalModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { FocusTarget } from "@/components/focus-target";
import { Disclosure } from "@/components/disclosure";
import { IngredientPrices } from "@/components/ingredient-prices";
import {
  AllergenSummary,
  AllergensSection,
  ConversionsSection,
  DataSection,
  IngredientSheetProvider,
  SheetBar,
  ThawingToggle,
} from "@/components/ingredient-sheet/sheet-editor";
import { Badge } from "@/components/ui/badge";
import { FormCheckbox, FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { InfoTip } from "@/components/ui/info-tip";
import { ToggleField } from "@/components/ui/toggle-field";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { ShortList } from "@/components/ui/short-list";
import { Tile } from "@/components/ui/tile";
import { WastePreview } from "@/components/waste-preview";
import { getMenus, requireMenu } from "@/lib/auth/session";
import {
  ALLERGEN_STATUS_LABELS,
  SOURCE_LABELS,
  getCategories,
  getIngredient,
  getIngredientSheetState,
  getIngredientUsage,
  getSuppliers,
  getThawingChangePending,
  getUnits,
  getWasteProcesses,
  getYieldAlertThreshold,
  getYieldProcesses,
  getYieldRestaurants,
  getYieldSummary,
  type IngredientDetail,
  type IngredientUsage,
  type Unit,
  type YieldRow,
} from "@/lib/catalog";
import { codeNoticeFromQuery } from "@/lib/codes";
import { lineStatusLabel } from "@/lib/cost-labels";
import { getIngredientNetCost, resolveCostPlace, type IngredientNetCost } from "@/lib/costs";
import { UUID, first, formatDate } from "@/lib/data";
import { priceState, type IngredientSheetDraft } from "@/lib/ingredient-sheet";
import { missingState } from "@/lib/metrics";
import { formatMoney } from "@/lib/money";
import { getLocalCost, getProductPrices, type LocalCost, type ProductPrice } from "@/lib/prices";
import { bigUnitPrice } from "@/lib/recipe-sheet";
import { createdRecently } from "@/lib/recipes";
import {
  cleaningDifference,
  describeCooking,
  exceedsYieldAlert,
  formatCleaning,
  formatLoss,
  netYield,
} from "@/lib/yields";

// Ficha de una materia prima en una pantalla (ADR-0046, pedido de Soy del 2026-11-13; ficha única, ADR-0043): una línea
// de encabezado, 4 indicadores y tres columnas de tarjetas que se editan donde se ven. Lo que se edita se guarda junto
// con la barra de abajo (ADR-0039); las altas y las propuestas con aprobación (producto, proveedor, precio, merma,
// rendimiento, ensayo) van en un panel corto. Las listas se cortan con «Ver los N»: la pantalla no crece con los datos.
// Las reglas no cambian: las decide la base. En el celular, la ficha es de consulta (con scroll).
export default function MateriaPrimaPage({
  params,
  searchParams,
}: PageProps<"/materias-primas/[id]">) {
  return (
    <AppShell
      title="Materia prima"
      fill
      heading={
        <Suspense fallback="Materia prima">
          <IngredientName params={params} />
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
          <ActiveAction params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Ingredient params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// Una sola lectura por pedido: la usan el título y la ficha.
const ingredientById = cache(getIngredient);

async function IngredientName({
  params,
}: {
  params: PageProps<"/materias-primas/[id]">["params"];
}) {
  await requireMenu("catalog");
  const { id } = await params;
  if (!UUID.test(id)) return "Materia prima";
  return (await ingredientById(id))?.name ?? "Materia prima";
}

const SECTIONS = [
  { key: "datos", label: "Datos generales" },
  { key: "compra", label: "Precios de compra" },
  { key: "rendimientos", label: "Mermas y rendimientos" },
  { key: "conversiones", label: "Conversiones" },
  { key: "alergenos", label: "Alérgenos" },
  { key: "uso", label: "Dónde se usa" },
] as const;

// Los avisos después de guardar (la ficha vuelve con lo guardado y el aviso va arriba).
const NOTICES: Record<string, { status: "ok" | "info"; text: string }> = {
  guardado: { status: "ok", text: "Cambios guardados." },
  producto: { status: "ok", text: "Producto de compra guardado." },
  congelada: {
    status: "ok",
    text: "Guardado: se compra congelada. Los costos se actualizan en un minuto.",
  },
  "congelada-pendiente": {
    status: "info",
    text: "Cambios guardados. Queda pendiente: dejar de comprarla congelada lo tiene que aprobar un Chef de todo el grupo.",
  },
};

const linkClass =
  "inline-flex min-h-touch items-center text-base text-primary underline-offset-4 hover:underline";

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

// Las unidades del catálogo, agrupadas por tipo y como «Kilogramo (kg)» (ADR-0040).
const UNIT_GROUPS: [string, string][] = [
  ["mass", "Peso"],
  ["volume", "Volumen"],
  ["count", "Unidades"],
  ["package", "Envases"],
];
function UnitOptions({ units }: { units: Unit[] }) {
  return (
    <>
      {UNIT_GROUPS.map(([dimension, label]) => {
        const list = units.filter((u) => u.dimension === dimension);
        return list.length === 0 ? null : (
          <optgroup key={dimension} label={label}>
            {list.map((u) => (
              <option key={u.code} value={u.code}>
                {u.label}
              </option>
            ))}
          </optgroup>
        );
      })}
    </>
  );
}

function today() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Buenos_Aires" }).format(
    new Date(),
  );
}

// A dónde vuelve «← Materias primas»: el listado con sus filtros, si vino de ahí.
function backHref(volver: string | undefined): string {
  return volver && /^\/materias-primas(\?|$)/.test(volver) ? volver : "/materias-primas";
}

async function Back({
  searchParams,
}: {
  searchParams: PageProps<"/materias-primas/[id]">["searchParams"];
}) {
  const query = await searchParams;
  return (
    <BackLink href={backHref(first(query.volver))} label="Volver a materias primas">
      Materias primas
    </BackLink>
  );
}

// La línea del nombre: código · rubro · en qué se usa, y el estado con palabra.
async function Meta({ params }: { params: PageProps<"/materias-primas/[id]">["params"] }) {
  await requireMenu("catalog");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  const ingredient = await ingredientById(id);
  if (!ingredient) return null;
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">
        <span>{ingredient.code}</span>
        {` · ${ingredient.category || "Sin rubro"} · se usa en ${ingredient.unit}`}
      </span>
      {ingredient.isActive ? (
        <Badge status="ok">Activa</Badge>
      ) : (
        <Badge status="none">Desactivada</Badge>
      )}
      {ingredient.requiresThawing ? <Badge status="info">Se compra congelada</Badge> : null}
    </>
  );
}

// Desactivar (o volver a activar): un botón a la derecha del nombre, con su motivo en un panel corto. En el celular la
// ficha es de consulta (ADR-0043): se hace en la computadora.
async function ActiveAction({ params }: { params: PageProps<"/materias-primas/[id]">["params"] }) {
  await requireMenu("catalog");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  const [ingredient, menus] = await Promise.all([ingredientById(id), getMenus()]);
  if (!ingredient || !menus.catalogManage) return null;
  const label = ingredient.isActive ? "Desactivar" : "Volver a activar";
  return (
    <div className="hidden desk:block">
      <ActionModal
        label={label}
        icon="none"
        title={label}
        description={
          ingredient.isActive
            ? "No se borra nada: deja de ofrecerse para recetas nuevas y su historia queda."
            : "Vuelve a ofrecerse para recetas nuevas."
        }
      >
        <ActionForm
          action={setActiveAction}
          schema="reason"
          submitLabel={ingredient.isActive ? "Desactivar" : "Activar"}
          variant={ingredient.isActive ? "destructive" : "default"}
        >
          <input type="hidden" name="ingredientId" value={ingredient.id} />
          <input type="hidden" name="active" value={ingredient.isActive ? "false" : "true"} />
          <Reason id="mp-motivo-activa" />
        </ActionForm>
      </ActionModal>
    </div>
  );
}

async function Ingredient({
  params,
  searchParams,
}: {
  params: PageProps<"/materias-primas/[id]">["params"];
  searchParams: PageProps<"/materias-primas/[id]">["searchParams"];
}) {
  const session = await requireMenu("catalog");
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const [ingredient, menus, query] = await Promise.all([
    ingredientById(id),
    getMenus(),
    searchParams,
  ]);
  if (!ingredient) notFound();
  const canManage = menus.catalogManage;
  const canRecordYields = menus.yieldsRecord;
  // Cada tarjeta lleva el comienzo del id: Next guarda oculta la ficha anterior, y con dos «#uso» un enlace podría
  // llevar a la oculta (lo mismo que en la ficha de receta).
  const anchor = (key: string) => `${key}-${ingredient.id.slice(0, 8)}`;
  // Los enlaces de antes (?seccion=compra) llevan a su tarjeta: el foco va ahí y se marca (FocusTarget).
  const old = first(query.seccion);
  const back = backHref(first(query.volver));
  if (old && SECTIONS.some((s) => s.key === old)) {
    const q = back !== "/materias-primas" ? `?${new URLSearchParams({ volver: back })}` : "";
    redirect(`/materias-primas/${ingredient.id}${q}#${anchor(old)}`);
  }

  // Recién creada con otro código que el de la vista previa (alguien creó otra en el medio, ADR-0041).
  const codeNotice =
    first(query.aviso) === "codigo" && (await createdRecently("ingredient", ingredient.id))
      ? codeNoticeFromQuery(first(query.aviso), first(query.previsto), ingredient.code)
      : null;
  const saved = NOTICES[first(query.aviso) ?? ""];

  const none = Promise.resolve([]);
  const [categories, units, suppliers, sheetState] = await Promise.all([
    getCategories(),
    getUnits(),
    canManage || menus.pricesPropose ? getSuppliers() : none,
    canManage ? getIngredientSheetState(ingredient.id) : Promise.resolve(null),
  ]);
  const [yieldRows, processes, yieldRestaurants, yieldAlert, usage, wasteProcesses] =
    await Promise.all([
      getYieldSummary(ingredient.id),
      canRecordYields ? getYieldProcesses() : none,
      canRecordYields ? getYieldRestaurants() : none,
      getYieldAlertThreshold(ingredient.id),
      getIngredientUsage(ingredient.id),
      getWasteProcesses(ingredient.groupId),
    ]);
  const thawingPending = ingredient.requiresThawing
    ? await getThawingChangePending(ingredient.id)
    : false;
  // El precio y el costo, en el local elegido arriba.
  const place =
    menus.costs || menus.pricesView ? (await resolveCostPlace(session.user_id)).place : null;
  const [netCost, localCost, productPrices] = await Promise.all([
    place && menus.costs
      ? getIngredientNetCost(ingredient.id, place.id, ingredient.unitCode, wasteProcesses.cleaning)
      : Promise.resolve(null),
    place && menus.pricesView ? getLocalCost(ingredient.id, place.id) : Promise.resolve(null),
    place && menus.pricesView ? getProductPrices(ingredient.id, place.id) : Promise.resolve([]),
  ]);

  // Solo se edita con catalog.manage y con el sello de la base (si no hay sello, la base no la deja editar).
  const editable = canManage && sheetState !== null;
  const initial: IngredientSheetDraft = {
    data: {
      name: ingredient.name,
      category_id: ingredient.categoryId,
      recipe_unit: ingredient.unitCode,
      purchase_unit: ingredient.purchaseUnitCode ?? "",
      notes: ingredient.notes ?? "",
    },
    aliases: ingredient.aliases,
    requiresThawing: ingredient.requiresThawing,
    conversions: {
      density: null,
      unit_weight: null,
      ...Object.fromEntries(
        ingredient.conversions.map((c) => [
          c.kind,
          {
            factor: String(c.factor).replace(".", ","),
            source: c.source,
            measured_on: c.measuredOn,
            measured_by: c.measuredBy ?? "",
          },
        ]),
      ),
    },
    allergens: Object.fromEntries(
      ingredient.allergens
        .filter((a) => a.status !== null)
        .map((a) => [a.id, { status: a.status ?? "", source: a.source ?? "" }]),
    ),
  };
  const options = {
    // Los rubros dados de baja no se ofrecen, salvo el que ya tiene (ADR-0038).
    categories: categories
      .filter((c) => c.isActive || c.id === ingredient.categoryId)
      .map((c) => ({ id: c.id, label: c.label })),
    units: units.map((u) => ({
      code: u.code,
      label: u.label,
      dimension: u.dimension,
      isBase: u.isBase,
    })),
    allergens: ingredient.allergens.map((a) => ({
      id: a.id,
      name: a.name,
      validated: a.validated,
    })),
    sources: Object.entries(SOURCE_LABELS).map(([value, label]) => ({ value, label })),
    statuses: Object.entries(ALLERGEN_STATUS_LABELS).map(([value, label]) => ({ value, label })),
  };

  // Mermas generales (limpieza y descongelado) y el rendimiento neto (ADR-0040): sin dato, «—» y el motivo.
  const general = (processId: string | null) =>
    yieldRows.find((r) => r.processId === processId && r.cut === null && r.supplier === null);
  const cleaning = general(wasteProcesses.cleaning);
  const thawing = general(wasteProcesses.thawing);
  const net = netYield({
    cleaning: cleaning?.standardCleaning ?? null,
    thawing: thawing?.standardCleaning ?? null,
    requiresThawing: ingredient.requiresThawing,
  });
  const missingPlace = "Elegí un local arriba para ver el precio.";
  const current = localCost ? bigUnitPrice(localCost.unit_cost, localCost.base_unit) : null;
  const activeProducts = ingredient.products.filter((p) => p.isActive).length;
  const published = usage.filter((u) => u.status === "published").length;
  const allergenCount = {
    done: ingredient.allergens.filter((a) => a.status !== null).length,
    total: ingredient.allergens.length,
  };
  const allergenState = missingState(allergenCount.total - allergenCount.done, allergenCount.total);

  return (
    <>
      <FocusTarget />
      {codeNotice ? <Notice status="info">{codeNotice}</Notice> : null}
      {/* El aviso de guardado: en la computadora, quien edita lo ve en la barra de abajo (pantalla sin scroll, ADR-0046);
          en el celular, y quien no edita, acá arriba. */}
      {saved ? (
        <Notice status={saved.status} className={editable ? "desk:hidden" : undefined}>
          {saved.text}
        </Notice>
      ) : null}

      <IngredientSheetProvider
        ingredientId={ingredient.id}
        stamp={sheetState?.stamp ?? null}
        editable={editable}
        hasPrices={sheetState?.hasPrices ?? false}
        initial={initial}
        options={options}
        notice={saved ?? null}
      >
        {/* 4 indicadores: no se repiten abajo. El precio, con prices.view; el costo neto, con costos (el Chef ve costos sin
            ver precios). En el celular, uno debajo del otro: los montos no entran de a dos. */}
        <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
          {menus.pricesView ? (
            <Metric
              compact
              label="Precio vigente"
              value={current ? formatMoney(current.value) : null}
              unit={current ? `/ ${current.unit}` : undefined}
              missingReason={
                !place
                  ? missingPlace
                  : localCost
                    ? (lineStatusLabel(localCost.status) ?? "Sin precio aprobado.")
                    : "Sin precio aprobado."
              }
              period={place?.name ?? undefined}
              stale={localCost?.stale ?? false}
              asOf={localCost?.valid_from ? formatDate(localCost.valid_from) : null}
              status={localCost?.inherited ? "info" : "ok"}
              statusLabel={localCost?.inherited ? "Precio heredado" : "Al día"}
              emptyLabel="Sin datos"
            />
          ) : (
            <Metric
              compact
              label="Productos de compra"
              value={activeProducts}
              comparison={activeProducts === 1 ? "activo" : "activos"}
              status={activeProducts > 0 ? "ok" : "none"}
              statusLabel={activeProducts > 0 ? "Cargados" : "Sin productos"}
              emptyLabel="Sin datos"
            />
          )}
          {menus.costs ? (
            <Metric
              compact
              label={netCost ? `Costo neto ${netCost.per}` : "Costo neto"}
              value={netCost?.net != null ? formatMoney(netCost.net) : null}
              missingReason={
                !place
                  ? missingPlace
                  : !netCost
                    ? "No ves los costos de este local."
                    : (lineStatusLabel(netCost.netStatus) ?? "Falta un dato.")
              }
              period={place?.name ?? undefined}
              comparison="con merma y descongelado"
              stale={netCost?.stale ?? false}
              asOf={netCost?.validFrom ? formatDate(netCost.validFrom) : null}
              status={netCost?.inherited ? "info" : "ok"}
              statusLabel={netCost?.inherited ? "Precio heredado" : "Al día"}
              emptyLabel="Sin datos"
            />
          ) : (
            // Sin costos: los alérgenos con dato (la merma ya está en su tarjeta; no se repite). La regla única de lo
            // que falta (lib/metrics.ts).
            <Metric
              compact
              label="Alérgenos con dato"
              value={allergenCount.done}
              total={allergenCount.total}
              comparison={`de ${allergenCount.total}`}
              emptyLabel="No hay alérgenos para cargar."
              status={allergenState.status}
              statusLabel={allergenState.label}
            />
          )}
          <Metric
            compact
            label="Rinde neto"
            value={net.value !== null ? formatCleaning(net.value) : null}
            missingReason={net.missing ?? undefined}
            comparison={
              ingredient.requiresThawing && thawing?.standardCleaning != null
                ? `descongelado ${formatLoss(thawing.standardCleaning)}`
                : undefined
            }
            status="ok"
            statusLabel="Calculado"
            emptyLabel="Sin datos"
          />
          {/* «Dónde se usa» (ADR-0046, decisión de Joaco): el número va en el indicador y la lista, en «Ver cuáles». Los
              enlaces de antes (#uso) llevan el foco acá. */}
          <div
            id={anchor("uso")}
            tabIndex={-1}
            className="scroll-mt-24 rounded-md target:outline-2 target:outline-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <Metric
              compact
              className="h-full"
              action={
                usage.length > 0 ? (
                  <ActionModal
                    label="Ver cuáles"
                    accessibleName="Ver cuáles (Recetas que la usan)"
                    variant="link"
                    icon="none"
                    size="sm"
                    title="Dónde se usa"
                    description="Las recetas vigentes o en preparación que la tienen, entre las que ves."
                  >
                    <Usage rows={usage} canOpen={menus.recipes} />
                  </ActionModal>
                ) : null
              }
              label="Recetas que la usan"
              value={usage.length}
              comparison={
                usage.length === 0
                  ? "No está en ninguna receta"
                  : `${published} ${published === 1 ? "vigente" : "vigentes"}`
              }
              status={usage.length > 0 ? "info" : "none"}
              statusLabel={usage.length > 0 ? "En uso" : "Sin uso"}
              emptyLabel="Sin datos"
            />
          </div>
        </div>

        {/* Tres columnas en proporción 4 : 5 : 4 (el boceto) que ocupan el alto que queda. En el celular, una debajo de la otra. */}
        <div className="grid gap-4 desk:flex-1 desk:grid-cols-[4fr_5fr_4fr]">
          <Tile id={anchor("datos")} title="Datos generales">
            <DataSection
              middle={<ThawingToggle pending={thawingPending} />}
              readExtra={
                thawingPending ? (
                  <Badge status="review" className="self-start whitespace-normal">
                    Pedido pendiente: dejar de comprarla congelada
                  </Badge>
                ) : null
              }
            />
          </Tile>

          <div className="flex min-w-0 flex-col gap-4">
            <Tile
              id={anchor("compra")}
              title={menus.pricesView ? "Precios de compra" : "Cómo se compra"}
              aside={menus.pricesView ? (place?.name ?? undefined) : undefined}
              className="desk:flex-1"
            >
              <PurchaseCard
                ingredient={ingredient}
                prices={menus.pricesView}
                place={place?.name ?? null}
                localCost={localCost}
                productPrices={productPrices}
                canManage={canManage}
                canPropose={menus.pricesPropose}
                canSeeImpact={menus.costs}
                pricedProducts={sheetState?.pricedProducts ?? null}
                volver={back}
                units={units}
                suppliers={suppliers}
              />
            </Tile>
            <Tile
              id={anchor("rendimientos")}
              title="Mermas y rendimientos"
              titleExtra={
                <InfoTip label="mermas y rendimiento neto">
                  Lo que se pierde al limpiar y al descongelar. El costo usa siempre lo aprobado por
                  un Chef de todo el grupo.
                </InfoTip>
              }
              className="desk:flex-1"
            >
              <WasteCard
                ingredient={ingredient}
                rows={yieldRows}
                cleaning={cleaning ?? null}
                thawing={thawing ?? null}
                alertPct={yieldAlert}
                canRecord={canRecordYields}
                processes={processes}
                restaurants={yieldRestaurants}
                canManageProcesses={menus.yieldsApprove}
                wasteProcesses={wasteProcesses}
                netCost={netCost}
              />
            </Tile>
          </div>

          <div className="flex min-w-0 flex-col gap-4">
            <Tile
              id={anchor("conversiones")}
              title="Conversiones"
              titleExtra={
                <InfoTip label="conversiones">
                  Solo hacen falta si se compra en una unidad y se usa en otra (por ejemplo, aceite
                  por kg usado en ml). Nunca se supone que 1 litro pesa 1 kilo.
                </InfoTip>
              }
            >
              <ConversionsSection />
            </Tile>
            <Tile
              id={anchor("alergenos")}
              title="Alérgenos"
              titleExtra={
                <InfoTip label="alérgenos">
                  Cada clic cambia el estado: Sin dato, No contiene, Puede contener, Contiene. «Sin
                  dato» no quiere decir que no tenga: un plato con un ingrediente sin dato se
                  muestra como no verificado.
                </InfoTip>
              }
              aside={<AllergenSummary />}
              className="desk:flex-1"
            >
              <AllergensSection />
            </Tile>
          </div>
        </div>

        <SheetBar />
      </IngredientSheetProvider>
    </>
  );
}

// Dónde se usa (sección 18): las recetas vigentes o en preparación que la tienen, entre las que se ven.
function Usage({ rows, canOpen }: { rows: IngredientUsage[]; canOpen: boolean }) {
  if (rows.length === 0)
    return <p className="text-base text-ink-muted">Todavía no está en ninguna receta.</p>;
  return (
    <ul className="flex flex-col gap-2" aria-label="Todas las recetas que la usan">
      {rows.map((r) => (
        <li key={r.recipeId} className="flex flex-wrap items-center justify-between gap-2">
          {canOpen ? (
            <Link href={`/recetas/${r.recipeId}`} className={linkClass}>
              {r.name}
            </Link>
          ) : (
            <span className="text-base text-ink">{r.name}</span>
          )}
          <span className="text-sm text-ink-muted tabular-nums">
            {r.code} · v{r.versionNumber} {r.status === "published" ? "vigente" : "en preparación"}
          </span>
        </li>
      ))}
    </ul>
  );
}

// ---------------------------------------------------------------------------
// Precios de compra: el precio vigente y el costo neto destacados, y la tabla de productos
// ---------------------------------------------------------------------------
// Editar un producto de compra (ADR-0044). El código y la materia prima no cambian. Con precios, el envase y el
// contenido se ven deshabilitados y el tooltip dice por qué: la base los rechaza igual (guard_priced_product).
function ProductEdit({
  ingredientId,
  product: p,
  priced,
  volver,
  units,
  suppliers,
}: {
  ingredientId: string;
  product: IngredientDetail["products"][number];
  priced: boolean;
  volver: string;
  units: Unit[];
  suppliers: Awaited<ReturnType<typeof getSuppliers>>;
}) {
  const key = p.id.slice(0, 8);
  const original = {
    description: p.description,
    brand_name: p.brandName ?? "",
    supplier_id: p.supplierId ?? "",
    notes: p.notes ?? "",
    is_active: String(p.isActive),
    package_unit: p.packageUnitCode,
    units_per_package: String(p.unitsPerPackage),
    content_per_unit: String(p.contentPerUnit).replace(".", ","),
    content_unit: p.contentUnitCode,
  };
  return (
    <ActionModal
      label="Editar"
      accessibleName={`Editar «${p.description}»`}
      icon="pencil"
      title="Editar producto de compra"
      description={`${p.code}. El código y la materia prima no cambian.`}
    >
      <ActionForm action={updateProductAction} schema="productEdit" submitLabel="Guardar producto">
        <input type="hidden" name="ingredientId" value={ingredientId} />
        <input type="hidden" name="productId" value={p.id} />
        <input type="hidden" name="volver" value={volver} />
        <input type="hidden" name="original" value={JSON.stringify(original)} />
        <FormInput
          id={`pe-${key}-description`}
          label="Descripción"
          hint="Como lo vende el proveedor."
          name="description"
          required
          maxLength={200}
          defaultValue={original.description}
        />
        <div className="grid gap-4 sm:grid-cols-2">
          <FormSelect
            id={`pe-${key}-supplier_id`}
            label="Proveedor habitual"
            name="supplier_id"
            defaultValue={original.supplier_id}
          >
            <option value="">Sin proveedor fijo</option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </FormSelect>
          <FormInput
            id={`pe-${key}-brand_name`}
            label="Marca"
            name="brand_name"
            maxLength={80}
            defaultValue={original.brand_name}
          />
        </div>
        <fieldset
          className="flex flex-col gap-4"
          aria-describedby={priced ? `pe-${key}-envase-fijo` : undefined}
        >
          <legend className="mb-2 text-sm font-medium text-ink">Envase y contenido</legend>
          {/* Con precios, se dice a la vista (los campos deshabilitados salen del orden del teclado); el detalle, en
              el tooltip. */}
          {priced ? (
            <p
              id={`pe-${key}-envase-fijo`}
              className="-mt-2 flex items-center gap-1 text-sm text-ink-muted"
            >
              No se cambia: ya tiene precios.
              <InfoTip label="por qué no se cambia el envase">
                Ya tiene precios: el precio se guardó por envase. Si cambió el envase o el
                contenido, agregá otro producto de compra y marcá este como que ya no se compra.
              </InfoTip>
            </p>
          ) : null}
          <FormSelect
            id={`pe-${key}-package_unit`}
            label="Viene en"
            name="package_unit"
            disabled={priced}
            defaultValue={original.package_unit}
          >
            <UnitOptions units={units} />
          </FormSelect>
          <div className="grid gap-4 sm:grid-cols-2">
            <FormInput
              id={`pe-${key}-units_per_package`}
              label="Unidades por envase"
              name="units_per_package"
              inputMode="numeric"
              disabled={priced}
              defaultValue={original.units_per_package}
            />
            <FormInput
              id={`pe-${key}-content_per_unit`}
              label="Contenido de cada unidad"
              name="content_per_unit"
              inputMode="decimal"
              disabled={priced}
              defaultValue={original.content_per_unit}
            />
          </div>
          <FormSelect
            id={`pe-${key}-content_unit`}
            label="Unidad del contenido"
            name="content_unit"
            disabled={priced}
            defaultValue={original.content_unit}
          >
            <UnitOptions units={units.filter((u) => u.dimension !== "package")} />
          </FormSelect>
        </fieldset>
        <FormTextarea
          id={`pe-${key}-notes`}
          label="Observaciones"
          name="notes"
          maxLength={1000}
          defaultValue={original.notes}
        />
        <ToggleField
          id={`pe-${key}-activo`}
          name="is_active"
          label="¿Se sigue comprando?"
          defaultValue={p.isActive}
        />
        <Reason id={`pe-${key}-motivo`} />
      </ActionForm>
    </ActionModal>
  );
}

// ---------------------------------------------------------------------------
// Precios de compra (ADR-0046): una sola tarjeta para los productos y sus precios. Hasta 3 productos a la vista; el
// detalle (tabla completa con «Editar», los que ya no se compran, el costo en el local y el historial de precios) va en
// «Ver los N productos». Quien no ve precios ve «Cómo se compra», sin precios.
// ---------------------------------------------------------------------------
function PurchaseCard({
  ingredient,
  prices,
  place,
  localCost,
  productPrices,
  canManage,
  canPropose,
  canSeeImpact,
  pricedProducts,
  volver,
  units,
  suppliers,
}: {
  ingredient: IngredientDetail;
  prices: boolean;
  place: string | null;
  localCost: LocalCost | null;
  productPrices: ProductPrice[];
  canManage: boolean;
  canPropose: boolean;
  canSeeImpact: boolean;
  // Productos con precios: su envase y su contenido no cambian (ADR-0044). null: no lo puede editar.
  pricedProducts: string[] | null;
  volver: string;
  units: Unit[];
  suppliers: Awaited<ReturnType<typeof getSuppliers>>;
}) {
  const priceOf = new Map(productPrices.map((p) => [p.productId, p]));
  // Los activos, y los que ya no se compran pero tienen el precio que vale (el último costo conocido).
  const products = ingredient.products.filter(
    (p) => p.isActive || priceOf.get(p.id)?.priceRecordId != null,
  );
  const noPrice =
    prices &&
    place !== null &&
    (!localCost || localCost.status === "missing_price" || localCost.unit_cost === null);
  const detailCount =
    products.length +
    (canManage && pricedProducts !== null ? ingredient.products.length - products.length : 0);
  return (
    <>
      {prices && place === null ? (
        <p className="text-sm text-ink-muted">Elegí un local arriba para ver el precio.</p>
      ) : null}
      {noPrice ? (
        <p className="rounded-sm bg-warn px-3 py-1 text-sm text-warn-ink">
          {products.length === 0
            ? "Todavía no tiene productos de compra ni un precio que valga en este local."
            : "Todavía no tiene un precio que valga en este local."}
        </p>
      ) : null}
      <ShortList
        label="Productos de compra"
        items={products}
        limit={3}
        itemKey={(p) => p.id}
        empty={
          noPrice ? null : (
            <p className="text-sm text-ink-muted">Todavía no tiene productos de compra.</p>
          )
        }
        renderItem={(p) => {
          const price = priceOf.get(p.id);
          const big = price ? bigUnitPrice(price.unitCost, price.baseUnit) : null;
          const state = price
            ? priceState(price)
            : { status: "none" as const, label: place ? "Sin precio" : "Elegí un local" };
          return (
            <div className="flex min-h-touch items-center justify-between gap-2 text-sm desk:min-h-7">
              <span className="min-w-0 truncate text-ink">
                {[p.description, p.supplier].filter(Boolean).join(" · ")}
              </span>
              {prices ? (
                <span className="flex shrink-0 items-center gap-2">
                  <span className="text-ink tabular-nums">
                    {big ? `${formatMoney(big.value)} / ${big.unit}` : "—"}
                  </span>
                  <Badge status={state.status}>{state.label}</Badge>
                </span>
              ) : p.isActive ? null : (
                <Badge status="none">Ya no se compra</Badge>
              )}
            </div>
          );
        }}
      />
      {detailCount > 0 ? (
        <ActionModal
          label={detailCount === 1 ? "Ver el producto" : `Ver los ${detailCount} productos`}
          variant="link"
          icon="none"
          size="sm"
          title={prices ? "Precios de compra" : "Cómo se compra"}
          description="Cada producto dice qué trae el envase. Varios productos pueden ser de la misma materia prima."
        >
          <ProductsDetail
            ingredient={ingredient}
            prices={prices}
            place={place}
            productPrices={productPrices}
            canManage={canManage}
            pricedProducts={pricedProducts}
            volver={volver}
            units={units}
            suppliers={suppliers}
          />
          {prices ? (
            <IngredientPrices
              part="detail"
              ingredient={ingredient}
              canPropose={canPropose}
              canSeeImpact={canSeeImpact}
              suppliers={suppliers}
            />
          ) : null}
        </ActionModal>
      ) : null}
      {canManage || (prices && canPropose) ? (
        <div className="mt-auto flex flex-wrap gap-2">
          {/* Las altas, en la computadora; «Proponer precio» también en el celular (ADR-0044). */}
          {canManage ? (
            <div className="hidden desk:contents">
              <CreateProduct ingredient={ingredient} units={units} suppliers={suppliers} />
              <CreateSupplier ingredient={ingredient} />
            </div>
          ) : null}
          {prices && canPropose ? (
            <ActionModal
              label="Proponer precio"
              icon="none"
              size="sm"
              title="Proponer precio"
              description="Lo aprueba el Controller; si cambia mucho, también Dirección General."
            >
              <IngredientPrices
                part="propose"
                ingredient={ingredient}
                canPropose={canPropose}
                canSeeImpact={canSeeImpact}
                suppliers={suppliers}
              />
            </ActionModal>
          ) : null}
        </div>
      ) : null}
    </>
  );
}

// ---------------------------------------------------------------------------
// Mermas y rendimientos (ADR-0040 y ADR-0046): la merma de limpieza y la de descongelado con su estado, un resumen de
// los rendimientos por proceso con «Ver todos» (la tabla completa en un panel) y las propuestas. Sin dato, «—» y el
// motivo: nunca 0 % ni 100 %.
// ---------------------------------------------------------------------------
function WasteRow({
  label,
  value,
  status,
  statusLabel,
  reason,
}: {
  label: string;
  value: string;
  status: "ok" | "none" | "review";
  statusLabel: string;
  // Sin dato, por qué falta (nunca 0 %).
  reason?: string;
}) {
  return (
    <li className="flex min-h-touch flex-col justify-center border-b border-line py-1 text-sm desk:min-h-7">
      <span className="flex items-center justify-between gap-2">
        <span className="text-ink">{label}</span>
        <span className="flex items-center gap-2">
          <span className="text-ink tabular-nums">{value}</span>
          <Badge status={status}>{statusLabel}</Badge>
        </span>
      </span>
      {reason ? <span className="text-xs text-ink-muted">{reason}</span> : null}
    </li>
  );
}

function WasteCard({
  ingredient,
  rows,
  cleaning,
  thawing,
  alertPct,
  canRecord,
  processes,
  restaurants,
  canManageProcesses,
  wasteProcesses,
  netCost,
}: {
  ingredient: IngredientDetail;
  rows: YieldRow[];
  cleaning: YieldRow | null;
  thawing: YieldRow | null;
  alertPct: number | null;
  canRecord: boolean;
  processes: { id: string; name: string }[];
  restaurants: { id: string; name: string }[];
  canManageProcesses: boolean;
  wasteProcesses: { cleaning: string | null; thawing: string | null };
  netCost: IngredientNetCost | null;
}) {
  const thaws = ingredient.requiresThawing;
  const waste = (row: YieldRow | null, reason: string) =>
    row?.standardCleaning != null
      ? { value: formatLoss(row.standardCleaning), status: "ok" as const, statusLabel: "Aprobada" }
      : row?.pendingProposals
        ? { value: "—", status: "review" as const, statusLabel: "En revisión", reason }
        : { value: "—", status: "none" as const, statusLabel: "Sin datos", reason };
  // Los rendimientos por proceso, en una línea: cuántos tienen estándar, cuántos están en revisión y cuántos se desvían.
  const withStandard = rows.filter((r) => standardText(r) !== null).length;
  const inReview = rows.filter((r) => r.pendingProposals > 0).length;
  const off = rows.filter((r) => deviates(r, alertPct)).length;
  const summary =
    rows.length === 0
      ? "Todavía no tiene rendimientos por proceso."
      : [
          `${rows.length} ${rows.length === 1 ? "rendimiento" : "rendimientos"} por proceso`,
          `${withStandard} con estándar`,
          inReview > 0 ? `${inReview} en revisión` : null,
          off > 0 ? `${off} se ${off === 1 ? "desvía" : "desvían"}` : null,
        ]
          .filter(Boolean)
          .join(" · ");
  return (
    <>
      <ul className="flex flex-col" aria-label="Mermas">
        <WasteRow
          label="Merma de limpieza"
          {...waste(cleaning, "Sin merma de limpieza aprobada.")}
        />
        {thaws ? (
          <WasteRow
            label="Merma de descongelado"
            {...waste(thawing, "Se compra congelada y falta su merma aprobada.")}
          />
        ) : (
          <WasteRow
            label="Merma de descongelado"
            value="—"
            status="none"
            statusLabel="No aplica"
            reason="No se compra congelada."
          />
        )}
      </ul>
      <p className="flex flex-wrap items-center gap-x-2 text-xs text-ink-muted">
        {summary}
        {rows.length > 0 ? (
          <ActionModal
            label="Ver todos"
            accessibleName="Ver todos los rendimientos por proceso"
            variant="link"
            icon="none"
            size="sm"
            title="Rendimientos por proceso"
            description="El estándar que usa el costo, lo que dicen los ensayos y la diferencia."
          >
            <YieldsTable ingredient={ingredient} rows={rows} alertPct={alertPct} />
          </ActionModal>
        ) : null}
      </p>
      <YieldActions
        ingredient={ingredient}
        rows={rows}
        canRecord={canRecord}
        processes={processes}
        restaurants={restaurants}
        canManageProcesses={canManageProcesses}
        wasteProcesses={wasteProcesses}
        netCost={netCost}
      />
    </>
  );
}

function ProductsDetail({
  ingredient,
  prices,
  place,
  productPrices,
  canManage,
  pricedProducts,
  volver,
  units,
  suppliers,
}: {
  ingredient: IngredientDetail;
  prices: boolean;
  place: string | null;
  productPrices: ProductPrice[];
  canManage: boolean;
  // Productos con precios: su envase y su contenido no cambian (ADR-0044). null: no lo puede editar.
  pricedProducts: string[] | null;
  volver: string;
  units: Unit[];
  suppliers: Awaited<ReturnType<typeof getSuppliers>>;
}) {
  const priceOf = new Map(productPrices.map((p) => [p.productId, p]));
  // Los activos, y los que ya no se compran pero tienen el precio que vale (el último costo conocido).
  const products = ingredient.products.filter(
    (p) => p.isActive || priceOf.get(p.id)?.priceRecordId != null,
  );
  // Quien edita también ve los que ya no se compran y no tienen precio, para corregirlos o volver a activarlos.
  const priced = canManage ? pricedProducts : null;
  const retired = priced ? ingredient.products.filter((p) => !products.includes(p)) : [];
  const edit = (p: IngredientDetail["products"][number]) =>
    priced ? (
      <ProductEdit
        ingredientId={ingredient.id}
        product={p}
        priced={priced.includes(p.id)}
        volver={volver}
        units={units}
        suppliers={suppliers}
      />
    ) : null;
  return (
    <>
      {products.length === 0 ? (
        <p className="text-base text-ink-muted">Todavía no tiene productos de compra.</p>
      ) : (
        <>
          {/* Computadora: tabla de ancho completo. Celular: tarjetas (ADR-0036). */}
          <div
            className="hidden overflow-x-auto desk:block"
            tabIndex={0}
            role="region"
            aria-label="Tabla de productos de compra"
          >
            <table className="w-full border-collapse text-base">
              <caption className="sr-only">Productos de compra</caption>
              <thead>
                <tr className="border-b border-line text-left text-sm text-ink-muted">
                  <th scope="col" className="py-2 pr-3 font-medium">
                    Producto de compra
                  </th>
                  <th scope="col" className="py-2 pr-3 font-medium">
                    Proveedor
                  </th>
                  <th scope="col" className="py-2 pr-3 font-medium">
                    Viene en
                  </th>
                  <th scope="col" className="py-2 pr-3 text-right font-medium">
                    Contenido
                  </th>
                  {prices ? (
                    <>
                      <th scope="col" className="py-2 pr-3 text-right font-medium">
                        Precio
                      </th>
                      <th scope="col" className="py-2 pr-3 text-right font-medium">
                        Precio por kg, l o u
                      </th>
                      <th scope="col" className="py-2 pr-3 font-medium">
                        Fecha
                      </th>
                      <th scope="col" className="py-2 font-medium">
                        Estado
                      </th>
                    </>
                  ) : null}
                  {priced ? (
                    <th scope="col" className="py-2 pl-3 font-medium">
                      <span className="sr-only">Acciones</span>
                    </th>
                  ) : null}
                </tr>
              </thead>
              <tbody>
                {products.map((p) => {
                  const price = priceOf.get(p.id);
                  const big = price ? bigUnitPrice(price.unitCost, price.baseUnit) : null;
                  const state = price
                    ? priceState(price)
                    : { status: "none" as const, label: place ? "Sin precio" : "Elegí un local" };
                  return (
                    <tr key={p.id} className="border-b border-line">
                      <th scope="row" className="py-2 pr-3 text-left font-medium text-ink">
                        {p.description}
                        {p.isActive ? null : (
                          <Badge status="none" className="ml-2">
                            Ya no se compra
                          </Badge>
                        )}
                        <span className="block text-sm font-normal text-ink-muted tabular-nums">
                          {[p.code, p.brandName].filter(Boolean).join(" · ")}
                        </span>
                      </th>
                      <td className="py-2 pr-3 text-ink">{p.supplier ?? "—"}</td>
                      <td className="py-2 pr-3 text-ink">{p.packageUnit}</td>
                      <td className="py-2 pr-3 text-right text-ink tabular-nums">{p.content}</td>
                      {prices ? (
                        <>
                          <td className="py-2 pr-3 text-right text-ink tabular-nums">
                            {price?.packageCost != null ? formatMoney(price.packageCost) : "—"}
                          </td>
                          <td className="py-2 pr-3 text-right text-ink tabular-nums">
                            {big ? `${formatMoney(big.value)} / ${big.unit}` : "—"}
                          </td>
                          <td className="py-2 pr-3 text-ink tabular-nums">
                            {price?.validFrom ? formatDate(price.validFrom) : "—"}
                          </td>
                          <td className="py-2">
                            <Badge status={state.status}>{state.label}</Badge>
                          </td>
                        </>
                      ) : null}
                      {priced ? <td className="py-2 pl-3 text-right">{edit(p)}</td> : null}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <ul className="flex flex-col gap-2 desk:hidden" aria-label="Productos de compra">
            {products.map((p) => {
              const price = priceOf.get(p.id);
              const big = price ? bigUnitPrice(price.unitCost, price.baseUnit) : null;
              const state = price
                ? priceState(price)
                : { status: "none" as const, label: place ? "Sin precio" : "Elegí un local" };
              return (
                <li key={p.id} className="flex flex-col gap-1 rounded-sm border border-line p-3">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <span className="font-medium text-ink">{p.description}</span>
                    {/* El mismo estado que en la tabla: sin precio también se dice. */}
                    {prices ? (
                      <Badge status={state.status}>{state.label}</Badge>
                    ) : p.isActive ? null : (
                      <Badge status="none">Ya no se compra</Badge>
                    )}
                  </div>
                  <span className="text-sm text-ink-muted tabular-nums">
                    {[p.supplier, `${p.packageUnit} de ${p.content}`].filter(Boolean).join(" · ")}
                  </span>
                  {prices && big ? (
                    <span className="text-base text-ink tabular-nums">
                      {formatMoney(big.value)} / {big.unit}
                    </span>
                  ) : null}
                </li>
              );
            })}
          </ul>
        </>
      )}

      {retired.length > 0 ? (
        <div className="hidden desk:block">
          <Disclosure summary={`Ya no se compran (${retired.length})`}>
            <ul className="flex flex-col gap-2" aria-label="Productos que ya no se compran">
              {retired.map((p) => (
                <li
                  key={p.id}
                  className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-b-0 last:pb-0"
                >
                  <span className="text-base font-medium text-ink">
                    {p.description}
                    <span className="block text-sm text-ink-muted tabular-nums">
                      {[p.code, p.supplier, `${p.packageUnit} de ${p.content}`]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  </span>
                  {edit(p)}
                </li>
              ))}
            </ul>
          </Disclosure>
        </div>
      ) : null}
    </>
  );
}

// Las altas de la tarjeta de compras: cada una con su panel, su motivo y su propio guardado (como hoy).
function CreateProduct({
  ingredient,
  units,
  suppliers,
}: {
  ingredient: IngredientDetail;
  units: Unit[];
  suppliers: Awaited<ReturnType<typeof getSuppliers>>;
}) {
  return (
    <ActionModal
      label="Producto"
      size="sm"
      accessibleName="Agregar producto de compra"
      title="Agregar producto de compra"
      description="Qué trae el envase, como lo vende el proveedor."
    >
      <ActionForm action={createProductAction} schema="product" submitLabel="Agregar producto">
        <input type="hidden" name="ingredientId" value={ingredient.id} />
        <FormInput id="mp-code" label="Código" name="code" required maxLength={30} />
        <FormInput
          id="mp-description"
          label="Descripción"
          hint="Como lo vende el proveedor."
          name="description"
          required
          maxLength={200}
        />
        <FormSelect
          id="mp-package_unit"
          label="Viene en"
          name="package_unit"
          required
          defaultValue=""
        >
          <option value="" disabled>
            Elegí cómo viene
          </option>
          <UnitOptions units={units} />
        </FormSelect>
        <div className="grid gap-4 sm:grid-cols-2">
          <FormInput
            id="mp-units_per_package"
            label="Unidades por envase"
            hint="Caja de 12 botellas: 12."
            name="units_per_package"
            inputMode="numeric"
            required
            defaultValue="1"
          />
          <FormInput
            id="mp-content_per_unit"
            label="Contenido de cada unidad"
            hint="Botella de 750 ml: 750."
            name="content_per_unit"
            inputMode="decimal"
            required
          />
        </div>
        <FormSelect
          id="mp-content_unit"
          label="Unidad del contenido"
          name="content_unit"
          required
          defaultValue=""
        >
          <option value="" disabled>
            Elegí la unidad
          </option>
          <UnitOptions units={units.filter((u) => u.dimension !== "package")} />
        </FormSelect>
        <FormSelect
          id="mp-supplier_id"
          label="Proveedor habitual"
          name="supplier_id"
          defaultValue=""
        >
          <option value="">Sin proveedor fijo</option>
          {suppliers.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </FormSelect>
        <FormInput id="mp-brand_name" label="Marca" name="brand_name" maxLength={80} />
        <Reason id="mp-motivo-producto" />
      </ActionForm>
    </ActionModal>
  );
}

function CreateSupplier({ ingredient }: { ingredient: IngredientDetail }) {
  return (
    <ActionModal
      label="Proveedor"
      size="sm"
      accessibleName="Crear un proveedor"
      title="Crear un proveedor"
      description="Queda para todo el grupo. Después lo elegís en el producto."
    >
      <ActionForm action={createSupplierAction} schema="supplier" submitLabel="Crear proveedor">
        <input type="hidden" name="groupId" value={ingredient.groupId} />
        <input type="hidden" name="ingredientId" value={ingredient.id} />
        <FormInput id="mp-supplier_code" label="Código" name="code" required maxLength={30} />
        <FormInput id="mp-supplier_name" label="Nombre" name="name" required maxLength={120} />
        <FormInput
          id="mp-tax_id"
          label="CUIT"
          name="tax_id"
          hint="Con o sin guiones."
          maxLength={15}
        />
        <Reason id="mp-motivo-proveedor" />
      </ActionForm>
    </ActionModal>
  );
}

// ---------------------------------------------------------------------------
// Rendimientos por proceso (etapa 2.1 B): el estándar que usa el costo, lo que dicen los ensayos y la diferencia. Un
// ensayo nunca cambia el estándar: se propone uno nuevo y lo aprueba un Chef de todo el grupo (ADR-0021).
// ---------------------------------------------------------------------------
// Si el promedio de los ensayos se desvía del estándar más que el umbral del aviso de rendimiento (ADR-0035).
function deviates(row: YieldRow, alertPct: number | null): boolean {
  if (alertPct === null) return false;
  const cleaning =
    row.measuredCleaning !== null &&
    row.standardCleaning !== null &&
    exceedsYieldAlert(row.measuredCleaning, row.standardCleaning, alertPct);
  const cooking =
    row.measuredCooking !== null &&
    row.standardCooking !== null &&
    exceedsYieldAlert(row.measuredCooking, row.standardCooking, alertPct);
  return cleaning || cooking;
}

function standardText(row: YieldRow): string | null {
  if (row.standardCleaning === null || row.standardCooking === null) return null;
  return `Limpieza ${formatCleaning(row.standardCleaning)} · ${describeCooking(row.standardCooking)}${row.declaredNoLoss ? " · declarado sin merma" : ""}`;
}

function testsText(row: YieldRow): string {
  if (row.tests === 0) return "Sin ensayos.";
  const parts = [row.tests === 1 ? "1 ensayo" : `${row.tests} ensayos`];
  if (row.measuredCleaning !== null) {
    parts.push(
      `limpieza ${formatCleaning(row.measuredCleaning)}` +
        (row.standardCleaning !== null
          ? ` (${cleaningDifference(row.measuredCleaning, row.standardCleaning)})`
          : ""),
    );
  }
  if (row.measuredCooking !== null) parts.push(describeCooking(row.measuredCooking));
  if (row.lastTestedOn) parts.push(`último el ${formatDate(row.lastTestedOn)}`);
  return parts.join(" · ");
}

function YieldState({ row, alertPct }: { row: YieldRow; alertPct: number | null }) {
  const standard = standardText(row) !== null;
  const off = deviates(row, alertPct);
  return (
    <span className="flex flex-wrap gap-1">
      {standard ? null : <Badge status="warn">Sin estándar aprobado</Badge>}
      {row.pendingProposals > 0 ? <Badge status="review">Propuesta en revisión</Badge> : null}
      {off ? (
        <Badge status="warn" className="whitespace-normal">
          El promedio se desvía más del {alertPct?.toLocaleString("es-AR")} % del estándar
        </Badge>
      ) : null}
      {standard && row.pendingProposals === 0 && !off ? <Badge status="ok">Aprobado</Badge> : null}
    </span>
  );
}

function YieldsTable({
  ingredient,
  rows,
  alertPct,
}: {
  ingredient: IngredientDetail;
  rows: YieldRow[];
  alertPct: number | null;
}) {
  const label = (r: YieldRow) =>
    [r.process, r.cut, r.supplier ? `de ${r.supplier}` : null].filter(Boolean).join(" · ");
  const key = (r: YieldRow) => `${r.processId}-${r.cut ?? ""}-${r.supplier ?? ""}`;
  return (
    <section
      className="flex flex-col gap-3"
      aria-labelledby={`rend-proceso-${ingredient.id.slice(0, 8)}`}
    >
      <h3
        id={`rend-proceso-${ingredient.id.slice(0, 8)}`}
        className="text-base font-semibold text-ink"
      >
        Rendimientos por proceso
      </h3>
      {rows.length === 0 ? (
        <p className="text-base text-ink-muted">Todavía no tiene rendimientos cargados.</p>
      ) : (
        <>
          <div
            className="hidden overflow-x-auto desk:block"
            tabIndex={0}
            role="region"
            aria-label="Tabla de rendimientos por proceso"
          >
            <table className="w-full border-collapse text-base">
              <caption className="sr-only">Rendimientos por proceso</caption>
              <thead>
                <tr className="border-b border-line text-left text-sm text-ink-muted">
                  <th scope="col" className="py-2 pr-3 font-medium">
                    Proceso
                  </th>
                  <th scope="col" className="py-2 pr-3 font-medium">
                    Corte o presentación
                  </th>
                  <th scope="col" className="py-2 pr-3 font-medium">
                    Estándar que usa el costo
                  </th>
                  <th scope="col" className="py-2 pr-3 font-medium">
                    Ensayos en las cocinas
                  </th>
                  <th scope="col" className="py-2 font-medium">
                    Estado
                  </th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={key(r)} className="border-b border-line align-top">
                    <th scope="row" className="py-2 pr-3 text-left font-medium text-ink">
                      {r.process}
                      {r.supplier ? (
                        <span className="block text-sm font-normal text-ink-muted">
                          de {r.supplier}
                        </span>
                      ) : null}
                    </th>
                    <td className="py-2 pr-3 text-ink">{r.cut ?? "—"}</td>
                    <td className="py-2 pr-3 text-ink tabular-nums">{standardText(r) ?? "—"}</td>
                    <td className="py-2 pr-3 text-sm text-ink-muted tabular-nums">
                      {testsText(r)}
                    </td>
                    <td className="py-2">
                      <YieldState row={r} alertPct={alertPct} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <ul className="flex flex-col gap-2 desk:hidden" aria-label="Rendimientos por proceso">
            {rows.map((r) => (
              <li key={key(r)} className="flex flex-col gap-1 rounded-sm border border-line p-3">
                <span className="font-medium text-ink">{label(r)}</span>
                <span className="text-base text-ink tabular-nums">
                  {standardText(r) ?? "Sin estándar aprobado"}
                </span>
                <span className="text-sm text-ink-muted tabular-nums">{testsText(r)}</span>
                <YieldState row={r} alertPct={alertPct} />
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}

// Proponer una merma o un rendimiento y registrar un ensayo: en la tarjeta de mermas, cada uno con su panel.
function YieldActions({
  ingredient,
  rows,
  canRecord,
  processes,
  restaurants,
  canManageProcesses,
  wasteProcesses,
  netCost,
}: {
  ingredient: IngredientDetail;
  rows: YieldRow[];
  canRecord: boolean;
  processes: { id: string; name: string }[];
  restaurants: { id: string; name: string }[];
  canManageProcesses: boolean;
  wasteProcesses: { cleaning: string | null; thawing: string | null };
  netCost: IngredientNetCost | null;
}) {
  if (!canRecord) return null;
  return (
    <div className="mt-auto flex flex-col gap-2">
      {canRecord && processes.length === 0 ? (
        <div className="flex flex-col gap-1">
          <p className="text-base text-ink">
            No hay procesos cargados (pelado, hervido…).
            {canManageProcesses ? "" : " Los crea un Chef de todo el grupo."}
          </p>
          {canManageProcesses ? (
            <Link href="/materias-primas/configuracion" className={`${linkClass} self-start`}>
              Crealos en la configuración del catálogo
            </Link>
          ) : null}
        </div>
      ) : null}
      {canRecord ? (
        <div className="hidden flex-wrap gap-2 desk:flex">
          <ProposalModal
            label="Proponer merma o rendimiento"
            options={[
              {
                value: "merma",
                label: "Merma",
                content: (
                  <WasteForm
                    ingredient={ingredient}
                    rows={rows}
                    processes={wasteProcesses}
                    netCost={netCost}
                  />
                ),
              },
              ...(processes.length > 0
                ? [
                    {
                      value: "rendimiento",
                      label: "Rendimiento por proceso",
                      content: <YieldProposalForm ingredient={ingredient} processes={processes} />,
                    },
                  ]
                : []),
            ]}
          />
          {processes.length > 0 ? (
            <ActionModal
              label="Registrar un ensayo"
              title="Registrar un ensayo"
              description="Lo que se midió en la cocina. No cambia el estándar: si hace falta, proponé uno nuevo."
            >
              <YieldTestForm
                ingredient={ingredient}
                processes={processes}
                restaurants={restaurants}
              />
            </ActionModal>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

// Proponer mermas (ADR-0040): limpieza y descongelado en %, con la vista previa del costo. Lo aprueba un Chef de todo
// el grupo.
function WasteForm({
  ingredient,
  rows,
  processes,
  netCost,
}: {
  ingredient: IngredientDetail;
  rows: YieldRow[];
  processes: { cleaning: string | null; thawing: string | null };
  netCost: IngredientNetCost | null;
}) {
  const general = (processId: string | null) =>
    rows.find((r) => r.processId === processId && r.cut === null && r.supplier === null);
  const thaws = ingredient.requiresThawing;
  // Sin los dos procesos, la propuesta fallaría: se avisa y no se ofrece el formulario.
  const missing = [
    processes.cleaning === null ? "limpieza (LIMPIEZA)" : null,
    processes.thawing === null ? "descongelado (DESCONGELADO)" : null,
  ].filter((p): p is string => p !== null);
  if (missing.length > 0)
    return (
      <Notice status="warn">
        Al grupo le falta el proceso de {missing.join(" y el de ")}. Lo crea un Chef de todo el
        grupo en la configuración del catálogo.
      </Notice>
    );
  return (
    <ActionForm action={proposeWasteAction} schema="waste" submitLabel="Proponer mermas">
      <input type="hidden" name="ingredientId" value={ingredient.id} />
      <FormInput
        id="mp-merma-limpieza"
        label="Merma de limpieza (%)"
        hint="Lo que se descarta al limpiar: 20 si de 1 kg quedan 800 g."
        name="cleaning_loss"
        inputMode="decimal"
      />
      <FormInput
        id="mp-merma-descongelado"
        label="Merma de descongelado (%)"
        hint={
          thaws ? "El agua que pierde al descongelarse." : "Solo cuenta si se compra congelada."
        }
        name="thawing_loss"
        inputMode="decimal"
      />
      <WastePreview
        requiresThawing={thaws}
        approvedCleaning={general(processes.cleaning)?.standardCleaning ?? null}
        approvedThawing={general(processes.thawing)?.standardCleaning ?? null}
        grossCost={netCost?.gross ?? null}
        per={netCost?.per ?? ""}
      />
      <FormCheckbox
        id="mp-merma-sin"
        name="declared_no_loss"
        label="No tiene merma"
        hint="Obligatorio para cargar 0 %: el sistema nunca supone que no hay merma."
      />
      <FormTextarea id="mp-merma-metodo" label="Cómo se midió" name="method" maxLength={500} />
      <Reason id="mp-motivo-merma" />
    </ActionForm>
  );
}

function YieldProposalForm({
  ingredient,
  processes,
}: {
  ingredient: IngredientDetail;
  processes: { id: string; name: string }[];
}) {
  return (
    <ActionForm action={proposeYieldAction} schema="yieldProposal" submitLabel="Proponer estándar">
      <input type="hidden" name="ingredientId" value={ingredient.id} />
      <FormSelect id="mp-est-proceso" label="Proceso" name="process_id" required defaultValue="">
        <option value="" disabled>
          Elegí el proceso
        </option>
        {processes.map((p) => (
          <option key={p.id} value={p.id}>
            {p.name}
          </option>
        ))}
      </FormSelect>
      <FormInput
        id="mp-est-corte"
        label="Corte o presentación"
        hint="Solo si cambia el rendimiento. Por ejemplo, «en cubos»."
        name="cut"
        maxLength={80}
      />
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id="mp-est-limpieza"
          label="Limpieza (%)"
          hint="Peso limpio sobre peso bruto. 100 si no hay limpieza."
          name="cleaning_percent"
          inputMode="decimal"
          required
        />
        <FormInput
          id="mp-est-coccion"
          label="Factor de cocción"
          hint="Peso después sobre peso antes: 0,85 si pierde, 2,5 si se hidrata, 1 si no se cocina."
          name="cooking_factor"
          inputMode="decimal"
          required
          defaultValue="1"
        />
      </div>
      <FormTextarea id="mp-est-metodo" label="Cómo se midió" name="method" maxLength={500} />
      <FormCheckbox
        id="mp-est-sin-merma"
        name="declared_no_loss"
        label="No tiene merma"
        hint="Obligatorio si la limpieza es 100 % y el factor 1: sin esta marca, el sistema nunca supone que no hay merma."
      />
      <Reason id="mp-motivo-estandar" />
    </ActionForm>
  );
}

function YieldTestForm({
  ingredient,
  processes,
  restaurants,
}: {
  ingredient: IngredientDetail;
  processes: { id: string; name: string }[];
  restaurants: { id: string; name: string }[];
}) {
  if (restaurants.length === 0)
    return <p className="text-base text-ink">No tenés locales donde registrar ensayos.</p>;
  const day = today();
  return (
    <ActionForm action={recordYieldTestAction} schema="yieldTest" submitLabel="Registrar ensayo">
      <input type="hidden" name="ingredientId" value={ingredient.id} />
      <FormSelect id="mp-ren-proceso" label="Proceso" name="process_id" required defaultValue="">
        <option value="" disabled>
          Elegí el proceso
        </option>
        {processes.map((p) => (
          <option key={p.id} value={p.id}>
            {p.name}
          </option>
        ))}
      </FormSelect>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormSelect
          id="mp-ren-local"
          label="Local donde se midió"
          name="restaurant_id"
          required
          defaultValue={restaurants.length === 1 ? restaurants[0]?.id : ""}
        >
          <option value="" disabled>
            Elegí el local
          </option>
          {restaurants.map((r) => (
            <option key={r.id} value={r.id}>
              {r.name}
            </option>
          ))}
        </FormSelect>
        <FormInput
          id="mp-ren-fecha"
          label="Fecha"
          name="tested_on"
          type="date"
          required
          max={day}
          defaultValue={day}
        />
      </div>
      <FormInput
        id="mp-ren-corte"
        label="Corte o presentación"
        hint="Solo si el estándar es de un corte. Por ejemplo, «en cubos»."
        name="cut"
        maxLength={80}
      />
      <p className="text-sm text-ink-muted">
        Pesos en gramos, sumando todas las muestras. Cargá el par que mediste: bruto y limpio, antes
        y después de cocinar, o los dos.
      </p>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id="mp-ren-bruto"
          label="Peso bruto (g)"
          name="gross_weight"
          inputMode="decimal"
        />
        <FormInput
          id="mp-ren-limpio"
          label="Peso limpio (g)"
          name="clean_weight"
          inputMode="decimal"
        />
        <FormInput
          id="mp-ren-antes"
          label="Antes de cocinar (g)"
          name="before_cooking_weight"
          inputMode="decimal"
        />
        <FormInput
          id="mp-ren-despues"
          label="Después de cocinar (g)"
          name="after_cooking_weight"
          inputMode="decimal"
        />
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id="mp-ren-muestras"
          label="Muestras"
          hint="Cuántas piezas o tandas pesaste en total."
          name="samples"
          inputMode="numeric"
          required
          defaultValue="1"
        />
        <FormInput
          id="mp-ren-responsable"
          label="Quién lo midió"
          name="responsible"
          maxLength={120}
        />
      </div>
      <Reason id="mp-motivo-ensayo" />
    </ActionForm>
  );
}
