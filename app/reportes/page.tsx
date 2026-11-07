import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import { requireMenu } from "@/lib/auth/session";
import { pickCostPlace } from "@/lib/costs";
import { first, formatDateTime, getActiveRestaurantId } from "@/lib/data";
import { REPORTS, reportDefinition } from "@/lib/report-labels";
import { getReportExports, getReportList, getReportPlaces } from "@/lib/reports";

// Reportes (ADR-0034): sacar la información del sistema en PDF, Excel o CSV.
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

async function ReportList({ placeId }: { placeId: string }) {
  const allowed = new Set(await getReportList(placeId));
  const reports = REPORTS.filter((r) => allowed.has(r.key));
  if (reports.length === 0) return <EmptyState title="No tenés reportes en este local." />;
  return (
    <nav aria-label="Reportes" className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {reports.map((r) => (
        <Link
          key={r.key}
          href={`/reportes/${r.key}?local=${placeId}`}
          className="flex min-h-touch flex-col gap-2 rounded-lg border border-line bg-surface p-4 hover:border-primary"
        >
          <span className="text-xl font-semibold text-ink">{r.title}</span>
          <span className="text-sm text-ink-muted">{r.text}</span>
        </Link>
      ))}
    </nav>
  );
}

const FORMATS: Record<string, string> = { pdf: "PDF", xlsx: "Excel", csv: "CSV" };

// Lo que salió del sistema: solo aparece para quien ve el registro de seguridad.
async function Exports() {
  const exports = await getReportExports();
  if (exports.length === 0) return null;
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>Últimas exportaciones</CardTitle>
        <CardDescription>Quién sacó qué reporte, de qué local y en qué formato.</CardDescription>
      </div>
      <ul className="flex flex-col divide-y divide-line" aria-label="Últimas exportaciones">
        {exports.map((e, i) => (
          <li key={i} className="flex flex-col gap-1 py-2 text-sm text-ink">
            <span className="[overflow-wrap:anywhere]">
              {e.person}: {reportDefinition(e.report)?.title ?? e.report} en{" "}
              {FORMATS[e.format] ?? e.format}
              {e.rows === null ? "" : `, ${e.rows} filas`}
            </span>
            <span className="text-ink-muted">
              {e.place} · {formatDateTime(e.at)}
            </span>
          </li>
        ))}
      </ul>
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
      {places.length > 1 ? (
        <FiltersPanel active={place ? [place.name] : []}>
          <form
            method="get"
            role="search"
            aria-label="Elegir local"
            className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
          >
            <Field id="reportes-local" label="Local">
              <Select key={place?.id ?? "ninguno"} name="local" defaultValue={place?.id ?? ""}>
                {place ? null : <option value="">Elegí un local</option>}
                {places.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Button type="submit">Ver</Button>
          </form>
        </FiltersPanel>
      ) : (
        <p className="text-sm text-ink-muted">{place?.name}</p>
      )}
      {place ? (
        <Suspense key={place.id} fallback={<Loading />}>
          <ReportList placeId={place.id} />
        </Suspense>
      ) : (
        <EmptyState title="Elegí un local para ver sus reportes." />
      )}
      <Suspense fallback={null}>
        <Exports />
      </Suspense>
    </>
  );
}
