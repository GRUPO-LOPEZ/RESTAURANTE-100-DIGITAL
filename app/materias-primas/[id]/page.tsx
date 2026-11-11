import { IngredientPrices } from "@/components/ingredient-prices";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import {
  createProductAction,
  createSupplierAction,
  proposeYieldAction,
  recordYieldTestAction,
  setActiveAction,
  setAliasesAction,
  setAllergenAction,
  setConversionAction,
  updateIngredientAction,
} from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormCheckbox, FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { Tabs } from "@/components/ui/tabs";
import {
  ALLERGEN_STATUS_LABELS,
  SOURCE_LABELS,
  getCategories,
  getIngredient,
  getSuppliers,
  getUnits,
  getYieldProcesses,
  getYieldRestaurants,
  getIngredientUsage,
  getYieldAlertThreshold,
  getYieldSummary,
  type AllergenStatus,
  type IngredientDetail,
  type IngredientUsage,
  type YieldRow,
} from "@/lib/catalog";
import { UUID, first, formatDate } from "@/lib/data";
import { getMenus, requireMenu } from "@/lib/auth/session";
import {
  cleaningDifference,
  describeCooking,
  exceedsYieldAlert,
  formatCleaning,
} from "@/lib/yields";
import { BackLink } from "@/components/back-link";

// Ficha de una materia prima (sección 18; ficha por pestañas del rediseño, ADR-0036). La pestaña va en la
// dirección (?seccion=), así se puede volver o compartir.
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

// El h1 de la ficha es el nombre de la materia prima (rediseño, ADR-0036); la ruta de arriba dice "Materia prima".
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

// Las pestañas de la ficha. "Precios y compra" junta el precio vigente y cómo se compra.
const SECTIONS = [
  { key: "datos", label: "Datos generales" },
  { key: "compra", label: "Precios y compra" },
  { key: "rendimientos", label: "Rendimientos" },
  { key: "conversiones", label: "Conversiones" },
  { key: "alergenos", label: "Alérgenos" },
  { key: "uso", label: "Dónde se usa" },
] as const;
type Section = (typeof SECTIONS)[number]["key"];

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

function Row({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col sm:flex-row sm:gap-2">
      <dt className="text-sm font-medium text-ink sm:w-40 sm:shrink-0">{label}</dt>
      <dd className="text-sm break-words text-ink-muted">{value ?? "—"}</dd>
    </div>
  );
}

const ALLERGEN_BADGE: Record<AllergenStatus, BadgeStatus> = {
  contains: "bad",
  may_contain: "warn",
  free_verified: "ok",
};

const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 6 });

function SourceOptions() {
  return (
    <>
      <option value="" disabled>
        Elegí de dónde sale
      </option>
      {Object.entries(SOURCE_LABELS).map(([value, label]) => (
        <option key={value} value={value}>
          {label}
        </option>
      ))}
    </>
  );
}

async function Ingredient({
  params,
  searchParams,
}: {
  params: PageProps<"/materias-primas/[id]">["params"];
  searchParams: PageProps<"/materias-primas/[id]">["searchParams"];
}) {
  await requireMenu("catalog");
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

  const wanted = first(query.seccion);
  const section: Section = SECTIONS.find((t) => t.key === wanted)?.key ?? "datos";
  const show = (key: Section) => section === key;
  // "← Volver" a la lista con sus filtros y su página: solo la lista de materias primas de esta aplicación.
  const volver = first(query.volver);
  const back = volver && /^\/materias-primas(\?|$)/.test(volver) ? volver : "/materias-primas";
  // Las pestañas conservan el "volver" a la lista.
  const tabHref = (key: Section) => {
    const q = new URLSearchParams();
    if (key !== "datos") q.set("seccion", key);
    if (back !== "/materias-primas") q.set("volver", back);
    return q.size ? `/materias-primas/${ingredient.id}?${q}` : `/materias-primas/${ingredient.id}`;
  };

  // Cada pestaña consulta solo lo que muestra.
  const none = Promise.resolve([]);
  const [categories, units, suppliers] = await Promise.all([
    canManage && show("datos") ? getCategories() : none,
    canManage && show("compra") ? getUnits() : none,
    canManage && show("compra") ? getSuppliers() : none,
  ]);
  const [yieldRows, processes, yieldRestaurants, yieldAlert, usage] = await Promise.all([
    show("rendimientos") ? getYieldSummary(ingredient.id) : none,
    canRecordYields && show("rendimientos") ? getYieldProcesses() : none,
    canRecordYields && show("rendimientos") ? getYieldRestaurants() : none,
    show("rendimientos") ? getYieldAlertThreshold(ingredient.id) : Promise.resolve(null),
    show("uso") ? getIngredientUsage(ingredient.id) : none,
  ]);

  return (
    <>
      <BackLink href={back}>Volver a materias primas</BackLink>

      {/* Encabezado: siempre a la vista, en todas las pestañas. */}
      <Card className="flex flex-col gap-2">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex min-w-0 flex-col">
            {/* El nombre ya es el título de la pantalla: acá van sus datos. */}
            <span className="text-base text-ink tabular-nums">
              {ingredient.code}
              {ingredient.category ? ` · ${ingredient.category}` : ""}
            </span>
          </div>
          {ingredient.isActive ? (
            <Badge status="ok">Activa</Badge>
          ) : (
            <Badge status="none">Desactivada</Badge>
          )}
        </div>
      </Card>

      <Tabs
        label="Secciones de la materia prima"
        items={SECTIONS.map((t) => ({
          href: tabHref(t.key),
          // Quien no ve precios encuentra ahí solo cómo se compra.
          label: t.key === "compra" && !menus.pricesView ? "Cómo se compra" : t.label,
          current: show(t.key),
        }))}
      />

      {show("datos") ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Datos generales</CardTitle>
          <dl className="flex flex-col gap-2">
            <Row label="Categoría" value={ingredient.category} />
            <Row label="Se usa en recetas en" value={ingredient.unit} />
            <Row label="Se compra en" value={ingredient.purchaseUnit} />
            <Row
              label="Otros nombres"
              value={ingredient.aliases.length > 0 ? ingredient.aliases.join(", ") : null}
            />
            <Row label="Observaciones" value={ingredient.notes} />
          </dl>
          {canManage ? (
            <div className="flex flex-col gap-2">
              <Disclosure summary="Editar datos">
                <ActionForm
                  action={updateIngredientAction}
                  schema="ingredientEdit"
                  submitLabel="Guardar"
                >
                  <input type="hidden" name="ingredientId" value={ingredient.id} />
                  <FormInput
                    id="mp-name"
                    label="Nombre"
                    name="name"
                    required
                    maxLength={120}
                    defaultValue={ingredient.name}
                  />
                  <FormSelect
                    id="mp-category_id"
                    label="Categoría"
                    name="category_id"
                    required
                    defaultValue={ingredient.categoryId}
                  >
                    {/* Los rubros dados de baja no se ofrecen, salvo el que ya tiene (ADR-0038). */}
                    {categories
                      .filter((c) => c.isActive || c.id === ingredient.categoryId)
                      .map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.label}
                        </option>
                      ))}
                  </FormSelect>
                  <FormTextarea
                    id="mp-notes"
                    label="Observaciones"
                    name="notes"
                    maxLength={1000}
                    defaultValue={ingredient.notes ?? ""}
                  />
                  <Reason id="mp-motivo-datos" />
                </ActionForm>
              </Disclosure>
              <Disclosure summary="Cambiar los otros nombres">
                <ActionForm
                  action={setAliasesAction}
                  schema="aliases"
                  submitLabel="Guardar nombres"
                >
                  <input type="hidden" name="ingredientId" value={ingredient.id} />
                  <FormTextarea
                    id="mp-aliases"
                    label="Otros nombres"
                    hint="Uno por línea o separados por coma. Sirven para buscar e importar sin duplicar."
                    name="aliases"
                    maxLength={1000}
                    defaultValue={ingredient.aliases.join("\n")}
                  />
                  <Reason id="mp-motivo-alias" />
                </ActionForm>
              </Disclosure>
              <Disclosure summary={ingredient.isActive ? "Desactivar" : "Volver a activar"}>
                <ActionForm
                  action={setActiveAction}
                  schema="reason"
                  submitLabel={ingredient.isActive ? "Desactivar" : "Activar"}
                  variant={ingredient.isActive ? "destructive" : "default"}
                >
                  <input type="hidden" name="ingredientId" value={ingredient.id} />
                  <input
                    type="hidden"
                    name="active"
                    value={ingredient.isActive ? "false" : "true"}
                  />
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
      ) : null}

      {show("compra") && menus.pricesView ? (
        <IngredientPrices
          ingredient={ingredient}
          canPropose={menus.pricesPropose}
          canSeeImpact={menus.costs}
          suppliers={suppliers}
        />
      ) : null}
      {show("compra") ? (
        <Products
          ingredient={ingredient}
          canManage={canManage}
          units={units}
          suppliers={suppliers}
        />
      ) : null}
      {show("rendimientos") ? (
        <Yields
          ingredient={ingredient}
          rows={yieldRows}
          alertPct={yieldAlert}
          canRecord={canRecordYields}
          processes={processes}
          restaurants={yieldRestaurants}
          canManageProcesses={menus.yieldsApprove}
        />
      ) : null}
      {show("conversiones") ? <Conversions ingredient={ingredient} canManage={canManage} /> : null}
      {show("alergenos") ? <Allergens ingredient={ingredient} canManage={canManage} /> : null}
      {show("uso") ? <Usage rows={usage} canOpen={menus.recipes} /> : null}
    </>
  );
}

// Dónde se usa (sección 18): las recetas vigentes o en preparación que la tienen, entre las que se ven.
function Usage({ rows, canOpen }: { rows: IngredientUsage[]; canOpen: boolean }) {
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>Dónde se usa</CardTitle>
      {rows.length === 0 ? (
        <p className="text-base text-ink-muted">Todavía no está en ninguna receta.</p>
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Recetas que la usan">
          {rows.map((r) => (
            <li key={r.recipeId} className="flex flex-wrap items-center justify-between gap-2">
              {canOpen ? (
                <Link
                  href={`/recetas/${r.recipeId}`}
                  className="inline-flex min-h-touch items-center text-base text-primary underline-offset-4 hover:underline"
                >
                  {r.name}
                </Link>
              ) : (
                <span className="text-base text-ink">{r.name}</span>
              )}
              <span className="text-sm text-ink-muted tabular-nums">
                {r.code} · v{r.versionNumber}{" "}
                {r.status === "published" ? "vigente" : "en preparación"}
              </span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function Products({
  ingredient,
  canManage,
  units,
  suppliers,
}: {
  ingredient: IngredientDetail;
  canManage: boolean;
  units: Awaited<ReturnType<typeof getUnits>>;
  suppliers: Awaited<ReturnType<typeof getSuppliers>>;
}) {
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>Cómo se compra</CardTitle>
      <CardDescription>
        Cada producto dice qué trae el envase. Varios productos pueden ser de la misma materia
        prima.
      </CardDescription>
      {ingredient.products.length === 0 ? (
        <p className="text-base text-ink-muted">Todavía no tiene productos de compra.</p>
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Productos de compra">
          {ingredient.products.map((p) => (
            <li key={p.id} className="flex flex-col gap-1 rounded-sm border border-line p-3">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <span className="font-medium text-ink">{p.description}</span>
                {p.isActive ? null : <Badge>Ya no se compra</Badge>}
              </div>
              <span className="text-sm text-ink-muted tabular-nums">
                {[p.code, p.contents, p.brandName, p.supplier].filter(Boolean).join(" · ")}
              </span>
            </li>
          ))}
        </ul>
      )}
      {canManage ? (
        <div className="flex flex-col gap-2">
          <Disclosure summary="Agregar un producto de compra">
            <ActionForm
              action={createProductAction}
              schema="product"
              submitLabel="Agregar producto"
            >
              <input type="hidden" name="ingredientId" value={ingredient.id} />
              <div className="grid gap-4 sm:grid-cols-2">
                <FormInput id="mp-code" label="Código" name="code" required maxLength={30} />
                <FormInput
                  id="mp-description"
                  label="Descripción"
                  hint="Como lo vende el proveedor."
                  name="description"
                  required
                  maxLength={200}
                />
              </div>
              <div className="grid gap-4 sm:grid-cols-3">
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
                  {units.map((u) => (
                    <option key={u.code} value={u.code}>
                      {u.name}
                    </option>
                  ))}
                </FormSelect>
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
              <div className="grid gap-4 sm:grid-cols-3">
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
                  {units
                    .filter((u) => u.dimension !== "package")
                    .map((u) => (
                      <option key={u.code} value={u.code}>
                        {u.name}
                      </option>
                    ))}
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
              </div>
              <Reason id="mp-motivo-producto" />
            </ActionForm>
          </Disclosure>
          <Disclosure summary="Crear un proveedor">
            <ActionForm
              action={createSupplierAction}
              schema="supplier"
              submitLabel="Crear proveedor"
            >
              <input type="hidden" name="groupId" value={ingredient.groupId} />
              <input type="hidden" name="ingredientId" value={ingredient.id} />
              <div className="grid gap-4 sm:grid-cols-3">
                <FormInput
                  id="mp-supplier_code"
                  label="Código"
                  name="code"
                  required
                  maxLength={30}
                />
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
              </div>
              <Reason id="mp-motivo-proveedor" />
            </ActionForm>
          </Disclosure>
        </div>
      ) : null}
    </Card>
  );
}

function Conversions({
  ingredient,
  canManage,
}: {
  ingredient: IngredientDetail;
  canManage: boolean;
}) {
  // Hoy, en la hora de la Argentina, como fecha de la medición por defecto.
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Buenos_Aires",
  }).format(new Date());
  const labels = { density: "Densidad", unit_weight: "Peso por unidad" } as const;
  const units = { density: "g por ml", unit_weight: "g por unidad" } as const;
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>Conversiones</CardTitle>
      <CardDescription>
        Solo hacen falta si se compra en una unidad y se usa en otra (por ejemplo, aceite por kg
        usado en ml). Nunca se supone que 1 litro pesa 1 kilo.
      </CardDescription>
      {ingredient.conversions.length === 0 ? (
        <p className="text-base text-ink-muted">No tiene conversiones cargadas.</p>
      ) : (
        <dl className="flex flex-col gap-2">
          {ingredient.conversions.map((c) => (
            <Row
              key={c.kind}
              label={labels[c.kind]}
              value={`${number.format(c.factor)} ${units[c.kind]} · ${SOURCE_LABELS[c.source]} · ${formatDate(c.measuredOn)}${c.measuredBy ? ` · ${c.measuredBy}` : ""}`}
            />
          ))}
        </dl>
      )}
      {canManage ? (
        <Disclosure summary="Cargar o cambiar una conversión">
          <ActionForm
            action={setConversionAction}
            schema="conversion"
            submitLabel="Guardar conversión"
          >
            <input type="hidden" name="ingredientId" value={ingredient.id} />
            <div className="grid gap-4 sm:grid-cols-2">
              <FormSelect id="mp-kind" label="Conversión" name="kind" required defaultValue="">
                <option value="" disabled>
                  Elegí cuál
                </option>
                <option value="density">Densidad (g por ml)</option>
                <option value="unit_weight">Peso por unidad (g por unidad)</option>
              </FormSelect>
              <FormInput id="mp-factor" label="Valor" name="factor" inputMode="decimal" required />
            </div>
            <div className="grid gap-4 sm:grid-cols-3">
              <FormSelect
                id="mp-source"
                label="De dónde sale"
                name="source"
                required
                defaultValue=""
              >
                <SourceOptions />
              </FormSelect>
              <FormInput
                id="mp-measured_on"
                label="Fecha de la medición"
                name="measured_on"
                type="date"
                required
                defaultValue={today}
              />
              <FormInput
                id="mp-measured_by"
                label="Quién lo midió"
                name="measured_by"
                maxLength={120}
              />
            </div>
            <Reason id="mp-motivo-conversion" />
          </ActionForm>
        </Disclosure>
      ) : null}
    </Card>
  );
}

function Allergens({
  ingredient,
  canManage,
}: {
  ingredient: IngredientDetail;
  canManage: boolean;
}) {
  const unvalidated = ingredient.allergens.some((a) => !a.validated);
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>Alérgenos</CardTitle>
      <CardDescription>
        «Sin dato» no quiere decir que no tenga: un plato con un ingrediente sin dato se muestra
        como no verificado.
      </CardDescription>
      {unvalidated ? (
        <p className="rounded-sm border border-line bg-warn p-3 text-base text-warn-ink">
          La lista de alérgenos todavía no está validada por un responsable.
        </p>
      ) : null}
      <ul className="flex flex-col gap-2" aria-label="Alérgenos">
        {ingredient.allergens.map((a) => (
          <li
            key={a.id}
            className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-0"
          >
            <span className="text-base text-ink">{a.name}</span>
            {a.status ? (
              <Badge status={ALLERGEN_BADGE[a.status]}>{ALLERGEN_STATUS_LABELS[a.status]}</Badge>
            ) : (
              <Badge>Sin dato</Badge>
            )}
          </li>
        ))}
      </ul>
      {canManage && ingredient.allergens.length > 0 ? (
        <Disclosure summary="Cambiar un alérgeno">
          <ActionForm action={setAllergenAction} schema="allergen" submitLabel="Guardar alérgeno">
            <input type="hidden" name="ingredientId" value={ingredient.id} />
            <div className="grid gap-4 sm:grid-cols-3">
              <FormSelect
                id="mp-allergen_id"
                label="Alérgeno"
                name="allergen_id"
                required
                defaultValue=""
              >
                <option value="" disabled>
                  Elegí el alérgeno
                </option>
                {ingredient.allergens.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </FormSelect>
              <FormSelect id="mp-status" label="Estado" name="status" defaultValue="">
                <option value="">Sin dato</option>
                {Object.entries(ALLERGEN_STATUS_LABELS).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </FormSelect>
              <FormSelect
                id="mp-allergen_source"
                label="De dónde sale"
                hint="No hace falta para «Sin dato»."
                name="source"
                defaultValue=""
              >
                <option value="">Sin indicar</option>
                {Object.entries(SOURCE_LABELS).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </FormSelect>
            </div>
            <Reason id="mp-motivo-alergeno" />
          </ActionForm>
        </Disclosure>
      ) : null}
    </Card>
  );
}

// Rendimientos (etapa 2.1 B): el estándar que usa el costo, lo que dicen los ensayos y la
// diferencia. Un ensayo nunca cambia el estándar: se propone uno nuevo y lo aprueba un Chef de
// todo el grupo (ADR-0021).
function YieldStandard({ row }: { row: YieldRow }) {
  if (row.standardCleaning === null || row.standardCooking === null) {
    return <Badge status="warn">Sin estándar aprobado</Badge>;
  }
  return (
    <span className="text-base text-ink tabular-nums">
      Limpieza {formatCleaning(row.standardCleaning)} · {describeCooking(row.standardCooking)}
      {row.declaredNoLoss ? " · declarado sin merma" : ""}
    </span>
  );
}

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

function YieldTests({ row, alertPct }: { row: YieldRow; alertPct: number | null }) {
  if (row.tests === 0) return <span className="text-sm text-ink-muted">Sin ensayos.</span>;
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
  return (
    <span className="flex flex-col items-start gap-1">
      <span className="text-sm text-ink-muted tabular-nums">{parts.join(" · ")}</span>
      {deviates(row, alertPct) ? (
        <Badge status="warn" className="whitespace-normal">
          El promedio se desvía más del {alertPct?.toLocaleString("es-AR")} % del estándar
        </Badge>
      ) : null}
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
}: {
  ingredient: IngredientDetail;
  rows: YieldRow[];
  alertPct: number | null;
  canRecord: boolean;
  processes: { id: string; name: string }[];
  restaurants: { id: string; name: string }[];
  canManageProcesses: boolean;
}) {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Buenos_Aires",
  }).format(new Date());
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>Rendimientos</CardTitle>
      <CardDescription>
        Cuánto rinde según el proceso. El costo usa siempre el estándar aprobado; los ensayos
        muestran lo que se midió en las cocinas y no lo cambian.
      </CardDescription>
      {rows.length === 0 ? (
        <p className="text-base text-ink-muted">
          Todavía no tiene rendimientos cargados.
          {canRecord ? " Registrá un ensayo o proponé un estándar." : ""}
        </p>
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Rendimientos por proceso">
          {rows.map((r) => (
            <li
              key={`${r.processId}-${r.cut ?? ""}-${r.supplier ?? ""}`}
              className="flex flex-col gap-1 rounded-sm border border-line p-3"
            >
              <div className="flex flex-wrap items-start justify-between gap-2">
                <span className="font-medium text-ink">
                  {[r.process, r.cut, r.supplier ? `de ${r.supplier}` : null]
                    .filter(Boolean)
                    .join(" · ")}
                </span>
                {r.pendingProposals > 0 ? (
                  <Badge status="review">Propuesta en revisión</Badge>
                ) : null}
              </div>
              <YieldStandard row={r} />
              <YieldTests row={r} alertPct={alertPct} />
            </li>
          ))}
        </ul>
      )}
      {canRecord && processes.length === 0 ? (
        <div className="flex flex-col gap-1">
          <p className="text-base text-ink">
            No hay procesos cargados (pelado, hervido…).
            {canManageProcesses ? "" : " Los crea un Chef de todo el grupo."}
          </p>
          {canManageProcesses ? (
            <Link
              href="/materias-primas/configuracion"
              className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
            >
              Crealos en la configuración del catálogo
            </Link>
          ) : null}
        </div>
      ) : null}
      {canRecord && processes.length > 0 ? (
        <div className="flex flex-col gap-2">
          <Disclosure summary="Registrar un ensayo">
            {restaurants.length === 0 ? (
              <p className="text-base text-ink">No tenés locales donde registrar ensayos.</p>
            ) : (
              <ActionForm
                action={recordYieldTestAction}
                schema="yieldTest"
                submitLabel="Registrar ensayo"
              >
                <input type="hidden" name="ingredientId" value={ingredient.id} />
                <div className="grid gap-4 sm:grid-cols-3">
                  <FormSelect
                    id="mp-ren-proceso"
                    label="Proceso"
                    name="process_id"
                    required
                    defaultValue=""
                  >
                    <option value="" disabled>
                      Elegí el proceso
                    </option>
                    {processes.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                  </FormSelect>
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
                    max={today}
                    defaultValue={today}
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
                  Pesos en gramos, sumando todas las muestras. Cargá el par que mediste: bruto y
                  limpio, antes y después de cocinar, o los dos.
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
            )}
          </Disclosure>
          <Disclosure summary="Proponer un estándar nuevo">
            <p className="text-base text-ink">
              No cambia nada hasta que lo apruebe un Chef de todo el grupo, distinto de vos.
            </p>
            <ActionForm
              action={proposeYieldAction}
              schema="yieldProposal"
              submitLabel="Proponer estándar"
            >
              <input type="hidden" name="ingredientId" value={ingredient.id} />
              <div className="grid gap-4 sm:grid-cols-2">
                <FormSelect
                  id="mp-est-proceso"
                  label="Proceso"
                  name="process_id"
                  required
                  defaultValue=""
                >
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
              </div>
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
              <FormTextarea
                id="mp-est-metodo"
                label="Cómo se midió"
                name="method"
                maxLength={500}
              />
              <FormCheckbox
                id="mp-est-sin-merma"
                name="declared_no_loss"
                label="No tiene merma"
                hint="Obligatorio si la limpieza es 100 % y el factor 1: sin esta marca, el sistema nunca supone que no hay merma."
              />
              <Reason id="mp-motivo-estandar" />
            </ActionForm>
          </Disclosure>
        </div>
      ) : null}
    </Card>
  );
}
