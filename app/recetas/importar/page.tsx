import Link from "next/link";
import { Suspense } from "react";
import { Upload } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { formatDateTime } from "@/lib/data";
import {
  JOB_STATUS_BADGE,
  JOB_STATUS_LABELS,
  getImportJobs,
  type ImportJobRow,
} from "@/lib/imports/jobs";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

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

const PATH = "/recetas/importar";

const COLUMNS: DataColumn<ImportJobRow>[] = [
  {
    key: "file",
    header: "Archivo",
    mobile: "title",
    cell: (j) => (
      <Link
        href={`/recetas/importar/${j.id}`}
        className="inline-flex min-h-touch items-center font-medium break-all text-primary underline-offset-4 hover:underline desk:min-h-0"
      >
        {j.fileName}
      </Link>
    ),
  },
  { key: "brand", header: "Marca", cell: (j) => j.brandName },
  {
    key: "prefix",
    header: "Prefijo",
    cell: (j) => <span className="tabular-nums">{j.prefix}</span>,
  },
  {
    key: "created",
    header: "Subida",
    cell: (j) => (
      <span className="whitespace-nowrap tabular-nums">{formatDateTime(j.createdAt)}</span>
    ),
  },
  {
    key: "status",
    header: "Estado",
    mobile: "status",
    cell: (j) => <Badge status={JOB_STATUS_BADGE[j.status]}>{JOB_STATUS_LABELS[j.status]}</Badge>,
  },
];

async function Jobs({
  searchParams,
}: {
  searchParams: PageProps<"/recetas/importar">["searchParams"];
}) {
  await requireMenu("imports");
  const raw = await searchParams;
  const params = plainParams(raw);
  // Página y filas por página como en todos los listados (15 de entrada; 10, 25 o 50).
  const list = parseList(raw, []);
  const [{ rows, total }, menus] = await Promise.all([
    getImportJobs(list.page - 1, list.size),
    getMenus(),
  ]);

  return (
    <>
      <BackLink href="/recetas">Volver a recetas</BackLink>
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 importación" : `${total.toLocaleString("es-AR")} importaciones`}
        </CardTitle>
        {rows.length === 0 && total > 0 ? (
          <EmptyState title="Esa página no existe.">
            <Link
              href={listHref(PATH, params, { pagina: undefined })}
              className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline"
            >
              Ir a la primera página
            </Link>
          </EmptyState>
        ) : (
          <DataTable
            caption="Importaciones"
            columns={COLUMNS}
            rows={rows}
            rowKey={(j) => j.id}
            empty={
              <EmptyState title="Todavía no se importó ningún recetario.">
                {menus.importsRun
                  ? "Subí el primero con «Importar recetario»."
                  : "Los suben los chefs y los directores de marca."}
              </EmptyState>
            }
          />
        )}
        {total > 0 ? (
          <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
        ) : null}
      </Card>
    </>
  );
}
