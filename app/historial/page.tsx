import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import {
  ACTION_LABELS,
  FIELD_LABELS,
  TABLE_LABELS,
  formatDateTime,
  formatValue,
  getHistory,
  type HistoryRow,
} from "@/lib/data";
import { requireMenu } from "@/lib/auth/session";

// Historial inalterable (ADR-0006): quién, cuándo, qué cambió y por qué, en lenguaje simple.
// Solo lo de tu alcance, y sin costos si no tenés permiso para verlos.
export default function HistorialPage({ searchParams }: PageProps<"/historial">) {
  return (
    <AppShell
      title="¿Quién cambió qué?"
      description="Cada cambio queda registrado para siempre: nadie lo puede borrar ni modificar."
    >
      <Suspense fallback={<Loading />}>
        <History searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const VISIBLE = 5;

function Change({ row, field }: { row: HistoryRow; field: string }) {
  const before = row.old_values?.[field];
  const after = row.new_values?.[field];
  const isChange =
    row.action === "update" || row.action === "soft_delete" || row.action === "restore";
  return (
    <div className="flex flex-col sm:flex-row sm:gap-2">
      <dt className="font-medium text-ink sm:w-48 sm:shrink-0">{FIELD_LABELS[field]}</dt>
      <dd className="break-words text-ink-muted">
        {isChange ? `${formatValue(before)} → ${formatValue(after)}` : formatValue(after ?? before)}
      </dd>
    </div>
  );
}

function Changes({ row }: { row: HistoryRow }) {
  // Solo los campos con nombre en español: ids y datos técnicos no se muestran.
  const fields = (row.changed_fields ?? Object.keys(row.new_values ?? row.old_values ?? {})).filter(
    (f) => FIELD_LABELS[f],
  );
  if (fields.length === 0) return null;
  const first = fields.slice(0, VISIBLE);
  const rest = fields.slice(VISIBLE);
  return (
    <>
      <dl className="flex flex-col gap-1 text-sm">
        {first.map((f) => (
          <Change key={f} row={row} field={f} />
        ))}
      </dl>
      {rest.length > 0 ? (
        <details className="text-sm">
          <summary className="flex min-h-touch cursor-pointer items-center text-primary underline-offset-4 hover:underline">
            Ver todo ({rest.length} más)
          </summary>
          <dl className="flex flex-col gap-1">
            {rest.map((f) => (
              <Change key={f} row={row} field={f} />
            ))}
          </dl>
        </details>
      ) : null}
    </>
  );
}

async function History({
  searchParams,
}: {
  searchParams: PageProps<"/historial">["searchParams"];
}) {
  await requireMenu("audit");
  const params = await searchParams;
  const beforeRaw = Array.isArray(params.antes) ? params.antes[0] : params.antes;
  const before = beforeRaw && /^[0-9]{1,18}$/.test(beforeRaw) ? Number(beforeRaw) : undefined;
  const rows = await getHistory(before);
  if (rows.length === 0) return <EmptyState title="No hay cambios para mostrar en tu alcance." />;
  const last = rows[rows.length - 1];

  return (
    <>
      <ol className="flex flex-col gap-4">
        {rows.map((r) => (
          <li key={r.sequence_number}>
            <Card className="flex flex-col gap-2">
              <div className="flex flex-wrap items-center gap-2">
                <Badge
                  status={
                    r.action === "soft_delete" ? "bad" : r.action === "insert" ? "ok" : "info"
                  }
                >
                  {ACTION_LABELS[r.action] ?? "Cambio"}
                </Badge>
                <span className="text-base font-medium text-ink">
                  {TABLE_LABELS[`${r.schema_name}.${r.table_name}`] ?? "Dato del sistema"}
                </span>
                {r.place_name ? (
                  <span className="text-sm text-ink-muted">· {r.place_name}</span>
                ) : null}
              </div>
              <p className="text-sm text-ink-muted">
                <time dateTime={r.occurred_at}>{formatDateTime(r.occurred_at)}</time> ·{" "}
                {r.actor_name}
              </p>
              {r.reason ? <p className="text-base text-ink">Motivo: {r.reason}</p> : null}
              <Changes row={r} />
            </Card>
          </li>
        ))}
      </ol>
      {rows.length === 50 && last ? (
        <Button asChild variant="outline" className="self-start">
          <Link href={`/historial?antes=${last.sequence_number}`}>Ver cambios más antiguos</Link>
        </Button>
      ) : null}
    </>
  );
}
