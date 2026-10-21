import { Suspense } from "react";

import { decideAction } from "@/app/usuarios/actions";
import { DecisionForm } from "@/app/aprobaciones/decision-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import { formatDateTime, getInbox, type InboxRow } from "@/lib/data";
import { requireOperable } from "@/lib/auth/session";

const STATUS: Record<InboxRow["status"], { label: string; status: BadgeStatus }> = {
  pending: { label: "Pendiente", status: "warn" },
  approved: { label: "Aprobada", status: "ok" },
  rejected: { label: "Rechazada", status: "bad" },
  cancelled: { label: "Retirada", status: "neutral" },
};

export default function AprobacionesPage() {
  return (
    <AppShell
      title="¿Qué espera una decisión?"
      description="Los cambios que necesitan que otra persona los apruebe (ADR-0008)."
    >
      <Suspense fallback={<Loading />}>
        <Inbox />
      </Suspense>
    </AppShell>
  );
}

async function Inbox() {
  await requireOperable();
  const rows = await getInbox();
  if (rows.length === 0) return <EmptyState title="No hay solicitudes para mostrar." />;

  return (
    <ul className="flex flex-col gap-4">
      {rows.map((r) => (
        <li key={r.id}>
          <Card className="flex flex-col gap-2">
            <div className="flex flex-wrap items-center gap-2">
              <CardTitle>{r.summary ?? r.workflow_name}</CardTitle>
              <Badge status={STATUS[r.status].status}>{STATUS[r.status].label}</Badge>
            </div>
            <CardDescription>
              Pidió {r.requested_by_name ?? "alguien"} el {formatDateTime(r.requested_at)}
              {r.place_name ? ` · ${r.place_name}` : ""}
            </CardDescription>
            <p className="text-base text-ink">Motivo: {r.reason}</p>
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
