import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import {
  ACTION_LABELS,
  FIELD_LABELS,
  MODULE_LABELS,
  TABLE_LABELS,
  formatDateTime,
  formatValue,
  type HistoryRow,
} from "@/lib/data";

// Historial en lenguaje simple: qué pasó, dónde, cuándo, quién y por qué, con los campos que
// cambiaron (antes → después). Lo usan el historial y los cambios críticos del tablero.
const VISIBLE = 5;

function Change({ row, field }: { row: HistoryRow; field: string }) {
  const before = row.old_values?.[field];
  const after = row.new_values?.[field];
  const isChange = ["update", "soft_delete", "restore", "publish"].includes(row.action);
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

function actionStatus(action: string) {
  if (action === "soft_delete" || action === "reject") return "bad" as const;
  if (action === "insert" || action === "approve" || action === "publish") return "ok" as const;
  return "info" as const;
}

export function HistoryList({ rows, compact = false }: { rows: HistoryRow[]; compact?: boolean }) {
  return (
    <ol className="flex flex-col gap-4">
      {rows.map((r) => (
        <li key={r.sequence_number}>
          <Card className="flex flex-col gap-2">
            <div className="flex flex-wrap items-center gap-2">
              <Badge status={actionStatus(r.action)}>{ACTION_LABELS[r.action] ?? "Cambio"}</Badge>
              <span className="text-base font-medium text-ink">
                {TABLE_LABELS[`${r.table_schema}.${r.table_name}`] ?? "Dato del sistema"}
              </span>
              {r.place_name ? (
                <span className="text-sm text-ink-muted">· {r.place_name}</span>
              ) : null}
              {r.module && MODULE_LABELS[r.module] ? (
                <span className="text-sm text-ink-muted">· {MODULE_LABELS[r.module]}</span>
              ) : null}
            </div>
            <p className="text-sm text-ink-muted">
              <time dateTime={r.occurred_at}>{formatDateTime(r.occurred_at)}</time> · {r.actor_name}
            </p>
            {r.reason ? <p className="text-base text-ink">Motivo: {r.reason}</p> : null}
            {compact ? null : <Changes row={r} />}
          </Card>
        </li>
      ))}
    </ol>
  );
}
