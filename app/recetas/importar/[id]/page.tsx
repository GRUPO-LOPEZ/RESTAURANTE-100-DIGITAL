import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { Download } from "lucide-react";

import {
  cancelImportAction,
  confirmIngredientsAction,
  confirmRecipesAction,
  validateImportAction,
} from "@/app/recetas/importar/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormTextarea } from "@/components/ui/form";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { first, formatDateTime, uuidOrUndefined } from "@/lib/data";
import {
  IMPORTED_RECIPES_PAGE,
  IMPORT_ERRORS_PAGE,
  JOB_STATUS_BADGE,
  JOB_STATUS_LABELS,
  ROW_ACTION_LABELS,
  ROW_KIND_LABELS,
  getImportJob,
  getImportIssues,
  getImportedRecipes,
  type ImportJob,
  type RowAction,
  type RowKind,
} from "@/lib/imports/jobs";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

// Vista previa de una importación (ADR-0027): ¿qué se va a crear y qué hay que corregir? Nunca
// muestra precios: los guarda la base aparte y esta pantalla no los lee.
export default function ImportacionPage({
  params,
  searchParams,
}: PageProps<"/recetas/importar/[id]">) {
  return (
    <AppShell
      title="Vista previa de la importación"
      description="Lo que se crea, lo que ya existe y lo que hay que corregir, antes de confirmar."
    >
      <Suspense fallback={<Loading />}>
        <Preview params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const KINDS: RowKind[] = ["ingredient", "preparation", "dish", "line"];
const ACTIONS: RowAction[] = ["create", "reuse", "skip", "error"];

function count(job: ImportJob, kind: RowKind, action: RowAction | null): number {
  return job.summary
    .filter((s) => s.kind === kind && s.action === action)
    .reduce((a, s) => a + s.rows, 0);
}

async function Preview({
  params,
  searchParams,
}: {
  params: PageProps<"/recetas/importar/[id]">["params"];
  searchParams: PageProps<"/recetas/importar/[id]">["searchParams"];
}) {
  await requireMenu("imports");
  const id = uuidOrUndefined((await params).id);
  if (!id) notFound();
  const query = await searchParams;
  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(query.pagina) ?? "1", 10) - 1 || 0, 1000),
  );
  const [job, menus] = await Promise.all([getImportJob(id), getMenus()]);
  if (!job) notFound();
  const recipesPage = Math.max(
    0,
    Math.min(Number.parseInt(first(query.recetas) ?? "1", 10) - 1 || 0, 1000),
  );
  const [issues, recipes] = await Promise.all([
    getImportIssues(id, page),
    job.status === "confirmed"
      ? getImportedRecipes(id, recipesPage)
      : Promise.resolve({ rows: [], total: 0 }),
  ]);
  const recipePages = Math.max(1, Math.ceil(recipes.total / IMPORTED_RECIPES_PAGE));
  const csvFailed = first(query.csv) === "error";
  const pages = Math.max(1, Math.ceil(issues.total / IMPORT_ERRORS_PAGE));

  const open = job.status !== "confirmed" && job.status !== "cancelled";
  const validated = job.status === "validated" || job.status === "ingredients_confirmed";
  const ingredientsToConfirm =
    count(job, "ingredient", "create") + count(job, "ingredient", "reuse") > 0;
  const needsPurchasing = job.status === "validated" && ingredientsToConfirm;
  const unvalidated = job.summary.some((s) => s.action === null);

  return (
    <>
      <BackLink href="/recetas/importar">Volver a importaciones</BackLink>

      <Card className="flex flex-col gap-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="break-all">{job.fileName}</CardTitle>
          <Badge status={JOB_STATUS_BADGE[job.status]}>{JOB_STATUS_LABELS[job.status]}</Badge>
        </div>
        <CardDescription className="tabular-nums">
          {job.brandName} · prefijo {job.prefix} · subido el {formatDateTime(job.createdAt)}
        </CardDescription>
        {job.ingredientsConfirmedAt ? (
          <p className="text-sm text-ink-muted tabular-nums">
            Materias primas confirmadas el {formatDateTime(job.ingredientsConfirmedAt)}.
          </p>
        ) : null}
        {job.confirmedAt ? (
          <p className="text-sm text-ink-muted tabular-nums">
            Recetas confirmadas el {formatDateTime(job.confirmedAt)}.
          </p>
        ) : null}
      </Card>

      <section
        aria-label="Totales"
        className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"
      >
        {unvalidated ? (
          <Kpi
            label="Estado"
            value="Sin validar"
            status="warn"
            statusLabel="Falta validar"
            className="sm:col-span-2 lg:col-span-4"
          />
        ) : (
          <>
            <Kpi label="Se crean" value={sum(job, "create")} detail="Materias primas y recetas" />
            <Kpi
              label="Se usan las que ya existen"
              value={sum(job, "reuse") + sum(job, "skip")}
              detail="No se duplican"
            />
            <Kpi
              label="Errores"
              value={job.errors}
              detail="Problemas que frenan una fila"
              status={job.errors > 0 ? "bad" : "ok"}
              statusLabel={job.errors > 0 ? "Esas filas no se importan" : "Sin errores"}
            />
            <Kpi
              label="Avisos"
              value={job.warnings}
              detail="No frenan la importación"
              status={job.warnings > 0 ? "warn" : "ok"}
              statusLabel={job.warnings > 0 ? "Para revisar" : "Sin avisos"}
            />
          </>
        )}
      </section>

      <Card className="flex flex-col gap-4">
        <CardTitle>Qué hay en el Excel</CardTitle>
        <ul className="flex flex-col divide-y divide-line">
          {KINDS.map((kind) => {
            const parts = ACTIONS.map((a) => [a, count(job, kind, a)] as const).filter(
              ([, n]) => n > 0,
            );
            const total = job.summary
              .filter((s) => s.kind === kind)
              .reduce((a, s) => a + s.rows, 0);
            return (
              <li key={kind} className="flex flex-col gap-1 py-3">
                <span className="text-base font-medium text-ink tabular-nums">
                  {ROW_KIND_LABELS[kind]}: {total.toLocaleString("es-AR")}
                </span>
                {parts.length > 0 ? (
                  <span className="text-sm text-ink-muted tabular-nums">
                    {parts
                      .map(([a, n]) => `${ROW_ACTION_LABELS[a]}: ${n.toLocaleString("es-AR")}`)
                      .join(" · ")}
                  </span>
                ) : null}
              </li>
            );
          })}
        </ul>
      </Card>

      {open ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Próximo paso</CardTitle>
          {!validated ? (
            menus.importsRun ? (
              <>
                <CardDescription>Validá la importación para ver qué se crea.</CardDescription>
                <ActionForm
                  action={validateImportAction}
                  submitLabel="Validar"
                  pendingLabel="Validando…"
                >
                  <input type="hidden" name="jobId" value={job.id} />
                </ActionForm>
              </>
            ) : (
              <Notice status="info">Falta que quien la subió la valide.</Notice>
            )
          ) : needsPurchasing ? (
            menus.catalogManage ? (
              <>
                <CardDescription>
                  Compras confirma las materias primas: se crean las nuevas y se usan las que ya
                  existen. Después la cocina confirma las recetas.
                </CardDescription>
                <ActionForm
                  action={confirmIngredientsAction}
                  schema="reason"
                  submitLabel="Confirmar materias primas"
                  pendingLabel="Confirmando…"
                >
                  <input type="hidden" name="jobId" value={job.id} />
                  <FormTextarea
                    id="imp-mp-motivo"
                    label="Motivo de la confirmación"
                    hint="Queda en el historial."
                    name="reason"
                    required
                    maxLength={500}
                  />
                </ActionForm>
              </>
            ) : (
              <Notice status="info">
                Falta que Compras confirme las materias primas. Después se confirman las recetas.
              </Notice>
            )
          ) : menus.importsApprove && menus.recipesDraft ? (
            <>
              <CardDescription>
                Se crean las recetas en borrador, con sus componentes en gramos. Las filas con error
                no se importan. Después completás los pasos y pedís la revisión de cada una.
              </CardDescription>
              <ActionForm
                action={confirmRecipesAction}
                schema="reason"
                submitLabel="Confirmar recetas"
                pendingLabel="Creando recetas…"
              >
                <input type="hidden" name="jobId" value={job.id} />
                <FormTextarea
                  id="imp-rec-motivo"
                  label="Motivo de la confirmación"
                  hint="Queda en el historial."
                  name="reason"
                  required
                  maxLength={500}
                />
              </ActionForm>
            </>
          ) : (
            <Notice status="info">Falta que la cocina confirme las recetas.</Notice>
          )}
          {validated && menus.importsRun ? (
            <div className="flex flex-col gap-4 border-t border-line pt-4">
              <ActionForm
                action={validateImportAction}
                submitLabel="Validar de nuevo"
                pendingLabel="Validando…"
                variant="outline"
              >
                <input type="hidden" name="jobId" value={job.id} />
              </ActionForm>
            </div>
          ) : null}
        </Card>
      ) : null}

      {job.status === "confirmed" ? (
        <Card className="flex flex-col gap-4">
          <CardTitle className="tabular-nums">
            Recetas creadas: {recipes.total.toLocaleString("es-AR")}
          </CardTitle>
          {recipes.rows.length === 0 ? (
            <EmptyState title="Esta importación no creó recetas." />
          ) : (
            <ul aria-label="Recetas creadas" className="flex flex-col divide-y divide-line">
              {recipes.rows.map((r) => (
                <li key={r.recipeId} className="flex flex-col py-2">
                  <Link
                    href={`/recetas/${r.recipeId}`}
                    className="inline-flex min-h-touch items-center text-base text-primary underline-offset-4 hover:underline"
                  >
                    {r.name || r.code}
                  </Link>
                  <span className="text-sm text-ink-muted tabular-nums">
                    {r.kind === "dish" ? "Plato" : "Preparación"} · {job.prefix}-{r.code}
                  </span>
                </li>
              ))}
            </ul>
          )}
          {recipePages > 1 ? (
            <nav
              aria-label="Páginas de recetas creadas"
              className="flex flex-wrap items-center gap-2"
            >
              {recipesPage > 0 ? (
                <Button asChild variant="outline">
                  <Link href={`/recetas/importar/${job.id}?recetas=${recipesPage}`}>Anterior</Link>
                </Button>
              ) : null}
              <span className="text-sm text-ink-muted tabular-nums">
                Página {recipesPage + 1} de {recipePages}
              </span>
              {recipesPage + 1 < recipePages ? (
                <Button asChild variant="outline">
                  <Link href={`/recetas/importar/${job.id}?recetas=${recipesPage + 2}`}>
                    Siguiente
                  </Link>
                </Button>
              ) : null}
            </nav>
          ) : null}
        </Card>
      ) : null}

      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="tabular-nums">
            Problemas por fila: {issues.total.toLocaleString("es-AR")}
          </CardTitle>
          {issues.total > 0 ? (
            <Button asChild variant="outline">
              <a href={`/recetas/importar/${job.id}/errores`} download>
                <Download aria-hidden="true" />
                Descargar (CSV)
              </a>
            </Button>
          ) : null}
        </div>
        {csvFailed ? (
          <Notice status="bad">No pudimos armar el archivo de problemas. Probá de nuevo.</Notice>
        ) : null}
        {issues.rows.length === 0 ? (
          <EmptyState title={issues.total > 0 ? "Esa página no existe." : "No hay problemas."} />
        ) : (
          <ul aria-label="Problemas por fila" className="flex flex-col divide-y divide-line">
            {issues.rows.map((e, i) => (
              <li key={`${page}-${i}`} className="flex flex-col gap-1 py-3">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge status={e.severity === "error" ? "bad" : "warn"}>
                    {e.severity === "error" ? "Error" : "Aviso"}
                  </Badge>
                  {e.sheet ? (
                    <span className="text-sm text-ink-muted tabular-nums">
                      {e.sheet}
                      {e.row ? `, fila ${e.row}` : ""}
                      {e.field ? `, ${e.field}` : ""}
                    </span>
                  ) : null}
                </div>
                <span className="text-base text-ink">{e.message}</span>
              </li>
            ))}
          </ul>
        )}
        {pages > 1 ? (
          <nav aria-label="Páginas de problemas" className="flex flex-wrap items-center gap-2">
            {page > 0 ? (
              <Button asChild variant="outline">
                <Link href={`/recetas/importar/${job.id}?pagina=${page}`}>Anterior</Link>
              </Button>
            ) : null}
            <span className="text-sm text-ink-muted tabular-nums">
              Página {page + 1} de {pages}
            </span>
            {page + 1 < pages ? (
              <Button asChild variant="outline">
                <Link href={`/recetas/importar/${job.id}?pagina=${page + 2}`}>Siguiente</Link>
              </Button>
            ) : null}
          </nav>
        ) : null}
      </Card>

      {open && menus.importsRun ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Cancelar la importación</CardTitle>
          <CardDescription>
            No se crea nada. Si el Excel tenía errores, corregilo y subilo de nuevo.
          </CardDescription>
          <ActionForm
            action={cancelImportAction}
            schema="reason"
            submitLabel="Cancelar importación"
            pendingLabel="Cancelando…"
            variant="destructive"
          >
            <input type="hidden" name="jobId" value={job.id} />
            <FormTextarea
              id="imp-cancelar-motivo"
              label="Motivo de la cancelación"
              hint="Queda en el historial."
              name="reason"
              required
              maxLength={500}
            />
          </ActionForm>
        </Card>
      ) : null}
    </>
  );
}

function sum(job: ImportJob, action: RowAction): number {
  return job.summary
    .filter((s) => s.action === action && s.kind !== "line")
    .reduce((a, s) => a + s.rows, 0);
}
