import Link from "next/link";
import { Suspense } from "react";
import { notFound } from "next/navigation";

import {
  assignRoleAction,
  disableUserAction,
  requestReactivationAction,
  revokeRoleAction,
  unlockUserAction,
} from "@/app/usuarios/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select, Textarea } from "@/components/ui/field";
import { SCOPE_LABELS, getPlaces, getRoles, getUser, personName } from "@/lib/data";
import { requireOperable } from "@/lib/auth/session";

// Ficha de una persona: sus roles y lo que se puede hacer con su cuenta. Las acciones que
// no corresponden las rechaza la base (y quedan registradas); la pantalla no decide nada.
export default function UsuarioPage({ params }: PageProps<"/usuarios/[id]">) {
  return (
    <AppShell
      title="Ficha de la persona"
      description="Sus roles y lo que se puede hacer con su cuenta."
    >
      <Suspense fallback={<Loading />}>
        <Person params={params} />
      </Suspense>
    </AppShell>
  );
}

function Reason({ id, label }: { id: string; label: string }) {
  return (
    <Field id={id} label={label} hint="Queda en el historial.">
      <Textarea name="reason" required maxLength={500} />
    </Field>
  );
}

async function Person({ params }: { params: PageProps<"/usuarios/[id]">["params"] }) {
  const session = await requireOperable();
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const [user, roles, places] = await Promise.all([getUser(id), getRoles(), getPlaces()]);
  if (!user) notFound();
  const isMe = user.id === session.user_id;

  return (
    <>
      <Link
        href="/usuarios"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a usuarios
      </Link>
      <Card className="flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <CardTitle>{personName(user)}</CardTitle>
          {user.status === "disabled" ? (
            <Badge status="bad">Desactivada</Badge>
          ) : user.locked ? (
            <Badge status="warn">Bloqueada unos minutos</Badge>
          ) : (
            <Badge status="ok">Activa</Badge>
          )}
        </div>
        <CardDescription className="break-all">{user.email}</CardDescription>
      </Card>

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
          ) : null}
          {user.status === "active" ? (
            <ActionForm
              action={disableUserAction}
              submitLabel="Desactivar la cuenta"
              variant="destructive"
              pendingLabel="Desactivando…"
            >
              <input type="hidden" name="userId" value={user.id} />
              <p className="text-base text-ink">
                Desactivar cierra todas sus sesiones al instante. Toda su historia se conserva. Para
                reactivarla hace falta la aprobación de otra persona.
              </p>
              <Reason id="motivo-desactivar" label="Motivo para desactivar" />
            </ActionForm>
          ) : (
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
          )}
        </Card>
      ) : null}
    </>
  );
}
