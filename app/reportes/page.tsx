import Link from "next/link";
import { Suspense } from "react";
import { FileText } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { PlacePrompt } from "@/components/place-prompt";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/states";
import { requireMenu } from "@/lib/auth/session";
import { pickCostPlace } from "@/lib/costs";
import { first, formatDateTime, getActiveRestaurantId } from "@/lib/data";
import { REPORTS, reportDefinition } from "@/lib/report-labels";
import { getReportExports, getReportList, getReportPlaces, type ReportExport } from "@/lib/reports";

// Reportes (ADR-0034; rediseño, ADR-0036): sacar la información del sistema en PDF, Excel o CSV. El local es
// el de la barra de arriba (selector único y global); con «Todos mis locales», se pide uno.
export default function ReportesPage({ searchParams }: PageProps<"/reportes">) {
  return (
    <AppShell
      title="¿Qué reporte necesitás?"
      description="Cada reporte sale en PDF, Excel o CSV, con la fecha de los datos y el local."
    >
      <Suspense fallback={<Loading />}>
        <Reports searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function ReportList({ placeId, placeName }: { placeId: string; placeName: string }) {
  const allowed = new Set(await getReportList(placeId));
  const reports = REPORTS.filter((r) => allowed.has(r.key));
  if (reports.length === 0) return <EmptyState title="No tenés reportes en este local." />;
  return (
    <section aria-labelledby="reportes-local" className="flex flex-col gap-3">
      <h2 id="reportes-local" className="text-sm font-medium text-ink-muted">
        Reportes de {placeName}
      </h2>
      <nav aria-label="Reportes" className="grid gap-4 sm:grid-cols-2 desk:grid-cols-3">
        {reports.map((r) => (
          <Link
            key={r.key}
            href={`/reportes/${r.key}?local=${placeId}`}
            className="flex min-h-touch gap-3 rounded-md border border-line bg-surface p-4 hover:border-primary"
          >
            <FileText aria-hidden="true" className="mt-0.5 size-5 shrink-0 text-primary" />
            <span className="flex flex-col gap-1">
              <span className="text-base font-semibold text-ink">{r.title}</span>
              <span className="text-sm text-ink-muted">{r.text}</span>
            </span>
          </Link>
        ))}
      </nav>
    </section>
  );
}

const FORMATS: Record<string, string> = { pdf: "PDF", xlsx: "Excel", csv: "CSV" };

const EXPORT_COLUMNS: DataColumn<ReportExport>[] = [
  {
    key: "report",
    header: "Reporte",
    mobile: "title",
    cell: (e) => (
      <span className="[overflow-wrap:anywhere]">
        {reportDefinition(e.report)?.title ?? e.report}
      </span>
    ),
  },
  { key: "person", header: "Quién", cell: (e) => e.person },
  { key: "place", header: "Local", cell: (e) => e.place },
  { key: "format", header: "Formato", cell: (e) => FORMATS[e.format] ?? e.format },
  {
    key: "rows",
    header: "Filas",
    align: "right",
    cell: (e) => (e.rows === null ? "—" : e.rows.toLocaleString("es-AR")),
  },
  {
    key: "at",
    header: "Cuándo",
    align: "right",
    cell: (e) => <span className="tabular-nums">{formatDateTime(e.at)}</span>,
  },
];

// Lo que salió del sistema: solo aparece para quien ve el registro de seguridad (la base lo filtra).
async function Exports() {
  const exports = await getReportExports();
  if (exports.length === 0) return null;
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>Últimas exportaciones</CardTitle>
        <CardDescription>Quién sacó qué reporte, de qué local y en qué formato.</CardDescription>
      </div>
      <DataTable
        caption="Últimas exportaciones"
        columns={EXPORT_COLUMNS}
        rows={exports}
        rowKey={(e) => `${e.at}-${e.person}-${e.report}-${e.format}`}
      />
    </Card>
  );
}

async function Reports({ searchParams }: { searchParams: PageProps<"/reportes">["searchParams"] }) {
  const session = await requireMenu("reports");
  const params = await searchParams;
  const [places, activeId] = await Promise.all([
    getReportPlaces(),
    getActiveRestaurantId(session.user_id),
  ]);
  if (places.length === 0) return <EmptyState title="No tenés locales para sacar reportes." />;
  const place = pickCostPlace(places, first(params.local), activeId);

  return (
    <>
      {place ? (
        <Suspense key={place.id} fallback={<Loading />}>
          <ReportList placeId={place.id} placeName={place.name} />
        </Suspense>
      ) : (
        <PlacePrompt
          title="Elegí un local para ver sus reportes."
          places={places}
          path="/reportes"
        />
      )}
      <Suspense fallback={null}>
        <Exports />
      </Suspense>
    </>
  );
}
