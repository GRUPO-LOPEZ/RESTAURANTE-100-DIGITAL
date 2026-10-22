import Link from "next/link";
import { Suspense } from "react";
import { Check, Clock } from "lucide-react";

import { requestMatrixChangeAction } from "@/app/roles/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select } from "@/components/ui/field";
import { FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { first, formatDateTime, getBrandsAndRestaurants, getPermissionMatrix } from "@/lib/data";
import { requireMenu } from "@/lib/auth/session";

// Roles y permisos (sección 9): la matriz rol por permiso. Cada cambio pide motivo, queda en el
// historial y espera la aprobación de Dirección General (ADR-0008).
export default function RolesPage({ searchParams }: PageProps<"/roles">) {
  return (
    <AppShell
      title="¿Qué puede hacer cada rol?"
      description="La matriz de permisos. Cada cambio necesita un motivo y la aprobación de Dirección General."
    >
      <Suspense fallback={<Loading />}>
        <Matrix searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const MODULE_NAMES: Record<string, string> = {
  org: "Estructura",
  users: "Personas",
  roles: "Roles",
  permissions: "Matriz de permisos",
  audit: "Historial",
  security: "Registro de seguridad",
  approvals: "Aprobaciones",
  workflows: "Tipos de aprobación",
  test_documents: "Documentos de ensayo",
};

async function Matrix({ searchParams }: { searchParams: PageProps<"/roles">["searchParams"] }) {
  await requireMenu("roles");
  const params = await searchParams;
  const { groups } = await getBrandsAndRestaurants();
  const group = groups[0];
  if (!group) return <EmptyState title="No hay un grupo en tu alcance." />;
  const matrix = await getPermissionMatrix(group.id);
  if (!matrix) return <EmptyState title="No podés ver la matriz de este grupo." />;

  const roleParam = first(params.rol);
  const role = matrix.roles.find((r) => r.code === roleParam) ?? matrix.roles[0];
  if (!role) return <EmptyState title="No hay roles." />;
  const has = new Set(matrix.grants.map((g) => `${g.role_code}|${g.permission_code}`));
  const pending = new Map<string, (typeof matrix.pending)[number]>(
    matrix.pending.map((p) => [`${p.role_code}|${p.permission_code}`, p]),
  );
  const modules = [...new Set(matrix.permissions.map((p) => p.module))];

  return (
    <>
      <Card>
        <form method="get" className="flex flex-col gap-4 sm:flex-row sm:items-end">
          <Field id="rol" label="Rol" className="sm:w-80">
            <Select name="rol" defaultValue={role.code}>
              {matrix.roles.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.name}
                </option>
              ))}
            </Select>
          </Field>
          <button
            type="submit"
            className="min-h-touch rounded-sm border border-line bg-surface px-4 text-base font-medium text-ink hover:bg-line/50"
          >
            Ver sus permisos
          </button>
        </form>
      </Card>

      <section aria-labelledby="permisos-del-rol" className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          <h2 id="permisos-del-rol" className="text-xl text-ink">
            {role.name}
          </h2>
          {role.requires_mfa ? <Badge status="info">Usa doble verificación</Badge> : null}
          {role.is_mine ? (
            <Badge status="neutral">Es un rol tuyo: no lo podés cambiar</Badge>
          ) : null}
        </div>
        {modules.map((module) => (
          <Card key={module} className="flex flex-col gap-2">
            <CardTitle>{MODULE_NAMES[module] ?? module}</CardTitle>
            <ul className="flex flex-col">
              {matrix.permissions
                .filter((p) => p.module === module)
                .map((p) => {
                  const key = `${role.code}|${p.code}`;
                  const granted = has.has(key);
                  const waiting = pending.get(key);
                  return (
                    <li
                      key={p.code}
                      className="flex flex-col gap-2 border-b border-line py-3 last:border-0"
                    >
                      <div className="flex flex-wrap items-center gap-2">
                        {granted ? (
                          <Badge status="ok">
                            <Check aria-hidden="true" />
                            Lo tiene
                          </Badge>
                        ) : (
                          <Badge status="neutral">No lo tiene</Badge>
                        )}
                        <span className="text-base text-ink">{p.description}</span>
                        {p.is_sensitive ? <Badge status="warn">Sensible</Badge> : null}
                      </div>
                      <span className="text-sm text-ink-muted">{p.code}</span>
                      {waiting ? (
                        <p className="flex items-center gap-2 text-sm text-ink">
                          <Clock aria-hidden="true" className="size-4" />
                          Pedido de {waiting.grant ? "dar" : "quitar"} pendiente ·{" "}
                          {waiting.requested_by_name} · {formatDateTime(waiting.requested_at)}
                        </p>
                      ) : matrix.can_manage && !role.is_mine ? (
                        <details>
                          <summary className="flex min-h-touch cursor-pointer items-center text-base text-primary underline-offset-4 hover:underline">
                            {granted ? "Pedir que se lo quiten" : "Pedir que se lo den"}
                          </summary>
                          <ActionForm
                            action={requestMatrixChangeAction}
                            schema="reason"
                            submitLabel={granted ? "Pedir quitarlo" : "Pedir darlo"}
                            pendingLabel="Enviando…"
                            variant="outline"
                          >
                            <input type="hidden" name="groupId" value={group.id} />
                            <input type="hidden" name="role" value={role.code} />
                            <input type="hidden" name="permission" value={p.code} />
                            <input type="hidden" name="grant" value={granted ? "false" : "true"} />
                            <FormTextarea
                              id={`motivo-${p.code}`}
                              label="Motivo"
                              hint="Queda en el historial y lo ve quien aprueba."
                              name="reason"
                              required
                              maxLength={500}
                            />
                          </ActionForm>
                        </details>
                      ) : null}
                    </li>
                  );
                })}
            </ul>
          </Card>
        ))}
      </section>

      {/* La matriz completa, para mirar de un vistazo en una pantalla grande. */}
      <Card className="hidden flex-col gap-4 lg:flex">
        <div className="flex flex-col gap-1">
          <CardTitle>Matriz completa</CardTitle>
          <CardDescription>
            Cada fila es un permiso; cada columna, un rol. Para cambiar algo, elegí el rol arriba.
          </CardDescription>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-left text-sm">
            <caption className="sr-only">Permisos de cada rol</caption>
            <thead>
              <tr className="border-b border-line">
                <th scope="col" className="py-2 pr-2 font-medium text-ink-muted">
                  Permiso
                </th>
                {matrix.roles.map((r) => (
                  <th key={r.code} scope="col" className="px-1 py-2 font-medium text-ink-muted">
                    <Link
                      href={`/roles?rol=${r.code}`}
                      className="text-primary underline-offset-4 hover:underline"
                    >
                      {r.name}
                    </Link>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {matrix.permissions.map((p) => (
                <tr key={p.code} className="border-b border-line last:border-0">
                  <th scope="row" className="py-1 pr-2 font-normal text-ink">
                    {p.description}
                  </th>
                  {matrix.roles.map((r) => (
                    <td key={r.code} className="px-1 py-1 text-center text-ink">
                      {has.has(`${r.code}|${p.code}`) ? (
                        <>
                          <Check aria-hidden="true" className="mx-auto size-4" />
                          <span className="sr-only">Sí</span>
                        </>
                      ) : (
                        <span className="sr-only">No</span>
                      )}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  );
}
