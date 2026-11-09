import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { RecipeCardExtras } from "@/components/recipe-card-extras";
import { ReportPrintButton } from "@/components/report-print-button";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Input } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { first, formatDate, formatDateTime, uuidOrUndefined } from "@/lib/data";
import {
  REPORT_EXPORT_LIMIT,
  REPORT_PAGE,
  argentinaDay,
  formatValue,
  reportDefinition,
  reportFileName,
  reportPeriod,
  type ReportColumn,
  type ReportRow,
} from "@/lib/report-labels";
import { getReportPage, getReportPlaces, getReportRecipes, getReportRows } from "@/lib/reports";

type Props = PageProps<"/reportes/[reporte]">;

// Un reporte: en pantalla va por páginas, y sale entero en Excel o CSV.
export default function ReportePage({ params, searchParams }: Props) {
  return (
    <AppShell title="Reporte">
      <Suspense fallback={<Loading />}>
        <Report params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

function ReportTable({
  title,
  heading,
  columns,
  rows,
}: {
  title: string;
  heading: string;
  columns: ReportColumn[];
  rows: ReportRow[];
}) {
  const cell = (row: ReportRow, c: ReportColumn) => formatValue(row[c.key] ?? null, c.kind);
  // Lo primero de cada fila lleva a la ficha, para corregir sin salir del reporte.
  const first = (row: ReportRow, c: ReportColumn) =>
    row.href ? (
      <Link
        href={row.href}
        className="text-primary underline-offset-4 hover:underline print:text-ink"
      >
        {cell(row, c)}
      </Link>
    ) : (
      cell(row, c)
    );
  const align = (c: ReportColumn) =>
    c.kind === "text" || c.kind === "date" ? "text-left" : "text-right tabular-nums";
  return (
    <>
      <ul
        className="grid gap-2 sm:grid-cols-2 lg:hidden print:hidden"
        aria-label={`Filas de ${title}`}
      >
        {rows.map((row, i) => (
          <li key={i} className="flex flex-col gap-1 rounded-lg border border-line p-4">
            {columns.map((c, n) => (
              <span
                key={c.key}
                className={
                  n === 0
                    ? "font-medium [overflow-wrap:anywhere] text-ink"
                    : "text-sm [overflow-wrap:anywhere] text-ink"
                }
              >
                {n === 0 ? null : <span className="text-ink-muted">{c.label}: </span>}
                {n === 0 ? first(row, c) : cell(row, c)}
              </span>
            ))}
          </li>
        ))}
      </ul>
      <table className="hidden w-full border-collapse text-left lg:table print:table">
        <caption className="sr-only">{title}</caption>
        <thead>
          {/* El encabezado de la tabla se repite en cada hoja: así una hoja suelta dice qué es. */}
          <tr className="hidden print:table-row">
            <th
              colSpan={columns.length}
              scope="colgroup"
              className="pb-2 text-sm font-normal text-ink-muted"
            >
              {heading}
            </th>
          </tr>
          <tr className="border-b border-line">
            {columns.map((c) => (
              <th
                key={c.key}
                scope="col"
                className={`px-3 py-2 text-sm font-medium text-ink-muted print:px-1 print:py-1 ${align(c)}`}
              >
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className="border-b border-line last:border-0 print:break-inside-avoid">
              {columns.map((c, n) => (
                <td
                  key={c.key}
                  className={`px-3 py-2 text-ink print:px-1 print:py-1 print:text-sm ${align(c)}`}
                >
                  {n === 0 ? first(row, c) : cell(row, c)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

// Una ficha es de una receta: primero se elige cuál, entre las vigentes del local.
async function RecipePicker({
  reportKey,
  title,
  local,
  search,
}: {
  reportKey: string;
  title: string;
  local: string;
  search: string | undefined;
}) {
  const { recipes, total } = await getReportRecipes(local, search?.slice(0, 100));
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>{title}</CardTitle>
        <CardDescription>¿De qué receta?</CardDescription>
        <Link
          href={`/reportes?local=${local}`}
          className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline"
        >
          Volver a los reportes
        </Link>
      </div>
      <form
        method="get"
        role="search"
        aria-label="Buscar una receta"
        className="grid gap-4 sm:grid-cols-3 sm:items-end"
      >
        <input type="hidden" name="local" value={local} />
        <Field id="ficha-buscar" label="Buscar">
          <Input
            type="search"
            name="buscar"
            enterKeyHint="search"
            maxLength={100}
            defaultValue={search ?? ""}
            placeholder="Nombre o código"
          />
        </Field>
        <Button type="submit">Buscar</Button>
      </form>
      {recipes.length === 0 ? (
        <EmptyState
          title={
            search?.trim()
              ? "No encontramos recetas vigentes con ese nombre o código."
              : "Este local todavía no tiene recetas vigentes."
          }
        >
          {search?.trim() ? "Probá con otra palabra, o con parte del código." : null}
        </EmptyState>
      ) : (
        <ul className="flex flex-col divide-y divide-line" aria-label="Recetas">
          {recipes.map((r) => (
            <li key={r.id}>
              <Link
                href={`/reportes/${reportKey}?local=${local}&receta=${r.id}`}
                className="flex min-h-touch items-center justify-between gap-4 py-2 underline-offset-4 hover:underline"
              >
                <span className="text-base [overflow-wrap:anywhere] text-primary">{r.name}</span>
                <span className="shrink-0 text-sm text-ink-muted tabular-nums">
                  {r.code} · {r.type}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
      {total > recipes.length ? (
        <p className="text-sm text-ink-muted">
          Se muestran {recipes.length} de {total}. Buscá por nombre o código para encontrar la que
          falta.
        </p>
      ) : null}
    </Card>
  );
}

async function Report({ params, searchParams }: Pick<Props, "params" | "searchParams">) {
  await requireMenu("reports");
  const [{ reporte }, query] = await Promise.all([params, searchParams]);
  const report = reportDefinition(reporte);
  const local = uuidOrUndefined(first(query.local));
  if (!report || !local) notFound();
  const recipe = report.recipe ? uuidOrUndefined(first(query.receta)) : undefined;
  if (report.recipe && !recipe) {
    return (
      <RecipePicker
        reportKey={report.key}
        title={report.title}
        local={local}
        search={first(query.buscar)}
      />
    );
  }

  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(query.pagina) ?? "1", 10) - 1 || 0, 10_000),
  );
  const now = new Date();
  const period = reportPeriod(first(query.desde), first(query.hasta), now);
  // La vista para imprimir trae todas las filas: un papel no se pagina con un botón.
  // Una ficha entra entera: se imprime tal como se ve.
  const printing = first(query.imprimir) === "1" || Boolean(report.recipe);
  const filter = { restaurantId: local, ...period, recipeId: recipe };
  const [places, result] = await Promise.all([
    getReportPlaces(),
    printing
      ? getReportRows(report.key, filter)
      : getReportPage(report.key, filter, REPORT_PAGE, page * REPORT_PAGE),
  ]);
  const place = places.find((p) => p.id === local);
  if (!place || !result) notFound();
  const filters = report.period
    ? `&desde=${period.from}&hasta=${period.to}`
    : recipe
      ? `&receta=${recipe}`
      : "";
  const here = `/reportes/${report.key}?local=${local}${filters}`;
  // Una página que ya no existe (un enlace viejo) vuelve a la primera.
  if (page > 0 && result.rows.length === 0) redirect(here);
  const pages = printing ? 1 : Math.max(1, Math.ceil(result.total / REPORT_PAGE));
  const generated = formatDateTime(now.toISOString());
  const range = report.period
    ? ` · Del ${formatDate(period.from)} al ${formatDate(period.to)}`
    : "";
  const summary = result.summary;
  const alerts = result.alerts;
  const heading = `Grupo LF · ${report.title}${summary?.[0] ? ` · ${summary[0]}` : ""} · ${place.name} · Datos del ${generated}${range}`;
  const cut = printing && result.total > result.rows.length;

  return (
    <>
      {first(query.aviso) === "no-se-pudo" ? (
        <div className="print:hidden">
          <Notice status="bad">No pudimos preparar el archivo. Probá de nuevo.</Notice>
        </div>
      ) : null}
      <Card className="flex flex-col gap-4 print:border-0 print:p-0">
        <div className="flex flex-col gap-1">
          <CardTitle>{report.title}</CardTitle>
          <CardDescription>
            {place.name} · Datos del {generated} {range} · {result.total}{" "}
            {report.recipe
              ? result.total === 1
                ? "línea"
                : "líneas"
              : result.total === 1
                ? "fila"
                : "filas"}
          </CardDescription>
          {summary ? (
            <ul className="flex flex-col gap-1 text-base text-ink" aria-label="De qué receta es">
              {summary.map((line) => (
                <li key={line} className="tabular-nums">
                  {line}
                </li>
              ))}
            </ul>
          ) : null}
          {alerts ? (
            <div className="flex flex-col gap-2 pt-2">
              <h3 className="text-base font-medium text-ink">Alérgenos</h3>
              <ul className="flex flex-wrap gap-2" aria-label="Alérgenos">
                {alerts.map((a) => (
                  <li key={a.text}>
                    <Badge status={a.status} className="text-base whitespace-normal">
                      {a.text}
                    </Badge>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
          <Link
            href={recipe ? `/reportes/${report.key}?local=${local}` : `/reportes?local=${local}`}
            className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline print:hidden"
          >
            {recipe ? "Elegir otra receta" : "Volver a los reportes"}
          </Link>
          {report.key === "recipe_card" && recipe ? (
            <Link
              href={`/recetas/${recipe}/cocina`}
              className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline print:hidden"
            >
              Ver en la cocina, con letra grande
            </Link>
          ) : null}
        </div>
        {report.period ? (
          <form
            method="get"
            className="grid gap-4 sm:grid-cols-3 sm:items-end print:hidden"
            aria-label="Elegir el período"
          >
            <input type="hidden" name="local" value={local} />
            <Field id="reporte-desde" label="Desde">
              <Input type="date" name="desde" defaultValue={period.from} />
            </Field>
            <Field id="reporte-hasta" label="Hasta">
              <Input type="date" name="hasta" defaultValue={period.to} />
            </Field>
            <Button type="submit">Ver</Button>
          </form>
        ) : null}
        <div className="flex flex-wrap items-start gap-2 print:hidden">
          {printing ? (
            <ReportPrintButton
              report={report.key}
              local={local}
              rows={result.rows.length}
              recipe={recipe}
              fileName={reportFileName(report.key, place.name, argentinaDay(now))}
            />
          ) : (
            <Button asChild variant="outline">
              <Link href={`${here}&imprimir=1`}>Preparar para imprimir o PDF</Link>
            </Button>
          )}
          <Button asChild variant="outline">
            <a href={`/reportes/${report.key}/exportar?local=${local}${filters}&formato=xlsx`}>
              Bajar en Excel
            </a>
          </Button>
          <Button asChild variant="outline">
            <a href={`/reportes/${report.key}/exportar?local=${local}${filters}&formato=csv`}>
              Bajar en CSV
            </a>
          </Button>
        </div>
        {cut ? (
          <Notice status="warn">
            Salen las primeras {REPORT_EXPORT_LIMIT.toLocaleString("es-AR")} de{" "}
            {result.total.toLocaleString("es-AR")} filas.
          </Notice>
        ) : null}
        {!printing && pages > 1 ? (
          <p className="hidden text-sm text-ink-muted print:block">
            Filas {page * REPORT_PAGE + 1} a {page * REPORT_PAGE + result.rows.length} de{" "}
            {result.total}. Esta hoja no trae el reporte completo.
          </p>
        ) : null}
        {result.rows.length === 0 ? (
          <EmptyState title={report.empty} />
        ) : (
          <ReportTable
            title={report.title}
            heading={heading}
            columns={report.columns}
            rows={result.rows}
          />
        )}
        {report.key === "recipe_card" && recipe && summary ? (
          <RecipeCardExtras recipeId={recipe} />
        ) : null}
        {pages > 1 ? (
          <nav aria-label="Páginas" className="flex flex-wrap items-center gap-2 print:hidden">
            {page > 0 ? (
              <Button asChild variant="outline">
                <Link href={`${here}&pagina=${page}`}>Anterior</Link>
              </Button>
            ) : null}
            <span className="text-sm text-ink-muted tabular-nums">
              Página {page + 1} de {pages}
            </span>
            {page + 1 < pages ? (
              <Button asChild variant="outline">
                <Link href={`${here}&pagina=${page + 2}`}>Siguiente</Link>
              </Button>
            ) : null}
          </nav>
        ) : null}
      </Card>
    </>
  );
}
