import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { ChevronDown } from "lucide-react";

import {
  createProductAction,
  createSupplierAction,
  setActiveAction,
  setAliasesAction,
  setAllergenAction,
  setConversionAction,
  updateIngredientAction,
} from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import {
  ALLERGEN_STATUS_LABELS,
  SOURCE_LABELS,
  getCategories,
  getIngredient,
  getSuppliers,
  getUnits,
  type AllergenStatus,
  type IngredientDetail,
} from "@/lib/catalog";
import { UUID, formatDate } from "@/lib/data";
import { getMenus, requireMenu } from "@/lib/auth/session";

export default function MateriaPrimaPage({ params }: PageProps<"/materias-primas/[id]">) {
  return (
    <AppShell title="Materia prima" description="Cómo se compra, cómo se mide y sus alérgenos.">
      <Suspense fallback={<Loading />}>
        <Ingredient params={params} />
      </Suspense>
    </AppShell>
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

// Cada acción va plegada, como en la ficha de una persona.
function Action({ summary, children }: { summary: string; children: React.ReactNode }) {
  return (
    <details className="group rounded-sm border border-line">
      <summary className="flex min-h-touch cursor-pointer items-center justify-between gap-2 px-3 text-base font-medium text-primary underline-offset-4 hover:underline">
        {summary}
        <ChevronDown
          aria-hidden="true"
          className="size-5 shrink-0 transition-transform group-open:rotate-180"
        />
      </summary>
      <div className="flex flex-col gap-4 p-3">{children}</div>
    </details>
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

async function Ingredient({ params }: { params: PageProps<"/materias-primas/[id]">["params"] }) {
  await requireMenu("catalog");
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const [ingredient, menus] = await Promise.all([getIngredient(id), getMenus()]);
  if (!ingredient) notFound();
  const canManage = menus.catalogManage;
  const [categories, units, suppliers] = canManage
    ? await Promise.all([getCategories(), getUnits(), getSuppliers()])
    : [[], [], []];

  return (
    <>
      <Link
        href="/materias-primas"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a materias primas
      </Link>

      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="flex flex-col">
            <CardTitle>{ingredient.name}</CardTitle>
            <span className="text-sm text-ink-muted tabular-nums">{ingredient.code}</span>
          </div>
          {ingredient.isActive ? <Badge status="ok">Activa</Badge> : <Badge>Desactivada</Badge>}
        </div>
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
        <p className="rounded-sm border border-line bg-info p-3 text-base text-info-ink">
          Todavía no se cargan precios ni rendimientos.
        </p>
        {canManage ? (
          <div className="flex flex-col gap-2">
            <Action summary="Editar datos">
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
                  {categories.map((c) => (
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
            </Action>
            <Action summary="Cambiar los otros nombres">
              <ActionForm action={setAliasesAction} schema="aliases" submitLabel="Guardar nombres">
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
            </Action>
            <Action summary={ingredient.isActive ? "Desactivar" : "Volver a activar"}>
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
            </Action>
          </div>
        ) : null}
      </Card>

      <Products ingredient={ingredient} canManage={canManage} units={units} suppliers={suppliers} />
      <Conversions ingredient={ingredient} canManage={canManage} />
      <Allergens ingredient={ingredient} canManage={canManage} />
    </>
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
          <Action summary="Agregar un producto de compra">
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
          </Action>
          <Action summary="Crear un proveedor">
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
          </Action>
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
        <Action summary="Cargar o cambiar una conversión">
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
        </Action>
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
        <Action summary="Cambiar un alérgeno">
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
        </Action>
      ) : null}
    </Card>
  );
}
