import * as React from "react";
import Link from "next/link";
import { Suspense, cache } from "react";
import { notFound, redirect } from "next/navigation";

import {
  closeSessionsAction,
  disableUserAction,
  liftSuspensionAction,
  requestReactivationAction,
  suspendUserAction,
  unlockUserAction,
} from "@/app/usuarios/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { FocusHeading } from "@/components/focus-heading";
import { FocusTarget } from "@/components/focus-target";
import {
  ProfileFields,
  ReadRow,
  RolesSection,
  SheetBar,
  UserSheetProvider,
} from "@/components/user-sheet/sheet-editor";
import { Badge } from "@/components/ui/badge";
import { FormTextarea } from "@/components/ui/form";
import { InfoTip } from "@/components/ui/info-tip";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { ShortList } from "@/components/ui/short-list";
import { Tile } from "@/components/ui/tile";
import { requireOperable } from "@/lib/auth/session";
import {
  ACTION_LABELS,
  TABLE_LABELS,
  UUID,
  first,
  own,
  formatDate,
  formatDateTime,
  getPlaces,
  getRoles,
  getUser,
  getUserDetail,
  getUserSheetState,
  personName,
  type UserDetail,
  type UserRow,
} from "@/lib/data";
import { rolePlaces, type UserDraft } from "@/lib/user-sheet";

// Ficha de una persona en una pantalla (Tanda 1 de Soy, ADR-0062), con el patrón de las pantallas de carga sin scroll
// (ADR-0046): una línea de encabezado con lo que se hace con su cuenta, 4 indicadores y tres columnas de tarjetas. Los
// datos y los roles se guardan juntos con la barra de abajo, con motivo. Qué puede hacer cada sesión lo dice la base
// (core.user_sheet_state) y lo vuelve a controlar; lo que rechaza queda registrado. En el celular, de consulta, salvo
// lo urgente: suspender, desactivar, liberar el bloqueo y cerrar sesiones.
type Params = PageProps<"/usuarios/[id]">["params"];
type Search = PageProps<"/usuarios/[id]">["searchParams"];

export default function UsuarioPage({ params, searchParams }: PageProps<"/usuarios/[id]">) {
  return (
    <AppShell
      title="Persona"
      fill
      heading={
        <Suspense fallback="Persona">
          <PersonHeading params={params} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back searchParams={searchParams} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <AccountActions params={params} searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Person params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// Una sola lectura por pedido: la usan el título, el encabezado y la ficha.
const userById = cache(getUser);
const detailById = cache(getUserDetail);
const stateById = cache(getUserSheetState);

async function personId(params: Params): Promise<string | null> {
  await requireOperable();
  const { id } = await params;
  return UUID.test(id) ? id : null;
}

async function PersonHeading({ params }: { params: Params }) {
  const id = await personId(params);
  const user = id ? await userById(id) : null;
  return user ? personName(user) : "Persona";
}

// «← Volver» a la lista con sus filtros: solo la lista de personas de esta aplicación.
function backHref(volver: string | undefined): string {
  return volver && /^\/usuarios\/lista(\?|$)/.test(volver) ? volver : "/usuarios/lista";
}

async function Back({ searchParams }: { searchParams: Search }) {
  const query = await searchParams;
  return (
    <BackLink href={backHref(first(query.volver))} label="Volver a personas">
      Personas
    </BackLink>
  );
}

function AccountBadge({ user }: { user: UserRow }) {
  if (user.status === "deactivated") return <Badge status="bad">Desactivada</Badge>;
  if (user.status === "suspended") return <Badge status="warn">Suspendida</Badge>;
  if (user.locked) return <Badge status="warn">Bloqueada unos minutos</Badge>;
  return <Badge status="ok">Activa</Badge>;
}

async function Meta({ params }: { params: Params }) {
  const id = await personId(params);
  const user = id ? await userById(id) : null;
  if (!user) return null;
  return (
    <>
      <span className="min-w-0 text-sm break-all text-ink-muted">
        {[user.email, user.job_title].filter(Boolean).join(" · ")}
      </span>
      <AccountBadge user={user} />
    </>
  );
}

// ---------------------------------------------------------------------------
// Lo que se hace con la cuenta: arriba a la derecha, con su motivo, en el momento
// ---------------------------------------------------------------------------
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

async function AccountActions({ params, searchParams }: { params: Params; searchParams: Search }) {
  const id = await personId(params);
  if (!id) return null;
  const volver = backHref(first((await searchParams).volver));
  const [user, detail, state] = await Promise.all([userById(id), detailById(id), stateById(id)]);
  if (!user || !detail || !state || state.is_me) return null;
  const gov = detail.governance;
  return (
    <div className="flex flex-wrap items-center gap-2">
      {user.locked && state.can_unlock ? (
        <ActionModal
          label="Liberar el bloqueo"
          icon="none"
          title="Liberar el bloqueo"
          description="Está bloqueada unos minutos por intentos fallidos. Podés liberarla antes."
        >
          <ActionForm
            action={unlockUserAction}
            schema="reason"
            submitLabel="Liberar el bloqueo"
            pendingLabel="Liberando…"
          >
            <input type="hidden" name="userId" value={user.id} />
            <input type="hidden" name="volver" value={volver} />
            <Reason id="motivo-liberar" label="Motivo para liberar el bloqueo" />
          </ActionForm>
        </ActionModal>
      ) : null}
      {user.status === "active" && state.can_suspend ? (
        <ActionModal label="Suspender" icon="none" title="Suspender la cuenta">
          <ActionForm
            action={suspendUserAction}
            schema="reason"
            submitLabel={gov.suspend ? "Pedir la suspensión" : "Suspender la cuenta"}
            pendingLabel={gov.suspend ? "Enviando…" : "Suspendiendo…"}
          >
            <input type="hidden" name="userId" value={user.id} />
            <input type="hidden" name="volver" value={volver} />
            {gov.suspend ? (
              <ApprovalNote>
                Esta persona es Superadministrador. Pedís la suspensión y queda pendiente hasta que
                la apruebe Dirección General. Cuando se aprueba, se cierran sus sesiones.
              </ApprovalNote>
            ) : (
              <p className="text-base text-ink">
                Suspender es una pausa (por ejemplo, una licencia): cierra sus sesiones y no puede
                entrar hasta que se levante. Se levanta sin aprobación.
              </p>
            )}
            <Reason id="motivo-suspender" label="Motivo para suspender" />
          </ActionForm>
        </ActionModal>
      ) : null}
      {user.status === "suspended" && state.can_suspend ? (
        <ActionModal
          label="Levantar la suspensión"
          icon="none"
          title="Levantar la suspensión"
          description="Al levantarla, vuelve a poder entrar."
        >
          <ActionForm
            action={liftSuspensionAction}
            schema="reason"
            submitLabel="Levantar la suspensión"
            pendingLabel="Levantando…"
          >
            <input type="hidden" name="userId" value={user.id} />
            <input type="hidden" name="volver" value={volver} />
            <Reason id="motivo-levantar" label="Motivo para levantar la suspensión" />
          </ActionForm>
        </ActionModal>
      ) : null}
      {user.status !== "deactivated" && state.can_deactivate ? (
        <ActionModal label="Desactivar" icon="none" title="Desactivar la cuenta">
          <ActionForm
            action={disableUserAction}
            schema="reason"
            submitLabel={gov.deactivate ? "Pedir la desactivación" : "Desactivar la cuenta"}
            variant="destructive"
            pendingLabel={gov.deactivate ? "Enviando…" : "Desactivando…"}
          >
            <input type="hidden" name="userId" value={user.id} />
            <input type="hidden" name="volver" value={volver} />
            {gov.deactivate ? (
              <ApprovalNote>
                {gov.deactivate === "core.change_general_management_status"
                  ? "Esta persona es de Dirección General. Pedís la desactivación y queda pendiente hasta que la apruebe otra persona de Dirección General, que no seas vos."
                  : "Esta persona es Superadministrador. Pedís la desactivación y queda pendiente hasta que la apruebe Dirección General."}{" "}
                Cuando se aprueba, se cierran sus sesiones y su historia se conserva.
              </ApprovalNote>
            ) : (
              <p className="text-base text-ink">
                Desactivar es para quien deja de trabajar: cierra todas sus sesiones al instante y
                toda su historia se conserva. Para reactivarla hace falta la aprobación de otra
                persona.
              </p>
            )}
            <Reason id="motivo-desactivar" label="Motivo para desactivar" />
          </ActionForm>
        </ActionModal>
      ) : null}
      {user.status === "deactivated" && state.can_reactivate ? (
        <ActionModal label="Pedir la reactivación" icon="none" title="Pedir la reactivación">
          <ActionForm
            action={requestReactivationAction}
            schema="reason"
            submitLabel="Pedir la reactivación"
            pendingLabel="Enviando…"
          >
            <input type="hidden" name="userId" value={user.id} />
            <input type="hidden" name="volver" value={volver} />
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
        </ActionModal>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// La ficha
// ---------------------------------------------------------------------------
const EVENT_LABELS: Record<string, string> = {
  login_failed: "Ingreso fallido",
  operation_denied: "Operación rechazada",
  account_locked: "Bloqueo por intentos fallidos",
};

const NOTICES: Record<string, { status: "ok" | "info"; text: string }> = {
  guardado: { status: "ok", text: "Cambios guardados." },
  suspendida: { status: "ok", text: "Cuenta suspendida. Se cerraron todas sus sesiones." },
  levantada: { status: "ok", text: "Suspensión levantada: ya puede entrar." },
  desactivada: { status: "ok", text: "Cuenta desactivada. Se cerraron todas sus sesiones." },
  liberada: { status: "ok", text: "Bloqueo liberado." },
  sesiones: { status: "ok", text: "Se cerraron todas sus sesiones. Puede volver a entrar." },
  pendiente: {
    status: "info",
    text: "El cambio de rol queda pendiente hasta que otra persona lo apruebe (se ve en Aprobaciones).",
  },
};

const SECTIONS: Record<string, string> = { datos: "datos", roles: "roles", actividad: "actividad" };
const PLACE_PREFIX = { group: "Todo el grupo", brand: "Marca", restaurant: "Local" } as const;

// La base cuenta hasta 1.000: más que eso se muestra «+1.000».
function capped(n: number | null): number | string | null {
  return n !== null && n > 1000 ? "+1.000" : n;
}

function joined(...parts: (string | null | undefined)[]): string | null {
  return parts.filter(Boolean).join(" · ") || null;
}

const smallLink =
  "inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8";

function ActivityRow({
  a,
  full = false,
}: {
  a: UserDetail["recent_activity"][number];
  // En el panel, el motivo entero.
  full?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between gap-2 text-sm">
      <span className="min-w-0">
        <span className="font-medium text-ink">
          {ACTION_LABELS[a.action] ?? "Cambio"} · {TABLE_LABELS[a.table_name] ?? "Dato del sistema"}
        </span>
        {a.place_name || a.reason ? (
          <span className={`block text-xs text-ink-muted ${full ? "break-words" : "truncate"}`}>
            {joined(a.place_name, a.reason)}
          </span>
        ) : null}
      </span>
      <time
        dateTime={a.occurred_at}
        className="shrink-0 text-xs text-ink-muted tabular-nums"
        title={formatDateTime(a.occurred_at)}
      >
        {formatDate(a.occurred_at)}
      </time>
    </div>
  );
}

async function Person({ params, searchParams }: { params: Params; searchParams: Search }) {
  const id = await personId(params);
  if (!id) notFound();
  const query = await searchParams;
  const volver = backHref(first(query.volver));
  // Los enlaces de antes (?seccion=roles) llevan a su tarjeta (FocusTarget).
  const old = own(SECTIONS, first(query.seccion));
  if (old) {
    const q = volver === "/usuarios/lista" ? "" : `?${new URLSearchParams({ volver })}`;
    redirect(`/usuarios/${id}${q}#${old}`);
  }
  const [user, detail, state, roles, places] = await Promise.all([
    userById(id),
    detailById(id),
    stateById(id),
    getRoles(),
    getPlaces(),
  ]);
  if (!user || !detail || !state) notFound();
  // Las áreas que esta sesión le puede poner, y la que ya tiene (aunque no esté en uso) hasta que se la cambien.
  const areas = state.areas;
  const areaOptions =
    detail.area_id && !areas.some((a) => a.id === detail.area_id)
      ? [...areas, { id: detail.area_id, label: `${detail.area_name ?? "Su área de hoy"}` }]
      : areas;
  const initial: UserDraft = {
    fields: {
      first_name: user.first_name ?? "",
      last_name: user.last_name ?? "",
      job_title: detail.job_title ?? "",
      area_id: detail.area_id ?? "",
    },
    roles: user.roles.map((r) => ({
      key: r.assignment_id,
      assignmentId: r.assignment_id,
      roleCode: r.role_code,
      roleName: r.role_name,
      place: "",
      placeLabel: `${PLACE_PREFIX[r.scope_type]} · ${r.scope_name ?? ""}`,
      removed: false,
    })),
  };
  const editable =
    state.can_edit_job || state.can_edit_profile || state.can_assign || state.revocable.length > 0;
  const saved = own(NOTICES, first(query.aviso)) ?? null;
  const needsMfa = user.roles.some(
    (r) => roles.find((x) => x.code === r.role_code)?.requires_mfa === true,
  );
  // El mismo corte que cuenta la base: 30 días atrás, desde la medianoche de la Argentina.
  const now = new Date();
  const from = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Buenos_Aires",
  }).format(new Date(now.getTime() - 30 * 86_400_000));
  const weekAgo = new Date(now.getTime() - 7 * 86_400_000).toISOString();
  const adminOnly = "Lo ve quien administra a la persona.";
  // Los del indicador: los últimos 7 días (la base manda hasta 20).
  const rejected = (detail.rejected_attempts ?? []).filter(
    (a) => new Date(a.occurred_at).toISOString() >= weekAgo,
  );
  // Varios cambios de un mismo guardado tienen la misma fecha: la clave es su lugar en la lista.
  const recent = detail.recent_activity.map((a, i) => ({ ...a, key: `${a.occurred_at}-${i}` }));

  return (
    <>
      {saved ? (
        <Notice status={saved.status} className={editable ? "desk:hidden" : undefined}>
          {saved.text}
        </Notice>
      ) : null}
      <UserSheetProvider
        userId={user.id}
        stamp={state.stamp}
        editable={editable}
        initial={initial}
        options={{
          areas: areaOptions,
          roles: roles.map((r) => ({ code: r.code, name: r.name })),
          places,
          canEditProfile: state.can_edit_profile,
          canEditJob: state.can_edit_job,
          canAssign: state.can_assign,
          revocable: state.revocable,
        }}
        notice={saved}
      >
        <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
          <Metric
            compact
            label="Último ingreso"
            value={
              detail.can_view_admin_details
                ? detail.last_seen_at
                  ? formatDate(detail.last_seen_at)
                  : null
                : null
            }
            period={
              detail.can_view_admin_details && detail.last_seen_at
                ? formatDateTime(detail.last_seen_at).split(", ").slice(1).join(", ")
                : undefined
            }
            missingReason={detail.can_view_admin_details ? "Todavía no entró." : adminOnly}
            emptyLabel="Sin ingresos"
            status={state.mfa ? "ok" : needsMfa ? "warn" : "none"}
            statusLabel={
              state.mfa
                ? "Con doble verificación"
                : needsMfa
                  ? "Falta la doble verificación"
                  : "Sin doble verificación"
            }
          />
          <Metric
            compact
            label="Roles"
            value={user.roles.length}
            emptyLabel="Sin roles"
            status={user.roles.length > 0 ? "info" : "none"}
            statusLabel={rolePlaces(user.roles)}
          />
          <Metric
            compact
            label="Cambios en 30 días"
            value={capped(state.changes_30d)}
            missingReason="Los ven quienes ven el historial."
            emptyLabel="Sin cambios"
            status={state.changes_30d ? "info" : "none"}
            statusLabel={state.changes_30d ? "En lo que podés ver" : "Sin cambios"}
            action={
              state.changes_30d ? (
                <Link
                  href={`/historial?persona=${user.id}&desde=${from}&local=todos`}
                  className={smallLink}
                >
                  Ver historial
                </Link>
              ) : undefined
            }
          />
          <Metric
            compact
            label="Accesos rechazados en 7 días"
            value={capped(state.rejected_7d)}
            missingReason="Los ven quienes ven el registro de seguridad."
            emptyLabel="Sin intentos"
            status={state.rejected_7d ? "warn" : "ok"}
            statusLabel={state.rejected_7d ? "Revisar" : "Sin intentos"}
            action={
              detail.can_view_security && rejected.length > 0 ? (
                <ActionModal
                  label={
                    rejected.length < (state.rejected_7d ?? 0)
                      ? `Ver los ${rejected.length} últimos`
                      : "Ver cuáles"
                  }
                  variant="link"
                  icon="none"
                  size="sm"
                  title="Intentos rechazados"
                  description="De los últimos 7 días: ingresos fallidos y bloqueos de su cuenta, y operaciones que intentó y la base no dejó hacer."
                >
                  <ul className="flex flex-col gap-2">
                    {rejected.map((a, i) => (
                      <li
                        key={`${a.occurred_at}-${i}`}
                        className="border-b border-line pb-2 text-sm last:border-0"
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
                </ActionModal>
              ) : undefined
            }
          />
        </div>

        <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-3 desk:grid-rows-[minmax(0,1fr)]">
          <Tile id="datos" title="Datos" scroll>
            <ProfileFields />
            <dl className="flex flex-col gap-1">
              <ReadRow label="Correo" value={<span className="break-all">{user.email}</span>} />
              <ReadRow
                label="Trabaja en"
                value={detail.workplaces
                  .map((w) => w.restaurant_name ?? w.brand_name ?? `Todo ${w.group_name}`)
                  .join(", ")}
              />
              {detail.can_view_admin_details ? (
                <>
                  <ReadRow label="La invitó" value={detail.invited_by_name} />
                  <ReadRow
                    label="Primer ingreso"
                    value={detail.activated_at ? formatDateTime(detail.activated_at) : null}
                  />
                </>
              ) : null}
            </dl>
            <h3 className="pt-1 text-base font-semibold text-ink">Cuenta</h3>
            <dl className="flex flex-col gap-1">
              {state.mfa !== null ? (
                <ReadRow
                  label="Verificación"
                  value={
                    <Badge status={state.mfa ? "ok" : needsMfa ? "warn" : "none"}>
                      {state.mfa
                        ? "Doble, activada"
                        : needsMfa
                          ? "Falta la doble"
                          : "Sin doble (opcional)"}
                    </Badge>
                  }
                />
              ) : null}
              {detail.status === "suspended" ? (
                <ReadRow
                  label="Suspendida"
                  value={joined(
                    detail.suspended_at ? formatDateTime(detail.suspended_at) : null,
                    detail.suspended_by_name,
                    detail.suspension_reason,
                  )}
                />
              ) : null}
              {detail.status === "deactivated" ? (
                <ReadRow
                  label="Desactivada"
                  value={joined(
                    detail.deactivated_at ? formatDateTime(detail.deactivated_at) : null,
                    detail.deactivated_by_name,
                    detail.deactivation_reason,
                  )}
                />
              ) : null}
              {state.sessions !== null ? (
                <ReadRow
                  label="Sesiones"
                  value={
                    <span className="flex flex-wrap items-center gap-x-3">
                      {state.sessions === 1 ? "1 abierta" : `${state.sessions} abiertas`}
                      {state.sessions > 0 && state.can_close_sessions ? (
                        <ActionModal
                          label="Cerrar todas"
                          variant="link"
                          icon="none"
                          size="sm"
                          title="Cerrar todas las sesiones"
                          description="Sale de todos sus dispositivos. No se suspende: puede volver a entrar con su contraseña."
                        >
                          <ActionForm
                            action={closeSessionsAction}
                            schema="reason"
                            submitLabel="Cerrar todas las sesiones"
                            pendingLabel="Cerrando…"
                          >
                            <input type="hidden" name="userId" value={user.id} />
                            <input type="hidden" name="volver" value={volver} />
                            <Reason id="motivo-sesiones" label="Motivo para cerrar las sesiones" />
                          </ActionForm>
                        </ActionModal>
                      ) : null}
                    </span>
                  }
                />
              ) : null}
            </dl>
            {detail.can_view_admin_details ? null : (
              <p className="text-xs text-ink-muted">
                El último acceso, quién la invitó, sus sesiones y los motivos los ve quien
                administra a la persona.
              </p>
            )}
            {state.is_me ? (
              <p className="text-xs text-ink-muted">
                Tus datos, tu contraseña y tus sesiones se cambian en{" "}
                <Link href="/mi-cuenta" className="text-primary underline underline-offset-4">
                  Mi cuenta
                </Link>
                .
              </p>
            ) : null}
          </Tile>
          <Tile
            id="roles"
            title="Roles y dónde los usa"
            scroll
            titleExtra={
              <InfoTip label="los roles">
                Qué puede hacer cada rol se ve en Roles y permisos. Un rol que aprueba cosas o
                administra la seguridad queda pendiente hasta que otra persona lo apruebe.
              </InfoTip>
            }
          >
            <RolesSection />
          </Tile>
          <Tile id="actividad" title="Lo último que hizo" scroll>
            {!detail.can_view_activity ? (
              <p className="text-sm text-ink-muted">La ven quienes ven el historial.</p>
            ) : (
              <>
                <ShortList
                  label="Lo último que hizo"
                  items={recent}
                  limit={5}
                  itemKey={(a) => a.key}
                  renderItem={(a) => <ActivityRow a={a} />}
                  empty="No hizo cambios que puedas ver."
                  more={
                    recent.length > 0 ? (
                      <ActionModal
                        label={
                          detail.recent_activity.length === 1
                            ? "Ver el último cambio"
                            : `Ver los ${detail.recent_activity.length} últimos`
                        }
                        variant="link"
                        icon="none"
                        size="sm"
                        title="Lo último que hizo"
                        description="Dentro de lo que podés ver del historial."
                      >
                        <ul className="flex flex-col gap-2">
                          {detail.recent_activity.map((a, i) => (
                            <li
                              key={`${a.occurred_at}-${i}`}
                              className="border-b border-line pb-2 last:border-0"
                            >
                              <ActivityRow a={a} full />
                            </li>
                          ))}
                        </ul>
                      </ActionModal>
                    ) : undefined
                  }
                />
                <Link href={`/historial?persona=${user.id}`} className={smallLink}>
                  Ver todo lo que hizo en el historial
                </Link>
              </>
            )}
          </Tile>
        </div>

        <SheetBar />
      </UserSheetProvider>
      <FocusTarget />
      <FocusHeading when={saved ? first(query.aviso) : undefined} />
    </>
  );
}
