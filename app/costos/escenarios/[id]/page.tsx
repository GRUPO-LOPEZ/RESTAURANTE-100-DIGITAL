import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense } from "react";

import {
  archiveScenarioAction,
  removeScenarioChangeAction,
  setScenarioPriceAction,
  setScenarioQuantityAction,
  setScenarioYieldAction,
} from "@/app/costos/escenarios/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { ScenarioTable } from "@/components/scenario-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select } from "@/components/ui/field";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { SCENARIO_PAGE, formatMoneyDifference } from "@/lib/cost-labels";
import { first, uuidOrUndefined } from "@/lib/data";
import { formatMoney, perBaseLabel } from "@/lib/money";
import {
  getScenario,
  getScenarioChanges,
  getScenarioIngredients,
  getScenarioLines,
  getScenarioPlaces,
  getScenarioRecipes,
  getScenarioResult,
  type ScenarioChange,
  type ScenarioIngredient,
} from "@/lib/scenarios";

type Props = PageProps<"/costos/escenarios/[id]">;

// Un escenario (ADR-0032): qué cambia y cuánto moverían esos cambios los costos de este local.
export default function EscenarioPage({ params, searchParams }: Props) {
  return (
    <AppShell
      title="¿Qué pasaría si…?"
      description="Lo simulado se calcula con los datos de hoy y no se guarda como costo."
    >
      <Suspense fallback={<Loading />}>
        <ScenarioDetail params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const number = (value: number | null) =>
  value === null ? "—" : value.toLocaleString("es-AR", { maximumFractionDigits: 4 });

function perUnit(ingredient: { unit: string | null }, unitCost: number | null) {
  const { factor, label } = perBaseLabel(ingredient.unit);
  return `${formatMoney(unitCost === null ? null : unitCost * factor)} ${label}`;
}

function changeText(c: ScenarioChange): string {
  if (c.kind === "price")
    return `${c.item}: ${perUnit(c, c.unitCost)} simulado${c.supplier ? `, comprándole a ${c.supplier}` : ""}`;
  if (c.kind === "yield")
    return `${c.item}: limpieza ${number((c.cleaningYield ?? 0) * 100)} % y cocción ×${number(c.cookingFactor)}, simulados`;
  const from =
    c.originalQuantity === null ? "" : `de ${number(c.originalQuantity)} ${c.unit ?? ""} `;
  return `${c.recipe ?? "Receta"} · ${c.item}: ${from}a ${number(c.quantity)} ${c.unit ?? ""}, simulado`;
}

function IngredientOptions({ ingredients }: { ingredients: ScenarioIngredient[] }) {
  return (
    <>
      <option value="">Elegí una materia prima</option>
      {ingredients.map((i) => (
        <option key={i.id} value={i.id}>
          {i.name} ·{" "}
          {i.unitCost === null
            ? `sin precio, se carga ${perBaseLabel(i.unit).label}`
            : `hoy ${perUnit(i, i.unitCost)}`}
        </option>
      ))}
    </>
  );
}

function ReasonField({ id }: { id: string }) {
  return <FormTextarea id={id} label="Motivo" name="reason" required maxLength={500} />;
}

async function ScenarioDetail({ params, searchParams }: Pick<Props, "params" | "searchParams">) {
  await requireMenu("scenarios");
  const [{ id: rawId }, query] = await Promise.all([params, searchParams]);
  const id = uuidOrUndefined(rawId);
  if (!id) notFound();
  const scenario = await getScenario(id);
  if (!scenario) notFound();

  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(query.pagina) ?? "1", 10) - 1 || 0, 1000),
  );
  const recipeId = uuidOrUndefined(first(query.receta));
  const notice = first(query.aviso);
  const editable = !scenario.archived;

  const [places, changes, result, ingredients, recipes, suppliers, lines] = await Promise.all([
    getScenarioPlaces(),
    getScenarioChanges(id),
    getScenarioResult(id, page),
    editable ? getScenarioIngredients(id) : [],
    editable ? getScenarioRecipes(id) : [],
    // Quien no ve proveedores simula igual: el proveedor es solo una referencia.
    editable ? getSuppliers().catch(() => []) : [],
    editable && recipeId ? getScenarioLines(id, recipeId) : [],
  ]);
  // Una página que ya no existe (un enlace viejo) vuelve a la primera, con las tarjetas.
  if (page > 0 && result.rows.length === 0) redirect(`/costos/escenarios/${id}`);
  const pages = Math.max(1, Math.ceil(result.total / SCENARIO_PAGE));
  const pageLink = (n: number) =>
    `/costos/escenarios/${id}?pagina=${n + 1}${recipeId ? `&receta=${recipeId}` : ""}`;
  const placeName = places.find((p) => p.id === scenario.restaurantId)?.name ?? "este local";

  return (
    <>
      <Notice status="info">Es una simulación: no cambia ningún costo ni receta.</Notice>
      {notice === "quitado" ? <Notice status="ok">Cambio quitado.</Notice> : null}
      {notice === "archivado" ? <Notice status="ok">Escenario archivado.</Notice> : null}

      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle className="min-w-0 [overflow-wrap:anywhere]">{scenario.name}</CardTitle>
            {scenario.archived ? <Badge status="neutral">Archivado</Badge> : null}
          </div>
          <CardDescription>Simulación para {placeName}.</CardDescription>
          <Link
            href={`/costos/escenarios?local=${scenario.restaurantId}`}
            className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline"
          >
            Volver a los escenarios
          </Link>
        </div>
        {changes.length === 0 ? (
          <EmptyState title="Este escenario todavía no tiene cambios.">
            {editable ? "Cargá un precio, un rendimiento o un gramaje." : null}
          </EmptyState>
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Cambios del escenario">
            {changes.map((c) => (
              <li key={c.id} className="flex flex-col gap-2 rounded-lg border border-line p-3">
                <span className="text-base text-ink tabular-nums">{changeText(c)}</span>
                {c.applies ? null : (
                  <span>
                    <Badge status="warn">No se aplica: hay otra versión</Badge>
                  </span>
                )}
                {editable ? (
                  <Disclosure summary={`Quitar: ${c.item}`}>
                    <ActionForm
                      action={removeScenarioChangeAction}
                      schema="reason"
                      submitLabel="Quitar este cambio"
                      pendingLabel="Quitando…"
                      variant="outline"
                    >
                      <input type="hidden" name="scenarioId" value={id} />
                      <input type="hidden" name="changeId" value={c.id} />
                      <ReasonField id={`quitar-${c.id}`} />
                    </ActionForm>
                  </Disclosure>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </Card>

      {editable ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Agregar un cambio</CardTitle>
          <Disclosure summary="Precio, también de otro proveedor">
            <ActionForm
              action={setScenarioPriceAction}
              schema="scenarioPrice"
              submitLabel="Simular este precio"
              pendingLabel="Guardando…"
            >
              <input type="hidden" name="scenarioId" value={id} />
              <FormSelect id="precio-materia" label="Materia prima" name="ingredient" required>
                <IngredientOptions ingredients={ingredients} />
              </FormSelect>
              <FormInput
                id="precio-valor"
                label="Precio simulado"
                hint="Por kg, litro o unidad, como dice la lista. Sin IVA; si el local no lo descuenta, con IVA."
                name="amount"
                inputMode="decimal"
                autoComplete="off"
                required
              />
              {suppliers.length > 0 ? (
                <FormSelect id="precio-proveedor" label="Proveedor (opcional)" name="supplier">
                  <option value="">Sin proveedor</option>
                  {suppliers.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name}
                    </option>
                  ))}
                </FormSelect>
              ) : null}
              <ReasonField id="precio-motivo" />
            </ActionForm>
          </Disclosure>
          <Disclosure summary="Rendimiento">
            <ActionForm
              action={setScenarioYieldAction}
              schema="scenarioYield"
              submitLabel="Simular este rendimiento"
              pendingLabel="Guardando…"
            >
              <input type="hidden" name="scenarioId" value={id} />
              <FormSelect id="rinde-materia" label="Materia prima" name="ingredient" required>
                <IngredientOptions ingredients={ingredients} />
              </FormSelect>
              <div className="grid gap-4 sm:grid-cols-2">
                <FormInput
                  id="rinde-limpieza"
                  label="Limpieza (%)"
                  hint="Cuánto queda después de limpiar, por ejemplo 80."
                  name="cleaning"
                  inputMode="decimal"
                  autoComplete="off"
                  required
                />
                <FormInput
                  id="rinde-coccion"
                  label="Factor de cocción"
                  hint="1 si no cambia con la cocción."
                  name="cooking"
                  inputMode="decimal"
                  autoComplete="off"
                  defaultValue="1"
                  required
                />
              </div>
              <ReasonField id="rinde-motivo" />
            </ActionForm>
          </Disclosure>
          <div id="gramaje" className="scroll-mt-4">
            <Disclosure summary="Gramaje de una receta" open={Boolean(recipeId)}>
              <form method="get" action="#gramaje" className="flex flex-col gap-4">
                {page > 0 ? <input type="hidden" name="pagina" value={page + 1} /> : null}
                <Field id="gramaje-receta" label="Receta">
                  <Select name="receta" defaultValue={recipeId ?? ""}>
                    <option value="">Elegí una receta</option>
                    {recipes.map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.name}
                      </option>
                    ))}
                  </Select>
                </Field>
                <div>
                  <Button type="submit" variant="outline">
                    Ver sus líneas
                  </Button>
                </div>
              </form>
              {recipeId && lines.length === 0 ? (
                <EmptyState title="Esa receta no tiene líneas para cambiar en este local." />
              ) : null}
              {lines.length > 0 ? (
                <ActionForm
                  action={setScenarioQuantityAction}
                  schema="scenarioQuantity"
                  submitLabel="Simular este gramaje"
                  pendingLabel="Guardando…"
                >
                  <input type="hidden" name="scenarioId" value={id} />
                  <FormSelect id="gramaje-linea" label="Línea" name="line" required>
                    <option value="">Elegí una línea</option>
                    {lines.map((l) => (
                      <option key={l.id} value={l.id}>
                        {l.item} · {number(l.quantity)} {l.unit}
                      </option>
                    ))}
                  </FormSelect>
                  <FormInput
                    id="gramaje-valor"
                    label="Cantidad simulada"
                    hint="En la misma unidad de la línea."
                    name="quantity"
                    inputMode="decimal"
                    autoComplete="off"
                    required
                  />
                  <ReasonField id="gramaje-motivo" />
                </ActionForm>
              ) : null}
            </Disclosure>
          </div>
        </Card>
      ) : null}

      {result.total > 0 ? (
        <>
          <div className="grid gap-4 lg:grid-cols-3">
            <Kpi
              label="Recetas que cambiarían"
              value={result.changed}
              detail={`de ${result.total}`}
            />
            <Kpi
              label="Mayor suba simulada"
              value={result.topRise ? formatMoneyDifference(result.topRise.amount) : "Ninguna"}
              detail={result.topRise?.recipe}
            />
            <Kpi
              label="Mayor baja simulada"
              value={result.topDrop ? formatMoneyDifference(result.topDrop.amount) : "Ninguna"}
              detail={result.topDrop?.recipe}
            />
          </div>
          <Card className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
              <CardTitle>Cómo quedarían las recetas (simulado)</CardTitle>
              <CardDescription>
                Costo de hoy contra costo simulado, el que cuenta en {placeName}.
              </CardDescription>
            </div>
            <ScenarioTable rows={result.rows} />
            {pages > 1 ? (
              <nav aria-label="Páginas" className="flex flex-wrap items-center gap-2">
                {page > 0 ? (
                  <Button asChild variant="outline">
                    <Link href={pageLink(page - 1)}>Anterior</Link>
                  </Button>
                ) : null}
                <span className="text-sm text-ink-muted tabular-nums">
                  Página {page + 1} de {pages}
                </span>
                {page + 1 < pages ? (
                  <Button asChild variant="outline">
                    <Link href={pageLink(page + 1)}>Siguiente</Link>
                  </Button>
                ) : null}
              </nav>
            ) : null}
          </Card>
        </>
      ) : changes.length > 0 ? (
        <EmptyState title="Estos cambios no alcanzan a ninguna receta de este local." />
      ) : null}

      {editable ? (
        <Disclosure summary="Archivar este escenario">
          <ActionForm
            action={archiveScenarioAction}
            schema="reason"
            submitLabel="Archivar"
            pendingLabel="Archivando…"
            variant="outline"
          >
            <input type="hidden" name="scenarioId" value={id} />
            <ReasonField id="archivar-motivo" />
          </ActionForm>
        </Disclosure>
      ) : null}
    </>
  );
}
