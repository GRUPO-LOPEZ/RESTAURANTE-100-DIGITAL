import * as React from "react";
import Link from "next/link";
import { Suspense, cache } from "react";
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
import { FormSelect, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import {
  ACTION_LABELS,
  scopeLabel,
  TABLE_LABELS,
  UUID,
  first,
  formatDateTime,
  getPlaces,
  getRoles,
  getUser,
  getUserDetail,
  personName,
} from "@/lib/data";
import { requireOperable } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

// Ficha de una persona (sección 9; ficha por pestañas del rediseño, ADR-0036): roles y alcances, último acceso,
// actividad reciente e intentos rechazados, y lo que se puede hacer con su cuenta. Las acciones que no
// corresponden las rechaza la base (y quedan registradas); la pantalla no decide nada. La pestaña va en la
// dirección (?seccion=).
export default function UsuarioPage({ params, searchParams }: PageProps<"/usuarios/[id]">) {
  return (
    <AppShell
      title="Ficha de la persona"
      heading={
        <Suspense fallback="Ficha de la persona">
          <PersonHeading params={params} />
        </Suspense>
      }
      description="Sus roles, su actividad y lo que se puede hacer con su cuenta."
    >
      <Suspense fallback={<Loading />}>
        <Person params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// Una sola lectura por pedido: la usan el título y la ficha.
const userById = cache(getUser);

// El h1 de la ficha es el nombre de la persona (como en recetas y materias primas, ADR-0036).
async function PersonHeading({ params }: { params: PageProps<"/usuarios/[id]">["params"] }) {
  await requireOperable();
  const { id } = await params;
  if (!UUID.test(id)) return "Ficha de la persona";
  const user = await userById(id);
  return user ? personName(user) : "Ficha de la persona";
}

const EVENT_LABELS: Record<string, string> = {
  login_failed: "Ingreso fallido",
  operation_denied: "Operación rechazada",
  account_locked: "Bloqueo por intentos fallidos",
};

function Reason({ id, label }: { id: string; label: string }) {
  return (
    <FormTextarea
      id={id}
      name="reason"
      label={label}
      hint="Queda en el historial."
      required
      maxLength={500}
    />
  );
}

// Aviso de que la acción no es inmediata: queda pendiente de una aprobación (ADR-0017).
function ApprovalNote({ children }: { children: React.ReactNode }) {
  return (
    <p
      data-slot="approval-note"
      className="rounded-sm border border-line bg-info p-3 text-base text-info-ink"
    >
      {children}
    </p>
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

const SECTIONS = [
  { key: "datos", label: "Datos y cuenta" },
  { key: "roles", label: "Roles" },
  { key: "actividad", label: "Actividad" },
] as const;
type Section = (typeof SECTIONS)[number]["key"];

async function Person({
  params,
  searchParams,
}: {
  params: PageProps<"/usuarios/[id]">["params"];
  searchParams: PageProps<"/usuarios/[id]">["searchParams"];
}) {
  const session = await requireOperable();
  const [{ id }, query] = await Promise.all([params, searchParams]);
  if (!UUID.test(id)) notFound();
  const [user, detail, roles, places] = await Promise.all([
    userById(id),
    getUserDetail(id),
    getRoles(),
    getPlaces(),
  ]);
  if (!user || !detail) notFound();
  const isMe = user.id === session.user_id;
  // Lo que va con aprobación de Dirección (ADR-0017): lo dice la base, no se calcula acá.
  const gov = detail.governance;
  // La actividad solo para quien la puede ver (la base también lo controla).
  const tabs = SECTIONS.filter(
    (t) =>
      t.key !== "actividad" ||
      detail.can_view_activity ||
      (detail.can_view_security && detail.rejected_attempts),
  );
  const wanted = first(query.seccion);
  const section: Section = tabs.find((t) => t.key === wanted)?.key ?? "datos";
  const show = (key: Section) => section === key;
  // "← Volver" a la lista con sus filtros: solo la lista de personas de esta aplicación.
  const volver = first(query.volver);
  const back = volver && /^\/usuarios\/lista(\?|$)/.test(volver) ? volver : "/usuarios/lista";
  const tabHref = (key: Section) => {
    const q = new URLSearchParams();
    if (key !== "datos") q.set("seccion", key);
    if (back !== "/usuarios/lista") q.set("volver", back);
    return q.size ? `/usuarios/${user.id}?${q}` : `/usuarios/${user.id}`;
  };

  return (
    <>
      <BackLink href={back}>Volver a personas</BackLink>
      {/* Encabezado: siempre a la vista, en todas las pestañas. */}
      <Card className="flex flex-col gap-2">
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            {/* El nombre ya es el título de la pantalla: acá van el estado y el correo. */}
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
      </Card>

      <Tabs
        label="Secciones de la persona"
        items={tabs.map((t) => ({ href: tabHref(t.key), label: t.label, current: show(t.key) }))}
      />

      {show("datos") ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Datos</CardTitle>
          <dl className="flex flex-col gap-1">
            <Row label="Puesto" value={detail.job_title} />
            <Row label="Área" value={detail.area_name} />
            {detail.can_view_admin_details ? (
              <>
                <Row
                  label="Último acceso"
                  value={
                    detail.last_seen_at ? formatDateTime(detail.last_seen_at) : "Todavía no entró"
                  }
                />
                <Row
                  label="Primer ingreso"
                  value={detail.activated_at ? formatDateTime(detail.activated_at) : null}
                />
                <Row label="La invitó" value={detail.invited_by_name} />
              </>
            ) : null}
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
          {detail.can_view_admin_details ? null : (
            <p className="text-sm text-ink-muted">
              El último acceso, el primer ingreso, quién la invitó y quién la suspendió o le dio de
              baja, con el motivo, los ve quien administra a la persona.
            </p>
          )}
        </Card>
      ) : null}

      {show("actividad") && detail.can_view_activity ? (
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Actividad reciente</CardTitle>
            <CardDescription>
              Los últimos cambios que hizo, dentro de lo que podés ver del historial.
            </CardDescription>
          </div>
          <Link
            href={`/historial?persona=${user.id}`}
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

      {show("actividad") && detail.can_view_security && detail.rejected_attempts ? (
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

      {show("roles") ? (
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
                  <span className="text-ink-muted">· {scopeLabel(r.scope_type, r.scope_name)}</span>
                </p>
                <Action summary={`Quitar ${r.role_name}…`}>
                  <ActionForm
                    action={revokeRoleAction}
                    schema="reason"
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
      ) : null}

      {show("roles") && !isMe ? (
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Dar un rol</CardTitle>
            <CardDescription>
              Si el rol aprueba cosas o administra la seguridad, queda pendiente hasta que otra
              persona lo apruebe.
            </CardDescription>
          </div>
          <ActionForm
            action={assignRoleAction}
            schema="assignRole"
            submitLabel="Dar el rol"
            pendingLabel="Guardando…"
          >
            <input type="hidden" name="userId" value={user.id} />
            <FormSelect id="rol" name="role" label="Rol" defaultValue="">
              <option value="" disabled>
                Elegí un rol
              </option>
              {roles.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.name}
                </option>
              ))}
            </FormSelect>
            <FormSelect id="lugar" name="place" label="Dónde" defaultValue="">
              <option value="" disabled>
                Elegí el lugar
              </option>
              {places.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </FormSelect>
            <Reason id="motivo-dar" label="Motivo para dar el rol" />
          </ActionForm>
        </Card>
      ) : null}

      {show("datos") && !isMe ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Cuenta</CardTitle>
          {user.locked ? (
            <Action key="unlock" summary="Liberar el bloqueo…">
              <ActionForm
                action={unlockUserAction}
                schema="reason"
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
                schema="reason"
                submitLabel={gov.suspend ? "Pedir la suspensión" : "Suspender la cuenta"}
                variant="outline"
                pendingLabel={gov.suspend ? "Enviando…" : "Suspendiendo…"}
              >
                <input type="hidden" name="userId" value={user.id} />
                {gov.suspend ? (
                  <ApprovalNote>
                    Esta persona es Superadministrador. Pedís la suspensión y queda pendiente hasta
                    que la apruebe Dirección General. Cuando se aprueba, se cierran sus sesiones.
                  </ApprovalNote>
                ) : (
                  <p className="text-base text-ink">
                    Suspender es una pausa (por ejemplo, una licencia): cierra sus sesiones y no
                    puede entrar hasta que se levante. Se levanta sin aprobación.
                  </p>
                )}
                <Reason id="motivo-suspender" label="Motivo para suspender" />
              </ActionForm>
            </Action>
          ) : null}
          {user.status === "suspended" ? (
            <Action key="lift" summary="Levantar la suspensión…">
              <ActionForm
                action={liftSuspensionAction}
                schema="reason"
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
                schema="reason"
                submitLabel={gov.deactivate ? "Pedir la desactivación" : "Desactivar la cuenta"}
                variant="destructive"
                pendingLabel={gov.deactivate ? "Enviando…" : "Desactivando…"}
              >
                <input type="hidden" name="userId" value={user.id} />
                {gov.deactivate ? (
                  <ApprovalNote>
                    {gov.deactivate === "core.change_general_management_status"
                      ? "Esta persona es de Dirección General. Pedís la desactivación y queda pendiente hasta que la apruebe otra persona de Dirección General, que no seas vos."
                      : "Esta persona es Superadministrador. Pedís la desactivación y queda pendiente hasta que la apruebe Dirección General."}{" "}
                    Cuando se aprueba, se cierran sus sesiones y su historia se conserva.
                  </ApprovalNote>
                ) : (
                  <p className="text-base text-ink">
                    Desactivar es para quien deja de trabajar: cierra todas sus sesiones al instante
                    y toda su historia se conserva. Para reactivarla hace falta la aprobación de
                    otra persona.
                  </p>
                )}
                <Reason id="motivo-desactivar" label="Motivo para desactivar" />
              </ActionForm>
            </Action>
          ) : (
            <Action key="reactivate" summary="Pedir la reactivación…">
              <ActionForm
                action={requestReactivationAction}
                schema="reason"
                submitLabel="Pedir la reactivación"
                variant="outline"
                pendingLabel="Enviando…"
              >
                <input type="hidden" name="userId" value={user.id} />
                {gov.reactivate ? (
                  <ApprovalNote>
                    Esta persona es de Dirección General. La reactivación la aprueba otra persona de
                    Dirección General, que no seas vos ni quien la desactivó.
                  </ApprovalNote>
                ) : (
                  <p className="text-base text-ink">
                    La reactivación la aprueba otra persona, distinta de quien la desactivó.
                  </p>
                )}
                <Reason id="motivo-reactivar" label="Motivo para reactivar" />
              </ActionForm>
            </Action>
          )}
        </Card>
      ) : null}
    </>
  );
}
