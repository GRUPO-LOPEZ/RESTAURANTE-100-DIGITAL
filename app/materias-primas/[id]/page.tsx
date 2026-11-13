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
import { Disclosure } from "@/components/disclosure";
import { IngredientPrices } from "@/components/ingredient-prices";
import {
  AllergensSection,
  ConversionsSection,
  DataSection,
  IngredientSheetProvider,
  SheetBar,
  ThawingToggle,
} from "@/components/ingredient-sheet/sheet-editor";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormCheckbox, FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { InfoTip } from "@/components/ui/info-tip";
import { ToggleField } from "@/components/ui/toggle-field";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
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

// Ficha única de una materia prima (ADR-0043, pedido de Soy del 2026-11-12): una sola página con índice, con la misma
// forma que la ficha de receta (ADR-0042). Lo que se edita se guarda junto con la barra de abajo (ADR-0039); las altas
// y las propuestas con aprobación (producto, proveedor, merma, rendimiento, ensayo, precio) van en un panel corto, con
// su propio flujo. Las reglas no cambian: las decide la base. En el celular, la ficha es de consulta.
export default function MateriaPrimaPage({
  params,
  searchParams,
}: PageProps<"/materias-primas/[id]">) {
  return (
    <AppShell
      title="Materia prima"
      heading={
        <Suspense fallback="Materia prima">
          <IngredientName params={params} />
        </Suspense>
      }
      description="Cómo se compra, cómo se mide y sus alérgenos."
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
  // Cada sección lleva el comienzo del id: Next guarda oculta la ficha anterior, y con dos «#uso» un enlace podría
  // bajar a la oculta (lo mismo que en la ficha de receta).
  const anchor = (key: string) => `${key}-${ingredient.id.slice(0, 8)}`;
  // Los enlaces de antes (?seccion=compra) bajan a la sección.
  const old = first(query.seccion);
  const volver = first(query.volver);
  const back = volver && /^\/materias-primas(\?|$)/.test(volver) ? volver : "/materias-primas";
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
    canManage ? getSuppliers() : none,
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
  const recipeUnit = units.find((u) => u.code === ingredient.unitCode);

  return (
    <>
      <BackLink href={back}>Volver a materias primas</BackLink>
      {codeNotice ? <Notice status="info">{codeNotice}</Notice> : null}
      {saved ? <Notice status={saved.status}>{saved.text}</Notice> : null}

      {/* Encabezado: código, estado, rubro, unidad de recetas e índice de secciones. */}
      <Card className="flex flex-col gap-3">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex min-w-0 flex-col gap-1">
            <span className="text-base text-ink tabular-nums">{ingredient.code}</span>
            <span className="text-sm text-ink-muted">
              Rubro: {ingredient.category || "sin rubro"} · Se usa en recetas en{" "}
              {recipeUnit?.label ?? ingredient.unit}
            </span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {ingredient.isActive ? (
              <Badge status="ok">Activa</Badge>
            ) : (
              <Badge status="none">Desactivada</Badge>
            )}
            {thawingPending || ingredient.requiresThawing ? (
              <Badge status="info">Se compra congelada</Badge>
            ) : null}
          </div>
        </div>
        <nav aria-label="Secciones de la materia prima">
          <ul className="flex flex-wrap gap-2">
            {SECTIONS.map((s) => (
              <li key={s.key}>
                <a
                  href={`#${anchor(s.key)}`}
                  className="inline-flex min-h-touch items-center rounded-sm border border-line px-3 text-sm text-ink hover:bg-line/50 desk:min-h-control-sm"
                >
                  {s.key === "compra" && !menus.pricesView ? "Cómo se compra" : s.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
        {canManage ? (
          // En el celular la ficha es de consulta (ADR-0043): desactivar se hace en la computadora.
          <div className="hidden desk:block">
            <Disclosure summary={ingredient.isActive ? "Desactivar" : "Volver a activar"}>
              <ActionForm
                action={setActiveAction}
                schema="reason"
                submitLabel={ingredient.isActive ? "Desactivar" : "Activar"}
                variant={ingredient.isActive ? "destructive" : "default"}
              >
                <input type="hidden" name="ingredientId" value={ingredient.id} />
                <input type="hidden" name="active" value={ingredient.isActive ? "false" : "true"} />
                <p className="text-base text-ink">
                  {ingredient.isActive
                    ? "No se borra nada: deja de ofrecerse para recetas nuevas y su historia queda."
                    : "Vuelve a ofrecerse para recetas nuevas."}
                </p>
                <Reason id="mp-motivo-activa" />
              </ActionForm>
            </Disclosure>
          </div>
        ) : null}
      </Card>

      <IngredientSheetProvider
        ingredientId={ingredient.id}
        stamp={sheetState?.stamp ?? null}
        editable={editable}
        hasPrices={sheetState?.hasPrices ?? false}
        initial={initial}
        options={options}
      >
        <Card id={anchor("datos")} className="flex scroll-mt-24 flex-col gap-4">
          <CardTitle>Datos generales</CardTitle>
          <DataSection />
        </Card>

        <Card id={anchor("compra")} className="flex scroll-mt-24 flex-col gap-4">
          <CardTitle>{menus.pricesView ? "Precios de compra" : "Cómo se compra"}</CardTitle>
          <PurchaseSection
            ingredient={ingredient}
            prices={menus.pricesView}
            money={menus.costs}
            place={place?.name ?? null}
            localCost={localCost}
            netCost={netCost}
            productPrices={productPrices}
            canManage={canManage}
            pricedProducts={sheetState?.pricedProducts ?? null}
            volver={back}
            units={units}
            suppliers={suppliers}
          />
        </Card>
        {menus.pricesView ? (
          <IngredientPrices
            ingredient={ingredient}
            canPropose={menus.pricesPropose}
            canSeeImpact={menus.costs}
            suppliers={suppliers}
          />
        ) : null}

        <Card id={anchor("rendimientos")} className="flex scroll-mt-24 flex-col gap-4">
          <Waste
            ingredient={ingredient}
            rows={yieldRows}
            processes={wasteProcesses}
            netCost={netCost}
            place={place?.name ?? null}
            thawingPending={thawingPending}
          />
          <Yields
            ingredient={ingredient}
            rows={yieldRows}
            alertPct={yieldAlert}
            canRecord={canRecordYields}
            processes={processes}
            restaurants={yieldRestaurants}
            canManageProcesses={menus.yieldsApprove}
            wasteProcesses={wasteProcesses}
            netCost={netCost}
          />
        </Card>

        <Card id={anchor("conversiones")} className="flex scroll-mt-24 flex-col gap-4">
          <CardTitle>Conversiones</CardTitle>
          <CardDescription>
            Solo hacen falta si se compra en una unidad y se usa en otra (por ejemplo, aceite por kg
            usado en ml). Nunca se supone que 1 litro pesa 1 kilo.
          </CardDescription>
          <ConversionsSection />
        </Card>

        <Card id={anchor("alergenos")} className="flex scroll-mt-24 flex-col gap-4">
          <div className="flex items-center gap-1">
            <CardTitle>Alérgenos</CardTitle>
            <InfoTip label="alérgenos">
              «Sin dato» no quiere decir que no tenga: un plato con un ingrediente sin dato se
              muestra como no verificado.
            </InfoTip>
          </div>
          <AllergensSection />
        </Card>

        <Card id={anchor("uso")} className="flex scroll-mt-24 flex-col gap-4">
          <CardTitle>Dónde se usa</CardTitle>
          <Usage rows={usage} canOpen={menus.recipes} />
        </Card>

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
    <ul className="flex flex-col gap-2" aria-label="Recetas que la usan">
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

function PurchaseSection({
  ingredient,
  prices,
  money,
  place,
  localCost,
  netCost,
  productPrices,
  canManage,
  pricedProducts,
  volver,
  units,
  suppliers,
}: {
  ingredient: IngredientDetail;
  prices: boolean;
  money: boolean;
  place: string | null;
  localCost: LocalCost | null;
  netCost: IngredientNetCost | null;
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
  const current = localCost ? bigUnitPrice(localCost.unit_cost, localCost.base_unit) : null;
  const missingPlace = "Elegí un local arriba para ver el precio.";
  return (
    <>
      {prices ? (
        <div className="grid gap-4 sm:grid-cols-2">
          <Metric
            label="Precio vigente"
            value={current ? `${formatMoney(current.value)} / ${current.unit}` : null}
            missingReason={
              !place
                ? missingPlace
                : localCost
                  ? (lineStatusLabel(localCost.status) ?? "Sin precio aprobado.")
                  : "Sin precio aprobado."
            }
            period={place ?? undefined}
            stale={localCost?.stale ?? false}
            asOf={localCost?.valid_from ? formatDate(localCost.valid_from) : null}
            status={localCost?.inherited ? "info" : "ok"}
            statusLabel={localCost?.inherited ? "Precio heredado" : "Al día"}
            emptyLabel="Sin datos"
          />
          {money ? (
            <Metric
              label={netCost ? `Costo neto (con merma) ${netCost.per}` : "Costo neto (con merma)"}
              value={netCost?.net != null ? formatMoney(netCost.net) : null}
              missingReason={
                !place
                  ? missingPlace
                  : !netCost
                    ? "No ves los costos de este local."
                    : (lineStatusLabel(netCost.netStatus) ?? "Falta un dato.")
              }
              period={place ?? undefined}
              stale={netCost?.stale ?? false}
              asOf={netCost?.validFrom ? formatDate(netCost.validFrom) : null}
              status={netCost?.inherited ? "info" : "ok"}
              statusLabel={netCost?.inherited ? "Precio heredado" : "Al día"}
              emptyLabel="Sin datos"
            />
          ) : null}
        </div>
      ) : (
        <CardDescription>
          Cada producto dice qué trae el envase. Varios productos pueden ser de la misma materia
          prima.
        </CardDescription>
      )}

      {products.length === 0 ? (
        <p className="text-base text-ink-muted">Todavía no tiene productos de compra.</p>
      ) : (
        <>
          {/* Computadora: tabla de ancho completo. Celular: tarjetas (ADR-0036). */}
          <div className="hidden overflow-x-auto desk:block">
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

      {canManage ? (
        <div className="hidden flex-wrap gap-2 desk:flex">
          <ActionModal
            label="Agregar producto de compra"
            title="Agregar producto de compra"
            description="Qué trae el envase, como lo vende el proveedor."
          >
            <ActionForm
              action={createProductAction}
              schema="product"
              submitLabel="Agregar producto"
            >
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
          <ActionModal
            label="Crear un proveedor"
            title="Crear un proveedor"
            description="Queda para todo el grupo. Después lo elegís en el producto."
          >
            <ActionForm
              action={createSupplierAction}
              schema="supplier"
              submitLabel="Crear proveedor"
            >
              <input type="hidden" name="groupId" value={ingredient.groupId} />
              <input type="hidden" name="ingredientId" value={ingredient.id} />
              <FormInput id="mp-supplier_code" label="Código" name="code" required maxLength={30} />
              <FormInput
                id="mp-supplier_name"
                label="Nombre"
                name="name"
                required
                maxLength={120}
              />
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
        </div>
      ) : null}
    </>
  );
}

// ---------------------------------------------------------------------------
// Mermas y rendimiento neto (ADR-0040): la merma de limpieza y la de descongelado en %, el rendimiento neto y el costo
// neto. Sin dato, «—» y el motivo: nunca 0 % ni 100 %.
// ---------------------------------------------------------------------------
function Waste({
  ingredient,
  rows,
  processes,
  netCost,
  place,
  thawingPending,
}: {
  ingredient: IngredientDetail;
  rows: YieldRow[];
  processes: { cleaning: string | null; thawing: string | null };
  netCost: IngredientNetCost | null;
  place: string | null;
  thawingPending: boolean;
}) {
  const general = (processId: string | null) =>
    rows.find((r) => r.processId === processId && r.cut === null && r.supplier === null);
  const cleaning = general(processes.cleaning);
  const thawing = general(processes.thawing);
  const thaws = ingredient.requiresThawing;
  const net = netYield({
    cleaning: cleaning?.standardCleaning ?? null,
    thawing: thawing?.standardCleaning ?? null,
    requiresThawing: thaws,
  });
  const pending = (cleaning?.pendingProposals ?? 0) + (thawing?.pendingProposals ?? 0);
  const approved = { status: "ok" as const, statusLabel: "Aprobada", emptyLabel: "Sin datos" };
  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-1">
          <CardTitle>Mermas y rendimientos</CardTitle>
          <InfoTip label="mermas y rendimiento neto">
            Lo que se pierde al limpiar y al descongelar. El costo usa siempre lo aprobado por un
            Chef de todo el grupo.
          </InfoTip>
        </div>
        {pending > 0 ? (
          <Badge status="review">
            {pending === 1 ? "1 merma en revisión" : `${pending} mermas en revisión`}
          </Badge>
        ) : null}
      </div>
      <div className="grid gap-4 sm:grid-cols-2 desk:grid-cols-4">
        <Metric
          label="Merma de limpieza"
          value={cleaning?.standardCleaning != null ? formatLoss(cleaning.standardCleaning) : null}
          missingReason="Sin merma de limpieza aprobada."
          {...approved}
        />
        {thaws ? (
          <Metric
            label="Merma de descongelado"
            value={thawing?.standardCleaning != null ? formatLoss(thawing.standardCleaning) : null}
            missingReason="Se compra congelada y falta su merma aprobada."
            {...approved}
          />
        ) : (
          <Metric
            label="Merma de descongelado"
            value="—"
            status="none"
            statusLabel="No aplica"
            comparison="No se compra congelada."
            emptyLabel="Sin datos"
          />
        )}
        <Metric
          label="Rinde neto"
          value={net.value !== null ? formatCleaning(net.value) : null}
          missingReason={net.missing ?? undefined}
          status="ok"
          statusLabel="Calculado"
          emptyLabel="Sin datos"
        />
        <Metric
          label={netCost ? `Costo neto ${netCost.per}` : "Costo neto"}
          value={netCost?.net != null ? formatMoney(netCost.net) : null}
          missingReason={
            !place
              ? "Elegí un local arriba para ver el costo."
              : !netCost
                ? "No ves los precios de este local."
                : (lineStatusLabel(netCost.netStatus) ?? "Falta un dato.")
          }
          period={place ?? undefined}
          // Un precio vencido va en «Atención» con su fecha; uno heredado de la marca o del grupo, en «Información».
          stale={netCost?.stale ?? false}
          asOf={netCost?.validFrom ? formatDate(netCost.validFrom) : null}
          status={netCost?.inherited ? "info" : "ok"}
          statusLabel={netCost?.inherited ? "Precio heredado" : "Al día"}
          emptyLabel="Sin datos"
        />
      </div>
      <ThawingToggle pending={thawingPending} />
    </>
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

function Yields({
  ingredient,
  rows,
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
  alertPct: number | null;
  canRecord: boolean;
  processes: { id: string; name: string }[];
  restaurants: { id: string; name: string }[];
  canManageProcesses: boolean;
  wasteProcesses: { cleaning: string | null; thawing: string | null };
  netCost: IngredientNetCost | null;
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
          <div className="hidden overflow-x-auto desk:block">
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
    </section>
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
