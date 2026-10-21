import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import {
  ACTION_LABELS,
  TABLE_LABELS,
  formatDateTime,
  getHistory,
  type HistoryRow,
} from "@/lib/data";
import { requireOperable } from "@/lib/auth/session";

// Historial inalterable (ADR-0006): quién, cuándo, qué (antes y después) y por qué.
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

const CONTROL = new Set(["updated_at", "updated_by", "created_at", "created_by", "deleted_by"]);

function show(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

function Changes({ row }: { row: HistoryRow }) {
  const fields = (row.changed_fields ?? Object.keys(row.new_values ?? row.old_values ?? {})).filter(
    (f) => !CONTROL.has(f),
  );
  if (fields.length === 0) return null;
  return (
    <dl className="grid gap-1 text-sm sm:grid-cols-[minmax(0,12rem)_1fr]">
      {fields.slice(0, 12).map((f) => (
        <div key={f} className="contents">
          <dt className="font-medium text-ink">{f}</dt>
          <dd className="break-all text-ink-muted">
            {row.action === "update" || row.action === "soft_delete" || row.action === "restore"
              ? `${show(row.old_values?.[f])} → ${show(row.new_values?.[f])}`
              : show((row.new_values ?? row.old_values)?.[f])}
          </dd>
        </div>
      ))}
    </dl>
  );
}

async function History({
  searchParams,
}: {
  searchParams: PageProps<"/historial">["searchParams"];
}) {
  await requireOperable();
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
                  {ACTION_LABELS[r.action] ?? r.action}
                </Badge>
                <span className="text-base font-medium text-ink">
                  {TABLE_LABELS[`${r.schema_name}.${r.table_name}`] ?? r.table_name}
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
