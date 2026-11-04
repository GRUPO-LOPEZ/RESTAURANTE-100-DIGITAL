import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { PrintButton } from "@/components/print-button";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { RELIABILITY, resolveCostPlace } from "@/lib/costs";
import { first, formatDate, uuidOrUndefined } from "@/lib/data";
import { formatMoney, parseAmount } from "@/lib/money";
import { LINE_UNITS, formatQuantity } from "@/lib/recipe-format";
import { getRecipe } from "@/lib/recipes";
import { getScaledCost, scaleVersion, type ScaledRecipe } from "@/lib/scaling";

// Escalado (ADR-0032; sección 13 del documento de Soy): ¿cuánto necesito para este lote? Solo lee: escalar nunca
// modifica la versión. La ve cualquiera que vea la receta; el costo proyectado, solo quien ve costos.
export default function EscalarPage({ params, searchParams }: PageProps<"/recetas/[id]/escalar">) {
  return (
    <AppShell
      title="¿Cuánto necesito para este lote?"
      description="Las cantidades de la receta para el objetivo que elijas. No cambia la receta."
    >
      <Suspense fallback={<Loading />}>
        <Scale params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// "1 unidad", "12 unidades": las etiquetas de las unidades están en singular.
function amount(value: number, code: string | null): string {
  const label = LINE_UNITS.find((u) => u.code === code)?.label ?? code ?? "";
  const plural =
    value !== 1 && (code === "unit" || code === "dozen")
      ? "es".slice(code === "dozen" ? 1 : 0)
      : "";
  return `${formatQuantity(value)} ${label}${plural}`;
}
const portionsText = (n: number) => `${formatQuantity(n)} ${n === 1 ? "porción" : "porciones"}`;
const unitLabel = (code: string) => LINE_UNITS.find((u) => u.code === code)?.label ?? code;

async function Scale({
  params,
  searchParams,
}: {
  params: PageProps<"/recetas/[id]/escalar">["params"];
  searchParams: PageProps<"/recetas/[id]/escalar">["searchParams"];
}) {
  const session = await requireMenu("recipes");
  const { id } = await params;
  if (!uuidOrUndefined(id)) notFound();
  const recipe = await getRecipe(id);
  if (!recipe) notFound();
  const version = recipe.current;
  const back = (
    <Link
      href={`/recetas/${recipe.id}`}
      className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline print:hidden"
    >
      Volver a la receta
    </Link>
  );
  if (!version)
    return (
      <>
        {back}
        <EmptyState title="Esta receta todavía no tiene una versión vigente." />
      </>
    );

  const query = await searchParams;
  const portions = version.portions;
  const yieldUnit = version.yieldUnit;
  const canPortions = portions !== null;
  const canYield = version.yieldQuantity !== null && yieldUnit !== null;
  if (!canPortions && !canYield)
    return (
      <>
        {back}
        <EmptyState title="No se puede escalar esta receta.">
          No tiene porciones ni rendimiento cargados.
        </EmptyState>
      </>
    );

  const wanted = first(query.por);
  const mode = wanted === "rendimiento" && canYield ? "yield" : canPortions ? "portions" : "yield";
  const raw = first(query.objetivo)?.trim() ?? "";
  const target = parseAmount(raw);
  const result =
    target !== null
      ? await scaleVersion(version.id, target, mode, mode === "yield" ? yieldUnit : null)
      : null;

  return (
    <>
      {back}
      <Card className="flex flex-col gap-4 print:hidden">
        <div className="flex flex-col gap-1">
          <CardTitle>{recipe.name}</CardTitle>
          <CardDescription>
            Versión {version.number}
            {portions !== null ? ` · ${portionsText(portions)}` : ""}
            {canYield ? ` · rinde ${amount(version.yieldQuantity ?? 0, yieldUnit)}` : ""}
          </CardDescription>
        </div>
        <form
          method="get"
          aria-label="Objetivo del lote"
          className="grid gap-4 sm:grid-cols-3 sm:items-end"
        >
          <Field id="escalar-objetivo" label="¿Cuánto querés hacer?">
            <Input
              name="objetivo"
              inputMode="decimal"
              enterKeyHint="go"
              autoComplete="off"
              defaultValue={first(query.objetivo) ?? ""}
              required
            />
          </Field>
          <Field id="escalar-por" label="Medido en">
            <Select name="por" defaultValue={mode === "yield" ? "rendimiento" : "porciones"}>
              {canPortions ? <option value="porciones">Porciones</option> : null}
              {canYield ? <option value="rendimiento">{unitLabel(yieldUnit ?? "")}</option> : null}
            </Select>
          </Field>
          <Button type="submit">Escalar</Button>
        </form>
      </Card>
      {raw !== "" && target === null ? (
        <Notice status="bad">Escribí un número, como 25 o 2,5.</Notice>
      ) : null}
      {result?.status === "bad" ? <Notice status="bad">{result.message}</Notice> : null}
      {result?.status === "ok" ? (
        <Result
          name={recipe.name}
          versionNumber={version.number}
          versionId={version.id}
          data={result.data}
          userId={session.user_id}
        />
      ) : null}
    </>
  );
}

async function Result({
  name,
  versionNumber,
  versionId,
  data,
  userId,
}: {
  name: string;
  versionNumber: number;
  versionId: string;
  data: ScaledRecipe;
  userId: string | undefined;
}) {
  const menus = await getMenus();
  const place = menus.costs ? (await resolveCostPlace(userId)).place : null;
  // El costo es secundario: si falla, las cantidades se ven igual, con un aviso.
  const cost = place
    ? await getScaledCost(versionId, place.id, data.exactFactor).catch(() => "failed" as const)
    : null;
  const scaled = data.lines.filter((l) => !l.noScale);
  const manual = data.lines.filter((l) => l.noScale);
  const batches = data.steps.filter((s) => s.batches !== null && s.batches > 1);
  const lot =
    data.targetPortions !== null
      ? portionsText(data.targetPortions)
      : amount(data.targetYield ?? 0, data.yieldUnit);
  const lotDetail =
    data.targetPortions !== null && data.targetYield !== null
      ? amount(data.targetYield, data.yieldUnit)
      : undefined;

  return (
    <>
      {cost === "failed" ? (
        <Notice status="warn">
          No pudimos calcular el costo proyectado. Las cantidades están bien.
        </Notice>
      ) : null}
      {batches.map((s) => (
        <Notice key={s.number} status="warn">
          Paso {s.number}: en {s.equipment} hacen falta {s.batches} tandas. Los tiempos no se
          multiplican: calculá cada tanda.
        </Notice>
      ))}
      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-col gap-1">
            <CardTitle>{name}</CardTitle>
            <p className="text-base text-ink tabular-nums">
              Para {lot}
              {lotDetail ? ` (${lotDetail})` : ""} · × {formatQuantity(data.factor)} · Versión{" "}
              {versionNumber}
              <span className="hidden print:inline">
                {" "}
                · Calculado el {formatDate(new Date().toISOString())}
              </span>
            </p>
          </div>
          <PrintButton />
        </div>
        {scaled.length === 0 ? (
          <EmptyState title="Esta receta no tiene líneas para escalar." />
        ) : (
          <ul aria-label="Cantidades para este lote" className="flex flex-col divide-y divide-line">
            {scaled.map((l) => (
              <Line key={l.order} line={l} />
            ))}
          </ul>
        )}
      </Card>
      {manual.length > 0 ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Para ajustar a mano</CardTitle>
          <CardDescription>Estas líneas no se escalan: quedan como en la receta.</CardDescription>
          <ul aria-label="Líneas que no se escalan" className="flex flex-col divide-y divide-line">
            {manual.map((l) => (
              <Line key={l.order} line={l} />
            ))}
          </ul>
        </Card>
      ) : null}
      <div className="grid gap-4 sm:grid-cols-3 print:hidden">
        <Kpi label="Multiplicás por" value={`× ${formatQuantity(data.factor)}`} />
        <Kpi label="Lote" value={lot} detail={lotDetail} />
        {cost && cost !== "failed" && place ? (
          <Kpi
            label={`Costo proyectado en ${place.name}`}
            value={cost.total === null ? "Sin costo" : formatMoney(cost.total)}
            detail={cost.gross === null ? undefined : `Con IVA: ${formatMoney(cost.gross)}`}
            status={RELIABILITY[cost.reliability].status}
            statusLabel={RELIABILITY[cost.reliability].label}
          />
        ) : null}
      </div>
      {data.steps.length > 0 ? (
        <Card className="flex flex-col gap-4 print:break-inside-avoid">
          <CardTitle>Equipo que se usa</CardTitle>
          <ul aria-label="Equipo" className="flex flex-col divide-y divide-line">
            {data.steps.map((s) => (
              <li key={s.number} className="flex flex-col gap-1 py-3">
                <span className="text-base font-medium text-ink">
                  Paso {s.number}: {s.equipment}
                </span>
                <span className="text-base text-ink tabular-nums">
                  {s.capacity === null
                    ? "Sin capacidad cargada: no se puede avisar si hacen falta más tandas."
                    : s.batches === null
                      ? `Entran ${amount(s.capacity, s.capacityUnit)}. No se pueden calcular las tandas: revisá el rendimiento de la receta.`
                      : `Entran ${amount(s.capacity, s.capacityUnit)} · ${s.batches === 1 ? "1 tanda" : `${s.batches} tandas`}`}
                </span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </>
  );
}

function Line({ line }: { line: ScaledRecipe["lines"][number] }) {
  return (
    <li className="flex flex-wrap items-baseline justify-between gap-x-4 py-3 print:break-inside-avoid">
      <span className="text-xl font-medium text-ink">{line.item}</span>
      <span className="flex shrink-0 flex-col items-end">
        <span className="text-xl font-semibold whitespace-nowrap text-ink tabular-nums">
          {amount(line.scaled, line.unit)}
        </span>
        <span className="text-sm text-ink-muted tabular-nums">
          Receta: {amount(line.quantity, line.unit)}
        </span>
      </span>
    </li>
  );
}
