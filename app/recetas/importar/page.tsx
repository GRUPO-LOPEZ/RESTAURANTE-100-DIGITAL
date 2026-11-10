import Link from "next/link";
import { Suspense } from "react";
import { ArrowLeft, Upload } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import { first, formatDateTime } from "@/lib/data";
import {
  IMPORT_JOBS_PAGE,
  JOB_STATUS_BADGE,
  JOB_STATUS_LABELS,
  getImportJobs,
} from "@/lib/imports/jobs";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Importaciones del recetario (ADR-0027): ¿qué Excel se subieron y en qué paso están?
export default function ImportacionesPage({ searchParams }: PageProps<"/recetas/importar">) {
  return (
    <AppShell
      title="Importaciones"
      description="Los recetarios de Excel que se subieron y en qué paso está cada uno."
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Jobs searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// La acción principal, a la derecha del título (ADR-0036).
async function Actions() {
  const menus = await getMenus();
  if (!menus.importsRun) return null;
  return (
    <Button asChild>
      <Link href="/recetas/importar/nueva">
        <Upload aria-hidden="true" />
        Importar recetario
      </Link>
    </Button>
  );
}

async function Jobs({
  searchParams,
}: {
  searchParams: PageProps<"/recetas/importar">["searchParams"];
}) {
  await requireMenu("imports");
  const params = await searchParams;
  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(params.pagina) ?? "1", 10) - 1 || 0, 1000),
  );
  const [{ rows, total }, menus] = await Promise.all([getImportJobs(page), getMenus()]);
  const pages = Math.max(1, Math.ceil(total / IMPORT_JOBS_PAGE));

  return (
    <>
      <Link
        href="/recetas"
        className="inline-flex min-h-touch items-center gap-1 self-start text-base text-primary underline-offset-4 hover:underline desk:min-h-control"
      >
        <ArrowLeft aria-hidden="true" className="size-4" />
        Volver a recetas
      </Link>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="tabular-nums">
            {total === 1 ? "1 importación" : `${total.toLocaleString("es-AR")} importaciones`}
          </CardTitle>
        </div>
        {rows.length === 0 ? (
          <EmptyState
            title={total > 0 ? "Esa página no existe." : "Todavía no se importó ningún recetario."}
          >
            {total > 0 ? (
              <Link
                href="/recetas/importar"
                className="text-primary underline-offset-4 hover:underline"
              >
                Ir a la primera página
              </Link>
            ) : menus.importsRun ? (
              "Subí el primero con «Importar recetario»."
            ) : (
              "Los suben los chefs y los directores de marca."
            )}
          </EmptyState>
        ) : (
          <ul aria-label="Importaciones" className="flex flex-col divide-y divide-line">
            {rows.map((j) => (
              <li
                key={j.id}
                className="flex flex-col gap-1 py-3 sm:flex-row sm:items-center sm:gap-4"
              >
                <div className="flex min-w-0 flex-1 flex-col gap-1">
                  <Link
                    href={`/recetas/importar/${j.id}`}
                    className="inline-flex min-h-touch items-center text-base font-medium break-all text-primary underline-offset-4 hover:underline"
                  >
                    {j.fileName}
                  </Link>
                  <span className="text-sm text-ink-muted tabular-nums">
                    {j.brandName} · prefijo {j.prefix} · {formatDateTime(j.createdAt)}
                  </span>
                </div>
                <Badge status={JOB_STATUS_BADGE[j.status]}>{JOB_STATUS_LABELS[j.status]}</Badge>
              </li>
            ))}
          </ul>
        )}
        {pages > 1 ? (
          <nav aria-label="Páginas" className="flex flex-wrap items-center gap-2">
            {page > 0 ? (
              <Button asChild variant="outline">
                <Link href={`/recetas/importar?pagina=${page}`}>Anterior</Link>
              </Button>
            ) : null}
            <span className="text-sm text-ink-muted tabular-nums">
              Página {page + 1} de {pages}
            </span>
            {page + 1 < pages ? (
              <Button asChild variant="outline">
                <Link href={`/recetas/importar?pagina=${page + 2}`}>Siguiente</Link>
              </Button>
            ) : null}
          </nav>
        ) : null}
      </Card>
    </>
  );
}
