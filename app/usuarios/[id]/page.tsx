import * as React from "react";
import Link from "next/link";
import { Suspense } from "react";
import { notFound } from "next/navigation";

import {
  assignRoleAction,
  disableUserAction,
  liftSuspensionAction,
  requestReactivationAction,
  revokeRoleAction,
  suspendUserAction,
  unlockUserAction,
} from "@/app/usuarios/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select, Textarea } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import {
  ACTION_LABELS,
  SCOPE_LABELS,
  TABLE_LABELS,
  UUID,
  formatDateTime,
  getPlaces,
  getRoles,
  getUser,
  getUserDetail,
  personName,
} from "@/lib/data";
import { requireOperable } from "@/lib/auth/session";

// Ficha de una persona (sección 9): roles y alcances, último acceso, actividad reciente e intentos
// rechazados, y lo que se puede hacer con su cuenta. Las acciones que no corresponden las rechaza
// la base (y quedan registradas); la pantalla no decide nada.
export default function UsuarioPage({ params }: PageProps<"/usuarios/[id]">) {
  return (
    <AppShell
      title="Ficha de la persona"
      description="Sus roles, su actividad y lo que se puede hacer con su cuenta."
    >
      <Suspense fallback={<Loading />}>
        <Person params={params} />
      </Suspense>
    </AppShell>
  );
}

const EVENT_LABELS: Record<string, string> = {
  login_failed: "Ingreso fallido",
  operation_denied: "Operación rechazada",
  account_locked: "Bloqueo por intentos fallidos",
};

function Reason({ id, label }: { id: string; label: string }) {
  return (
    <Field id={id} label={label} hint="Queda en el historial.">
      <Textarea name="reason" required maxLength={500} />
    </Field>
  );
}

// Cada acción con motivo va plegada: así la ficha no muestra muchos formularios a la vez.
function Action({ summary, children }: { summary: string; children: React.ReactNode }) {
  return (
    <details className="rounded-sm border border-line">
      <summary className="flex min-h-touch cursor-pointer items-center px-3 text-base font-medium text-primary underline-offset-4 hover:underline">
        {summary}
      </summary>
      <div className="flex flex-col gap-4 p-3">{children}</div>
    </details>
  );
}

function joined(...parts: (string | null | undefined)[]): string | null {
  return parts.filter(Boolean).join(" · ") || null;
}

function Row({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col sm:flex-row sm:gap-2">
      <dt className="text-sm font-medium text-ink sm:w-40 sm:shrink-0">{label}</dt>
      <dd className="text-sm break-words text-ink-muted">{value ?? "—"}</dd>
    </div>
  );
}

async function Person({ params }: { params: PageProps<"/usuarios/[id]">["params"] }) {
  const session = await requireOperable();
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const [user, detail, roles, places] = await Promise.all([
    getUser(id),
    getUserDetail(id),
    getRoles(),
    getPlaces(),
  ]);
  if (!user || !detail) notFound();
  const isMe = user.id === session.user_id;

  return (
    <>
      <Link
        href="/usuarios/lista"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a la lista
      </Link>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle>{personName(user)}</CardTitle>
            {user.status === "deactivated" ? (
              <Badge status="bad">Desactivada</Badge>
            ) : user.status === "suspended" ? (
              <Badge status="warn">Suspendida</Badge>
            ) : user.locked ? (
              <Badge status="warn">Bloqueada unos minutos</Badge>
            ) : (
              <Badge status="ok">Activa</Badge>
            )}
          </div>
          <CardDescription className="break-all">{user.email}</CardDescription>
        </div>
        <dl className="flex flex-col gap-1">
          <Row label="Puesto" value={detail.job_title} />
          <Row label="Área" value={detail.area_name} />
          <Row
            label="Último acceso"
            value={detail.last_seen_at ? formatDateTime(detail.last_seen_at) : "Todavía no entró"}
          />
          <Row
            label="Primer ingreso"
            value={detail.activated_at ? formatDateTime(detail.activated_at) : null}
          />
          <Row label="La invitó" value={detail.invited_by_name} />
          <Row
            label="Trabaja en"
            value={
              detail.workplaces
                .map((w) => w.restaurant_name ?? w.brand_name ?? `Todo ${w.group_name}`)
                .join(", ") || null
            }
          />
          {detail.status === "suspended" ? (
            <Row
              label="Suspendida"
              value={joined(
                detail.suspended_at ? formatDateTime(detail.suspended_at) : null,
                detail.suspended_by_name,
                detail.suspension_reason,
              )}
            />
          ) : null}
          {detail.status === "deactivated" ? (
            <Row
              label="Desactivada"
              value={joined(
                detail.deactivated_at ? formatDateTime(detail.deactivated_at) : null,
                detail.deactivated_by_name,
                detail.deactivation_reason,
              )}
            />
          ) : null}
        </dl>
      </Card>

      {detail.can_view_activity ? (
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Actividad reciente</CardTitle>
            <CardDescription>
              Los últimos cambios que hizo, dentro de lo que podés ver del historial.
            </CardDescription>
          </div>
          <Link
            href={`/historial?persona=${user.id}&local=todos`}
            className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
          >
            Ver todo lo que hizo en el historial
          </Link>
          {detail.recent_activity.length === 0 ? (
            <EmptyState title="No hizo cambios que puedas ver." />
          ) : (
            <ul className="flex flex-col gap-2">
              {detail.recent_activity.map((a, i) => (
                <li
                  key={`${a.occurred_at}-${i}`}
                  className="border-b border-line pb-2 text-sm last:border-0 last:pb-0"
                >
                  <span className="font-medium text-ink">
                    {ACTION_LABELS[a.action] ?? "Cambio"} ·{" "}
                    {TABLE_LABELS[a.table_name] ?? "Dato del sistema"}
                  </span>{" "}
                  <span className="text-ink-muted">
                    · {formatDateTime(a.occurred_at)}
                    {a.place_name ? ` · ${a.place_name}` : ""}
                    {a.reason ? ` · ${a.reason}` : ""}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      ) : null}

      {detail.can_view_security && detail.rejected_attempts ? (
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Intentos rechazados</CardTitle>
            <CardDescription>
              Ingresos fallidos, bloqueos y operaciones que la base no dejó hacer (las que intentó
              ella o las que intentaron sobre su cuenta).
            </CardDescription>
          </div>
          {detail.rejected_attempts.length === 0 ? (
            <EmptyState title="No hay intentos rechazados." />
          ) : (
            <ul className="flex flex-col gap-2">
              {detail.rejected_attempts.map((a, i) => (
                <li
                  key={`${a.occurred_at}-${i}`}
                  className="border-b border-line pb-2 text-sm last:border-0 last:pb-0"
                >
                  <span className="font-medium text-ink">
                    {EVENT_LABELS[a.event_type] ?? "Rechazo"}
                  </span>{" "}
                  <span className="text-ink-muted">
                    · {formatDateTime(a.occurred_at)}
                    {a.reason ? ` · ${a.reason}` : ""}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      ) : null}

      <Card className="flex flex-col gap-4">
        <CardTitle>Roles</CardTitle>
        {user.roles.length === 0 ? (
          <p className="text-base text-ink-muted">No tiene roles vigentes.</p>
        ) : null}
        <ul className="flex flex-col gap-4">
          {user.roles.map((r) => (
            <li
              key={r.assignment_id}
              className="flex flex-col gap-2 border-b border-line pb-4 last:border-0 last:pb-0"
            >
              <p className="text-base text-ink">
                {r.role_name}{" "}
                <span className="text-ink-muted">
                  · {SCOPE_LABELS[r.scope_type]} {r.scope_name}
                </span>
              </p>
              <Action summary="Quitar…">
                <ActionForm
                  action={revokeRoleAction}
                  submitLabel="Quitar este rol"
                  variant="outline"
                  pendingLabel="Quitando…"
                >
                  <input type="hidden" name="assignmentId" value={r.assignment_id} />
                  <Reason
                    id={`motivo-quitar-${r.assignment_id}`}
                    label={`Motivo para quitar ${r.role_name}`}
                  />
                </ActionForm>
              </Action>
            </li>
          ))}
        </ul>
      </Card>

      {!isMe ? (
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Dar un rol</CardTitle>
            <CardDescription>
              Si el rol aprueba cosas o administra la seguridad, queda pendiente hasta que otra
              persona lo apruebe.
            </CardDescription>
          </div>
          <ActionForm action={assignRoleAction} submitLabel="Dar el rol" pendingLabel="Guardando…">
            <input type="hidden" name="userId" value={user.id} />
            <Field id="rol" label="Rol">
              <Select name="role" required defaultValue="">
                <option value="" disabled>
                  Elegí un rol
                </option>
                {roles.map((r) => (
                  <option key={r.code} value={r.code}>
                    {r.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="lugar" label="Dónde">
              <Select name="place" required defaultValue="">
                <option value="" disabled>
                  Elegí el lugar
                </option>
                {places.map((p) => (
                  <option key={p.value} value={p.value}>
                    {p.label}
                  </option>
                ))}
              </Select>
            </Field>
            <Reason id="motivo-dar" label="Motivo para dar el rol" />
          </ActionForm>
        </Card>
      ) : null}

      {!isMe ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Cuenta</CardTitle>
          {user.locked ? (
            <Action key="unlock" summary="Liberar el bloqueo…">
              <ActionForm
                action={unlockUserAction}
                submitLabel="Liberar el bloqueo"
                variant="outline"
                pendingLabel="Liberando…"
              >
                <input type="hidden" name="userId" value={user.id} />
                <p className="text-base text-ink">
                  Está bloqueada unos minutos por intentos fallidos. Podés liberarla antes.
                </p>
                <Reason id="motivo-liberar" label="Motivo para liberar el bloqueo" />
              </ActionForm>
            </Action>
          ) : null}
          {user.status === "active" ? (
            <Action key="suspend" summary="Suspender…">
              <ActionForm
                action={suspendUserAction}
                submitLabel="Suspender la cuenta"
                variant="outline"
                pendingLabel="Suspendiendo…"
              >
                <input type="hidden" name="userId" value={user.id} />
                <p className="text-base text-ink">
                  Suspender es una pausa (por ejemplo, una licencia): cierra sus sesiones y no puede
                  entrar hasta que se levante. Se levanta sin aprobación.
                </p>
                <Reason id="motivo-suspender" label="Motivo para suspender" />
              </ActionForm>
            </Action>
          ) : null}
          {user.status === "suspended" ? (
            <Action key="lift" summary="Levantar la suspensión…">
              <ActionForm
                action={liftSuspensionAction}
                submitLabel="Levantar la suspensión"
                variant="outline"
                pendingLabel="Levantando…"
              >
                <input type="hidden" name="userId" value={user.id} />
                <p className="text-base text-ink">Al levantarla, vuelve a poder entrar.</p>
                <Reason id="motivo-levantar" label="Motivo para levantar la suspensión" />
              </ActionForm>
            </Action>
          ) : null}
          {user.status !== "deactivated" ? (
            <Action key="deactivate" summary="Desactivar…">
              <ActionForm
                action={disableUserAction}
                submitLabel="Desactivar la cuenta"
                variant="destructive"
                pendingLabel="Desactivando…"
              >
                <input type="hidden" name="userId" value={user.id} />
                <p className="text-base text-ink">
                  Desactivar es para quien deja de trabajar: cierra todas sus sesiones al instante y
                  toda su historia se conserva. Para reactivarla hace falta la aprobación de otra
                  persona.
                </p>
                <Reason id="motivo-desactivar" label="Motivo para desactivar" />
              </ActionForm>
            </Action>
          ) : (
            <Action key="reactivate" summary="Pedir la reactivación…">
              <ActionForm
                action={requestReactivationAction}
                submitLabel="Pedir la reactivación"
                variant="outline"
                pendingLabel="Enviando…"
              >
                <input type="hidden" name="userId" value={user.id} />
                <p className="text-base text-ink">
                  La reactivación la aprueba otra persona, distinta de quien la desactivó.
                </p>
                <Reason id="motivo-reactivar" label="Motivo para reactivar" />
              </ActionForm>
            </Action>
          )}
        </Card>
      ) : null}
    </>
  );
}
