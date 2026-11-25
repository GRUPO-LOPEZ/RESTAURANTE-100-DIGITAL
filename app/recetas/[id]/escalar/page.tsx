import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { PrintButton } from "@/components/print-button";
import { PaperPages } from "@/components/recipe-cards/paper-pages";
import { ScaleForm, type ScaleUnit } from "@/components/recipe-cards/scale-form";
import { Badge } from "@/components/ui/badge";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/kpi";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { ScrollFocus } from "@/components/ui/scroll-focus";
import { Tile } from "@/components/ui/tile";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { RELIABILITY, resolveCostPlace } from "@/lib/costs";
import { first, formatDate, uuidOrUndefined } from "@/lib/data";
import { measureWithContent } from "@/lib/measures";
import { formatMoney, parseAmount } from "@/lib/money";
import { formatQuantity, unitDimension, versionLine } from "@/lib/recipe-format";
import { getKitchenCard, getRecipe } from "@/lib/recipes";
import { getScaledCost, scaleVersion, type ScaleMode, type ScaledRecipe } from "@/lib/scaling";
import { amountText, spoonEquivalent, toBigger, unitText } from "@/lib/scaling-units";

// Hacer varias recetas (pedido de Soy, ADR-0065; antes «Escalar», ADR-0032): cuánto hace falta de cada ingrediente, en su
// unidad y sin densidad. Solo lee: nunca modifica la versión. La ve cualquiera que vea la receta; el costo proyectado,
// solo quien ve costos.
type Props = PageProps<"/recetas/[id]/escalar">;

export default function EscalarPage({ params, searchParams }: Props) {
  return (
    <AppShell
      title="Hacer varias recetas"
      fill
      heading={
        <Suspense fallback="Hacer varias recetas">
          <Name params={params} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back params={params} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={<PrintButton />}
    >
      <Suspense fallback={<Loading />}>
        <Scale params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const recipeOnce = cache(getRecipe);
const cardOnce = cache(getKitchenCard);

async function recipeOf(params: Props["params"]) {
  const session = await requireMenu("recipes");
  const { id } = await params;
  if (!uuidOrUndefined(id)) notFound();
  const recipe = await recipeOnce(id);
  if (!recipe) notFound();
  return { session, recipe };
}

const portionsText = (n: number) => `${formatQuantity(n)} ${unitText(n, "portion")}`;
const recipesText = (n: number) => `${formatQuantity(n)} ${n === 1 ? "receta" : "recetas"}`;

async function Name({ params }: { params: Props["params"] }) {
  return (await recipeOf(params)).recipe.name;
}

async function Back({ params }: { params: Props["params"] }) {
  const { recipe } = await recipeOf(params);
  return (
    <BackLink href={`/recetas/${recipe.id}`} label="Volver a la receta">
      Receta
    </BackLink>
  );
}

async function Meta({ params }: { params: Props["params"] }) {
  const { recipe } = await recipeOf(params);
  const v = recipe.current;
  if (!v) return null;
  return (
    <span className="text-sm text-ink-muted tabular-nums">
      Versión {v.number}
      {v.portions !== null ? ` · ${portionsText(v.portions)}` : ""}
      {v.yieldQuantity !== null && v.yieldUnit
        ? ` · rinde ${amountText({ value: v.yieldQuantity, unit: v.yieldUnit })}`
        : ""}
    </span>
  );
}

async function Scale({ params, searchParams }: Props) {
  const { session, recipe } = await recipeOf(params);
  const version = recipe.current;
  if (!version) return <EmptyState title="Esta receta todavía no tiene una versión vigente." />;

  const query = await searchParams;
  const yieldUnit = version.yieldQuantity !== null ? version.yieldUnit : null;
  const units: ScaleUnit[] = [{ value: "recetas", label: "recetas" }];
  if (version.portions !== null) units.push({ value: "porciones", label: "porciones" });
  if (yieldUnit !== null)
    units.push({
      value: "rendimiento",
      label:
        unitDimension(yieldUnit) === "count"
          ? unitText(2, yieldUnit)
          : `${unitText(1, yieldUnit)} de producto`,
    });
  // Los enlaces de antes (?por=porciones&objetivo=8) siguen andando; lo que la receta no tiene, por recetas.
  const wanted = first(query.por);
  const unit = units.find((u) => u.value === wanted)?.value ?? "recetas";
  const mode: ScaleMode =
    unit === "porciones" ? "portions" : unit === "rendimiento" ? "yield" : "recipes";
  const raw = first(query.objetivo)?.trim() ?? "1";
  const target = parseAmount(raw);
  const result =
    target !== null
      ? await scaleVersion(version.id, target, mode, mode === "yield" ? yieldUnit : null)
      : null;

  return (
    <>
      <section
        aria-label="Cuánto"
        className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-line bg-surface p-4 desk:py-3 print:hidden"
      >
        <ScaleForm
          path={`/recetas/${recipe.id}/escalar`}
          target={raw}
          unit={unit}
          units={units}
          error={
            target === null
              ? "Escribí un número, como 25 o 2,5."
              : result?.status === "bad"
                ? result.message
                : undefined
          }
        />
        {result?.status === "ok" ? (
          <p className="text-base text-ink tabular-nums" aria-live="polite">
            = <Lot data={result.data} mode={mode} />
          </p>
        ) : null}
      </section>
      {result?.status === "ok" ? (
        <Result
          recipeId={recipe.id}
          name={recipe.name}
          versionId={version.id}
          data={result.data}
          userId={session.user_id}
        />
      ) : null}
    </>
  );
}

// «48 porciones · 15,4 kg»: lo que sale. Cuántas recetas son, si se pidió en otra cosa.
function Lot({ data, mode }: { data: ScaledRecipe; mode: ScaleMode }) {
  const parts = [
    mode !== "recipes" ? recipesText(data.factor) : null,
    data.targetPortions !== null ? portionsText(data.targetPortions) : null,
    data.targetYield !== null && data.yieldUnit
      ? amountText(toBigger({ value: data.targetYield, unit: data.yieldUnit }))
      : null,
  ].filter((p): p is string => p !== null);
  if (parts.length === 0) return <>sin rendimiento cargado</>;
  return (
    <>
      <span className="font-semibold">{parts[0]}</span>
      {parts.slice(1).map((p) => ` · ${p}`)}
    </>
  );
}

type Line = ScaledRecipe["lines"][number];

const scaledAmount = (l: Line) => toBigger({ value: l.scaled, unit: l.unit });

function BigAmount({ line }: { line: Line }) {
  const amount = scaledAmount(line);
  const also = spoonEquivalent(amount);
  return (
    <span className="inline-flex flex-wrap items-baseline justify-end gap-x-1 whitespace-nowrap tabular-nums">
      <span className="text-xl font-semibold">{formatQuantity(amount.value)}</span>
      <span className="text-sm">{unitText(amount.value, amount.unit)}</span>
      {also ? <span className="text-sm">· {also}</span> : null}
    </span>
  );
}

const measureOf = (l: Line) =>
  measureWithContent(l.measureScaled, l.measureName, l.measureContent, l.measureUnit);

async function Result({
  recipeId,
  name,
  versionId,
  data,
  userId,
}: {
  recipeId: string;
  name: string;
  versionId: string;
  data: ScaledRecipe;
  userId: string | undefined;
}) {
  const [menus, card] = await Promise.all([getMenus(), cardOnce(recipeId)]);
  const place = menus.costs ? (await resolveCostPlace(userId)).place : null;
  // El costo es secundario: si falla, las cantidades se ven igual, con un aviso.
  const cost = place
    ? await getScaledCost(versionId, place.id, data.exactFactor).catch(() => "failed" as const)
    : null;
  const scaled = data.lines.filter((l) => !l.noScale);
  const manual = data.lines.filter((l) => l.noScale);
  const columns: DataColumn<Line>[] = [
    {
      key: "item",
      header: "Ingrediente",
      mobile: "title",
      cell: (l) => <span className="text-base font-medium">{l.item}</span>,
    },
    {
      key: "one",
      header: "Para 1 receta",
      align: "right",
      cell: (l) => amountText({ value: l.quantity, unit: l.unit }),
    },
    {
      key: "many",
      header: `Para ${recipesText(data.factor)}`,
      align: "right",
      mobile: "status",
      cell: (l) => <BigAmount line={l} />,
    },
  ];
  // Sin ninguna medida práctica, la columna no dice nada.
  if (scaled.some((l) => l.measureScaled !== null))
    columns.push({
      key: "measure",
      header: "Medida práctica",
      cell: (l) => measureOf(l) ?? <span className="text-ink-muted">—</span>,
    });

  return (
    <>
      {cost === "failed" ? (
        <Notice status="warn">
          No pudimos calcular el costo proyectado. Las cantidades están bien.
        </Notice>
      ) : null}
      <PaperPages
        header={
          <>
            <span className="text-2xl font-semibold text-ink">{name}</span>
            <span className="text-base text-ink tabular-nums">
              Para {recipesText(data.factor)}: <Lot data={data} mode="recipes" />
            </span>
            <span className="text-sm text-ink tabular-nums">
              {card
                ? `${versionLine({
                    number: card.versionNumber,
                    code: card.code,
                    publishedOn: formatDate(card.publishedAt),
                    approvedBy: card.approvedBy,
                  })} · `
                : ""}
              calculado el {formatDate(new Date().toISOString())}
            </span>
          </>
        }
      >
        {/* Por debajo de 1.280 px, una columna: la tabla con su alto y la página con scroll. */}
        <div className="grid gap-4 xl:min-h-64 xl:flex-[1_1_0px] xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] xl:grid-rows-[minmax(0,1fr)] print:block print:space-y-4">
          <div className="flex min-w-0 flex-col desk:h-96 xl:h-auto xl:min-h-0 print:h-auto">
            <DataTable
              caption="Cantidades para este lote"
              columns={columns}
              rows={scaled}
              rowKey={(l) => String(l.order)}
              scroll
              empty={<EmptyState title="Esta receta no tiene líneas para multiplicar." />}
            />
          </div>
          <section
            aria-label="Costo y equipos"
            className="relative flex min-w-0 flex-col gap-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary xl:min-h-0 xl:overflow-y-auto print:overflow-visible"
          >
            <ScrollFocus />
            {menus.costs && cost !== "failed" ? (
              <Metric
                label={place ? `Costo proyectado en ${place.name}` : "Costo proyectado"}
                value={cost && cost.total !== null ? formatMoney(cost.total) : null}
                missingReason={
                  !place
                    ? "Elegí un local arriba para ver el costo."
                    : cost
                      ? "Falta el costo de algún ingrediente."
                      : "No ves los costos de ese local."
                }
                emptyLabel="Sin datos"
                comparison={
                  cost && cost.gross !== null ? `Con IVA: ${formatMoney(cost.gross)}` : undefined
                }
                status={cost ? RELIABILITY[cost.reliability].status : "none"}
                statusLabel={cost ? RELIABILITY[cost.reliability].label : "Sin datos"}
                compact
                className="desk:shrink-0 print:hidden"
              />
            ) : null}
            {manual.length > 0 ? (
              <Tile title="Para ajustar a mano" className="desk:shrink-0 print:border-0 print:p-0">
                <p className="text-sm text-ink-muted">
                  No se multiplican: quedan como en la receta.
                </p>
                <ul
                  aria-label="Líneas que no se multiplican"
                  className="flex flex-col divide-y divide-line"
                >
                  {manual.map((l) => (
                    <li
                      key={l.order}
                      className="flex flex-wrap items-baseline justify-between gap-x-4 py-2 print:break-inside-avoid"
                    >
                      <span className="text-base text-ink">{l.item}</span>
                      <span className="text-right text-base font-semibold text-ink tabular-nums">
                        {amountText(scaledAmount(l))}
                        {measureOf(l) ? (
                          <span className="block text-sm font-normal">{measureOf(l)}</span>
                        ) : null}
                      </span>
                    </li>
                  ))}
                </ul>
              </Tile>
            ) : null}
            {data.steps.length > 0 ? (
              <Tile title="Equipos" className="desk:shrink-0 print:border-0 print:p-0">
                <ul aria-label="Equipo" className="flex flex-col divide-y divide-line">
                  {data.steps.map((s) => (
                    <li
                      key={s.number}
                      className="flex flex-wrap items-center justify-between gap-2 py-2 print:break-inside-avoid"
                    >
                      <span className="min-w-0 text-base text-ink">
                        Paso {s.number}: {s.equipment}
                        <span className="block text-sm text-ink-muted tabular-nums">
                          {s.capacity === null
                            ? "Sin capacidad cargada: no se puede avisar si hacen falta más tandas."
                            : s.batches === null
                              ? `Entran ${amountText({ value: s.capacity, unit: s.capacityUnit ?? "" })}. No se pueden calcular las tandas: revisá el rendimiento de la receta.`
                              : `Entran ${amountText({ value: s.capacity, unit: s.capacityUnit ?? "" })}`}
                        </span>
                      </span>
                      {s.batches === null ? null : (
                        <Badge status={s.batches > 1 ? "warn" : "ok"}>
                          {s.batches === 1 ? "1 tanda" : `${s.batches} tandas`}
                        </Badge>
                      )}
                    </li>
                  ))}
                </ul>
                {data.steps.some((s) => s.batches !== null && s.batches > 1) ? (
                  <p className="text-sm text-ink">
                    Los tiempos no se multiplican: calculá cada tanda.
                  </p>
                ) : null}
              </Tile>
            ) : null}
            <Tile
              title="Cada ingrediente sigue en su unidad"
              className="desk:shrink-0 print:hidden"
            >
              <p className="text-sm text-ink">
                Los gramos pasan a kilos y los mililitros a litros al llegar a 1.000. Lo que va en
                litros nunca se pasa a peso. Las cucharadas y las tazas, si quedan muchas, dicen al
                lado cuánto son.
              </p>
            </Tile>
          </section>
        </div>
      </PaperPages>
    </>
  );
}
