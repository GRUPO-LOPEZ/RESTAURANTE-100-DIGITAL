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
  formatDate,
  formatDateTime,
  formatField,
  getInbox,
  getRecipeNotices,
  getRoles,
  getUnreadCount,
  type InboxRow,
  type NoticeRow,
} from "@/lib/data";
import { formatMoney } from "@/lib/prices";
import { requireMenu } from "@/lib/auth/session";

const STATUS: Record<InboxRow["status"], { label: string; status: BadgeStatus }> = {
  pending: { label: "Pendiente", status: "warn" },
  approved: { label: "Aprobada", status: "ok" },
  rejected: { label: "Rechazada", status: "bad" },
  cancelled: { label: "Retirada", status: "neutral" },
};

// Bandeja de aprobaciones (sección 9): las pendientes con el antes y el después, aprobar o
// rechazar con motivo, y las resueltas recientemente. Arriba, los avisos de cambios de recetas
// (una preparación que cambió y que usan platos de la persona; ADR-0026).
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
  const [pending, resolved, roles, unread, notices] = await Promise.all([
    getInbox(true, 100),
    getInbox(false, 20),
    getRoles(),
    getUnreadCount(),
    getRecipeNotices(),
  ]);
  const roleNames = Object.fromEntries(roles.map((r) => [r.code, r.name]));
  // Los precios que, aprobados por el Controller, pasaron a Dirección General (ADR-0029).
  const toDirection = new Set(
    [...pending, ...resolved]
      .filter((r) => r.workflow_code === "costing.approve_price_direction")
      .map((r) => (r.proposed_changes as Record<string, unknown> | null)?.first_request_id)
      .filter((id): id is string => typeof id === "string"),
  );

  return (
    <>
      {unread > 0 ? (
        <Card className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-base text-ink">
            Tenés {unread} {unread === 1 ? "aviso nuevo" : "avisos nuevos"}.
          </p>
          <form action={markNotificationsReadAction}>
            <Button type="submit" variant="outline" className="w-full sm:w-auto">
              Marcar como leídos
            </Button>
          </form>
        </Card>
      ) : null}
      {notices.length > 0 ? <Notices rows={notices} /> : null}
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
              <RequestList rows={pending} roleNames={roleNames} toDirection={toDirection} />
            )}
          </section>
          {resolved.length > 0 ? (
            <section aria-labelledby="resueltas" className="flex flex-col gap-4">
              <h2 id="resueltas" className="text-xl text-ink">
                Resueltas recientemente
              </h2>
              <RequestList rows={resolved} roleNames={roleNames} toDirection={toDirection} />
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

const NOTICE_LABELS: Record<NoticeRow["kind"], { badge: string; link: string }> = {
  recipe_changed: { badge: "Cambió una preparación", link: "Ver la receta" },
  recipe_cost_changed: { badge: "Cambió un costo", link: "Ver el costo" },
  yield_deviation: { badge: "Rendimiento desviado", link: "Ver la materia prima" },
};

// Avisos de cambios de recetas: qué cambió y el enlace a la receta. Se marcan como leídos con el
// botón de arriba, junto con los de solicitudes.
function Notices({ rows }: { rows: NoticeRow[] }) {
  return (
    <section aria-labelledby="apr-avisos" className="flex flex-col gap-4">
      <h2 id="apr-avisos" className="text-xl text-ink">
        Avisos de recetas, costos y rendimientos ({rows.length >= 20 ? "20 o más" : rows.length})
      </h2>
      <ul className="flex flex-col gap-4">
        {rows.map((n) => (
          <li key={n.id}>
            <Card className="flex flex-col gap-2">
              <div className="flex flex-wrap items-center gap-2">
                <h3 className="text-base font-semibold text-ink">{n.title}</h3>
                <Badge status={n.kind === "yield_deviation" ? "warn" : "info"}>
                  {NOTICE_LABELS[n.kind].badge}
                </Badge>
              </div>
              <CardDescription>{formatDateTime(n.createdAt)}</CardDescription>
              {n.body ? <p className="text-base text-ink">{n.body}</p> : null}
              {n.link ? (
                <Link
                  href={n.link}
                  className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
                >
                  {NOTICE_LABELS[n.kind].link}
                  <span className="sr-only"> ({n.title})</span>
                </Link>
              ) : null}
            </Card>
          </li>
        ))}
      </ul>
    </section>
  );
}

// Un precio de compra (ADR-0029): qué producto, cuánto y cuánto cambia. Los importes llegan "[oculto]"
// desde la base a quien no ve precios en ese lugar (workflow.can_see_amounts), y se muestran así.
function PriceSummary({ row, toDirection }: { row: InboxRow; toDirection: boolean }) {
  const c = (row.proposed_changes ?? {}) as Record<string, unknown>;
  const money = (v: unknown) =>
    v === "[oculto]" ? "[oculto]" : typeof v === "number" ? formatMoney(v) : "—";
  const pct = (v: unknown) =>
    v === "[oculto]"
      ? "[oculto]"
      : typeof v === "number"
        ? `${v > 0 ? "+" : ""}${v.toLocaleString("es-AR")} %`
        : "sin precio anterior";
  const lookback = typeof c.lookback_days === "number" ? c.lookback_days : null;
  const today = c.price_variation_today_pct ?? c.price_variation_pct;
  return (
    <>
      <dl className="flex flex-col gap-1 rounded-sm border border-line p-3 text-sm">
        <div className="flex flex-col sm:flex-row sm:gap-2">
          <dt className="font-medium text-ink sm:w-48 sm:shrink-0">Materia prima</dt>
          <dd className="text-ink-muted">
            {[c.ingredient, c.product].filter((x) => typeof x === "string" && x).join(" · ") || "—"}
          </dd>
        </div>
        <div className="flex flex-col sm:flex-row sm:gap-2">
          <dt className="font-medium text-ink sm:w-48 sm:shrink-0">Precio del envase</dt>
          <dd className="text-ink-muted tabular-nums">
            {money(c.package_price)} · sin IVA {money(c.net_package_price)} · con IVA{" "}
            {money(c.gross_package_price)}
          </dd>
        </div>
        <div className="flex flex-col sm:flex-row sm:gap-2">
          <dt className="font-medium text-ink sm:w-48 sm:shrink-0">Vale desde</dt>
          <dd className="text-ink-muted tabular-nums">
            {typeof c.valid_from === "string" ? formatDate(c.valid_from) : "—"}
          </dd>
        </div>
        <div className="flex flex-col sm:flex-row sm:gap-2">
          <dt className="font-medium text-ink sm:w-48 sm:shrink-0">Variación</dt>
          <dd className="text-ink-muted tabular-nums">
            {today === null || today === undefined
              ? "Es el primer precio: no hay contra qué comparar"
              : `${pct(today)} contra el costo de hoy`}
            {c.price_variation_lookback_pct !== null &&
            c.price_variation_lookback_pct !== undefined &&
            lookback !== null
              ? ` · ${pct(c.price_variation_lookback_pct)} contra el de hace ${lookback} días`
              : ""}
          </dd>
        </div>
      </dl>
      {row.workflow_code === "costing.approve_price_direction" ? (
        <p className="text-base text-ink">
          Ya la aprobó el Controller. Como la variación supera el % del grupo, la decide Dirección
          General.
        </p>
      ) : toDirection ? (
        <p className="text-base text-ink">
          Como la variación supera el % del grupo, ahora la decide Dirección General.
        </p>
      ) : null}
    </>
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

function RequestList({
  rows,
  roleNames,
  toDirection,
}: {
  rows: InboxRow[];
  roleNames: Record<string, string>;
  toDirection: Set<string>;
}) {
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
            {r.workflow_code.startsWith("costing.") ? (
              <PriceSummary row={r} toDirection={toDirection.has(r.id)} />
            ) : (
              <BeforeAfter row={r} roleNames={roleNames} />
            )}
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
