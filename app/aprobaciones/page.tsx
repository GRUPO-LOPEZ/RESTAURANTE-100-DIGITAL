import Link from "next/link";
import { Suspense } from "react";

import { decideAction } from "@/app/usuarios/actions";
import { DecisionForm } from "@/app/aprobaciones/decision-form";
import { markNotificationsReadAction } from "@/app/shell-actions";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import {
  FIELD_LABELS,
  UUID,
  formatDateTime,
  formatField,
  getInbox,
  getRoles,
  getUnreadCount,
  type InboxRow,
} from "@/lib/data";
import { requireMenu } from "@/lib/auth/session";

const STATUS: Record<InboxRow["status"], { label: string; status: BadgeStatus }> = {
  pending: { label: "Pendiente", status: "warn" },
  approved: { label: "Aprobada", status: "ok" },
  rejected: { label: "Rechazada", status: "bad" },
  cancelled: { label: "Retirada", status: "neutral" },
};

// Bandeja de aprobaciones (sección 9): las pendientes con el antes y el después, aprobar o
// rechazar con motivo, y las resueltas recientemente.
export default function AprobacionesPage() {
  return (
    <AppShell
      title="¿Qué espera una decisión?"
      description="Los cambios que necesitan que otra persona los apruebe. Las pendientes van primero."
    >
      <Suspense fallback={<Loading />}>
        <Inbox />
      </Suspense>
    </AppShell>
  );
}

async function Inbox() {
  await requireMenu("approvals");
  // Las pendientes (hasta 100) y las últimas 20 resueltas.
  const [pending, resolved, roles, unread] = await Promise.all([
    getInbox(true, 100),
    getInbox(false, 20),
    getRoles(),
    getUnreadCount(),
  ]);
  const roleNames = Object.fromEntries(roles.map((r) => [r.code, r.name]));

  return (
    <>
      {unread > 0 ? (
        <Card className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-base text-ink">
            Tenés {unread} {unread === 1 ? "aviso nuevo" : "avisos nuevos"} de solicitudes que podés
            decidir.
          </p>
          <form action={markNotificationsReadAction}>
            <Button type="submit" variant="outline" className="w-full sm:w-auto">
              Marcar como leídos
            </Button>
          </form>
        </Card>
      ) : null}
      {pending.length === 0 && resolved.length === 0 ? (
        <EmptyState title="No hay solicitudes para mostrar." />
      ) : (
        <>
          <section aria-labelledby="pendientes" className="flex flex-col gap-4">
            <h2 id="pendientes" className="text-xl text-ink">
              Pendientes ({pending.length >= 100 ? "100 o más" : pending.length})
            </h2>
            {pending.length === 0 ? (
              <EmptyState title="No hay nada esperando una decisión." />
            ) : (
              <RequestList rows={pending} roleNames={roleNames} />
            )}
          </section>
          {resolved.length > 0 ? (
            <section aria-labelledby="resueltas" className="flex flex-col gap-4">
              <h2 id="resueltas" className="text-xl text-ink">
                Resueltas recientemente
              </h2>
              <RequestList rows={resolved} roleNames={roleNames} />
            </section>
          ) : null}
        </>
      )}
    </>
  );
}

// El antes y el después: los campos con nombre en español que están en lo que se pide.
function BeforeAfter({ row, roleNames }: { row: InboxRow; roleNames: Record<string, string> }) {
  const before = row.previous_values ?? {};
  const after = row.proposed_changes ?? {};
  const fields = Object.keys(before).filter((f) => FIELD_LABELS[f]);
  const added = Object.keys(after).filter((f) => FIELD_LABELS[f] && !(f in before));
  if (fields.length === 0 && added.length === 0) return null;
  return (
    <dl className="flex flex-col gap-1 rounded-sm border border-line p-3 text-sm">
      {fields.map((f) => (
        <div key={f} className="flex flex-col sm:flex-row sm:gap-2">
          <dt className="font-medium text-ink sm:w-40 sm:shrink-0">{FIELD_LABELS[f]}</dt>
          <dd className="break-words text-ink-muted">
            Antes: {formatField(f, before[f], roleNames)} → Después:{" "}
            {f in after ? formatField(f, after[f], roleNames) : "sin cambios"}
          </dd>
        </div>
      ))}
      {added.map((f) => (
        <div key={f} className="flex flex-col sm:flex-row sm:gap-2">
          <dt className="font-medium text-ink sm:w-40 sm:shrink-0">{FIELD_LABELS[f]}</dt>
          <dd className="break-words text-ink-muted">{formatField(f, after[f], roleNames)}</dd>
        </div>
      ))}
    </dl>
  );
}

// Una versión de receta se revisa en la receta: la solicitud lleva solo un resumen (ADR-0023).
function RecipeLink({ row }: { row: InboxRow }) {
  const recipeId = (row.proposed_changes as Record<string, unknown> | null)?.recipe_id;
  if (
    row.workflow_code !== "recipes.publish_version" ||
    typeof recipeId !== "string" ||
    !UUID.test(recipeId)
  )
    return null;
  return (
    <Link
      href={`/recetas/${recipeId}`}
      className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
    >
      Ver la receta y sus cambios
    </Link>
  );
}

function RequestList({ rows, roleNames }: { rows: InboxRow[]; roleNames: Record<string, string> }) {
  return (
    <ul className="flex flex-col gap-4">
      {rows.map((r) => (
        <li key={r.id}>
          <Card className="flex flex-col gap-2">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-xl text-ink">{r.summary ?? r.workflow_name}</h3>
              <Badge status={STATUS[r.status].status}>{STATUS[r.status].label}</Badge>
            </div>
            <CardDescription>
              Pidió {r.requested_by_name ?? "alguien"} el {formatDateTime(r.requested_at)}
              {r.place_name ? ` · ${r.place_name}` : ""}
            </CardDescription>
            <p className="text-base text-ink">Motivo: {r.reason}</p>
            <BeforeAfter row={r} roleNames={roleNames} />
            <RecipeLink row={r} />
            {r.resolved_at ? (
              <p className="text-sm text-ink-muted">
                Resolvió {r.resolved_by_name ?? "alguien"} el {formatDateTime(r.resolved_at)}
                {r.resolution_comment ? `: ${r.resolution_comment}` : ""}
              </p>
            ) : null}
            {r.can_decide ? (
              <DecisionForm action={decideAction} requestId={r.id} />
            ) : r.status === "pending" ? (
              <p className="text-sm text-ink-muted">
                La tiene que decidir otra persona con permiso.
              </p>
            ) : null}
          </Card>
        </li>
      ))}
    </ul>
  );
}
