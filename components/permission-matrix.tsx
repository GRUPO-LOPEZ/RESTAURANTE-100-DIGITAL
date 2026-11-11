"use client";

import { useMemo, useRef, useState, useTransition } from "react";
import { Check, Clock, X } from "lucide-react";

import { saveMatrixAction } from "@/app/roles/actions";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import { Button } from "@/components/ui/button";
import { Confirm } from "@/components/ui/dialog";
import { Field, Input } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { Tooltip, TooltipProvider } from "@/components/ui/tooltip";
import type { ActionState } from "@/lib/auth/results";
import type { PermissionMatrix as Matrix } from "@/lib/data";
import {
  buildChanges,
  cellKey,
  cellValue,
  pendingLabel,
  sensitiveGrants,
  toggleCell,
} from "@/lib/permission-matrix";
import { cn } from "@/lib/utils";

// Matriz de permisos (ADR-0039, pedido de Soy): filas = permisos agrupados por módulo, columnas = roles.
// Edición directa: un clic cambia la celda en un borrador local, el contador suma los cambios y «Guardar
// cambios» manda el lote a la base, todo o nada. Las quitas y los permisos comunes se aplican al guardar; dar un
// permiso sensible queda pedido para Dirección General (la celda dice «Pendiente»). La base decide todo.
export function PermissionMatrix({ groupId, matrix }: { groupId: string; matrix: Matrix }) {
  const original = useMemo(
    () => new Set(matrix.grants.map((g) => cellKey(g.role_code, g.permission_code))),
    [matrix.grants],
  );
  const waiting = useMemo(
    () => new Set(matrix.pending.map((p) => cellKey(p.role_code, p.permission_code))),
    [matrix.pending],
  );
  const roleIds = useMemo(() => new Map(matrix.roles.map((r) => [r.code, r.id])), [matrix.roles]);
  const sensitive = useMemo(
    () => new Set(matrix.permissions.filter((p) => p.is_sensitive).map((p) => p.code)),
    [matrix.permissions],
  );
  const modules = useMemo(() => {
    const named = new Map(matrix.modules.map((m) => [m.code, m.name]));
    const order: string[] = [];
    for (const p of matrix.permissions) if (!order.includes(p.module)) order.push(p.module);
    return order.map((code) => ({
      code,
      name: named.get(code) ?? code,
      permissions: matrix.permissions.filter((p) => p.module === code),
    }));
  }, [matrix.modules, matrix.permissions]);

  const [draft, setDraft] = useState<Map<string, boolean>>(() => new Map());
  const [reason, setReason] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [confirming, setConfirming] = useState(false);
  const [saving, startSaving] = useTransition();
  const reasonRef = useRef<HTMLInputElement>(null);
  useUnsavedWarning(draft.size > 0);

  const editable = matrix.can_manage;
  const sensitiveCount = sensitiveGrants(draft, sensitive);

  function save() {
    setConfirming(false);
    startSaving(async () => {
      const result = await saveMatrixAction({
        group_id: groupId,
        changes: buildChanges(draft, roleIds),
        reason,
      });
      setState(result);
      if (result.status === "ok" || result.status === "info") {
        setDraft(new Map());
        setReason("");
      } else if (result.fieldErrors?.reason) {
        reasonRef.current?.focus();
      }
    });
  }

  function requestSave() {
    if (reason.trim() === "") {
      setState({ status: "bad", fieldErrors: { reason: "Escribí el motivo." } });
      reasonRef.current?.focus();
      return;
    }
    if (sensitiveCount > 0) setConfirming(true);
    else save();
  }

  return (
    <TooltipProvider>
      <div className="flex flex-col gap-4">
        <p className="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-ink-muted">
          <span className="flex items-center gap-1">
            <span className="flex size-5 items-center justify-center rounded-sm bg-ok text-ok-ink">
              <Check aria-hidden="true" className="size-4" />
            </span>
            Lo tiene
          </span>
          <span className="flex items-center gap-1">
            <span className="flex size-5 items-center justify-center rounded-sm bg-bad text-bad-ink">
              <X aria-hidden="true" className="size-4" />
            </span>
            No lo tiene
          </span>
          <span className="flex items-center gap-1">
            <span className="flex size-5 items-center justify-center rounded-sm bg-info text-info-ink">
              <Clock aria-hidden="true" className="size-4" />
            </span>
            Pendiente de aprobación
          </span>
          <span className="flex items-center gap-1">
            <span aria-hidden="true" className="size-2 rounded-full bg-warn-ink" />
            Permiso sensible: darlo lo aprueba Dirección General
          </span>
        </p>

        {editable ? (
          <a
            href="#matriz-guardar"
            className="sr-only focus:not-sr-only focus:self-start focus:rounded-sm focus:bg-surface focus:px-3 focus:py-2 focus:text-primary"
          >
            Ir a guardar los cambios
          </a>
        ) : null}

        {/* Alto limitado en la computadora para que el encabezado de roles quede a la vista al bajar. */}
        <div className="overflow-auto rounded-md border border-line bg-surface desk:max-h-[calc(100dvh-var(--spacing-topbar)-14rem)]">
          <table className="w-full border-separate border-spacing-0 text-left text-sm">
            <caption className="sr-only">
              Matriz de permisos: cada fila es un permiso y cada columna, un rol.
            </caption>
            <thead>
              <tr>
                <th
                  scope="col"
                  className="sticky top-0 left-0 z-30 min-w-40 border-r border-b border-line bg-surface px-2 py-3 font-medium text-ink-muted desk:min-w-56 desk:px-4"
                >
                  Permiso
                </th>
                {matrix.roles.map((r) => (
                  <th
                    key={r.code}
                    scope="col"
                    className="sticky top-0 z-20 w-20 min-w-20 border-b border-line bg-surface px-1 py-3 text-center align-bottom font-medium break-words hyphens-auto text-ink"
                  >
                    {r.name}
                    {r.is_mine ? (
                      <span className="block text-xs font-normal text-ink-muted">
                        (tuyo, no se cambia)
                      </span>
                    ) : null}
                  </th>
                ))}
              </tr>
            </thead>
            {modules.map((m) => (
              <tbody key={m.code}>
                <tr>
                  <th
                    scope="colgroup"
                    colSpan={matrix.roles.length + 1}
                    className="border-b border-line bg-app py-2 text-left font-semibold text-ink"
                  >
                    {/* El nombre del módulo queda a la vista al correr la tabla de costado. */}
                    <span className="sticky left-0 px-2 desk:px-4">{m.name}</span>
                  </th>
                </tr>
                {m.permissions.map((p) => (
                  <tr key={p.code}>
                    <th
                      scope="row"
                      className="sticky left-0 z-10 border-r border-b border-line bg-surface px-2 py-1 font-normal text-ink desk:px-4"
                    >
                      <Tooltip
                        side="right"
                        content={
                          <>
                            <span>{p.description}</span>
                            <code className="text-xs text-ink-muted">{p.code}</code>
                          </>
                        }
                      >
                        <span
                          tabIndex={0}
                          className="inline-flex min-h-touch items-center gap-2 rounded-sm underline decoration-ink-muted decoration-dotted underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                        >
                          {p.name}
                          {p.is_sensitive ? (
                            <span
                              role="img"
                              aria-label="sensible"
                              className="size-2 shrink-0 rounded-full bg-warn-ink"
                            />
                          ) : null}
                        </span>
                      </Tooltip>
                      {/* En el celular el tooltip no se abre al tocar: la explicación va debajo. */}
                      <span className="block pb-1 text-xs text-ink-muted desk:hidden">
                        {p.description}
                      </span>
                    </th>
                    {matrix.roles.map((r) => {
                      const key = cellKey(r.code, p.code);
                      const value = cellValue(draft, original, key);
                      const changed = draft.has(key);
                      const pending = waiting.has(key);
                      const label = `${r.name}: ${p.name}${p.is_sensitive ? ", sensible" : ""}`;
                      const look = cn(
                        "mx-auto flex size-touch items-center justify-center rounded-sm border-2",
                        pending
                          ? "border-transparent bg-info text-info-ink"
                          : value
                            ? "bg-ok text-ok-ink"
                            : "bg-bad text-bad-ink",
                        !pending && (changed ? "border-dashed border-ink" : "border-transparent"),
                      );
                      const face = pending ? (
                        <Clock aria-hidden="true" className="size-5" />
                      ) : value ? (
                        <Check aria-hidden="true" className="size-5" />
                      ) : (
                        <X aria-hidden="true" className="size-5" />
                      );
                      return (
                        <td key={r.code} className="border-b border-line px-1 py-1 text-center">
                          {editable && !r.is_mine && !pending ? (
                            <button
                              type="button"
                              aria-pressed={value}
                              aria-label={changed ? `${label} (cambio sin guardar)` : label}
                              disabled={saving}
                              onClick={() => {
                                setDraft((d) => toggleCell(d, original, key));
                                setState({});
                              }}
                              className={cn(
                                look,
                                "cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                              )}
                            >
                              {face}
                            </button>
                          ) : (
                            <span className={look}>
                              {face}
                              <span className="sr-only">
                                {pending
                                  ? `${label}: pendiente de aprobación`
                                  : `${label}: ${value ? "sí" : "no"}`}
                              </span>
                            </span>
                          )}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            ))}
          </table>
        </div>

        {state.message ? (
          <Notice status={state.status === "bad" ? "bad" : state.status === "ok" ? "ok" : "info"}>
            {state.message}
          </Notice>
        ) : null}

        {editable ? (
          <div
            id="matriz-guardar"
            className={cn(
              "sticky bottom-[calc(var(--spacing-bottom-nav)+env(safe-area-inset-bottom))] z-40 -mx-4 flex-wrap items-end gap-3 border-t border-line bg-surface px-4 py-3 desk:bottom-0 desk:-mx-gutter desk:flex desk:px-gutter wide:-mx-gutter-wide wide:px-gutter-wide",
              // En el celular, la barra aparece solo cuando hay algo para guardar.
              draft.size > 0 ? "flex" : "hidden",
            )}
          >
            <p
              role="status"
              className={cn(
                "flex min-h-touch items-center text-base desk:min-h-control",
                draft.size > 0 ? "font-semibold text-ink" : "text-ink-muted",
              )}
            >
              {draft.size > 0 ? pendingLabel(draft.size) : "Sin cambios"}
            </p>
            {draft.size > 0 ? (
              <>
                <Field
                  id="matriz-motivo"
                  label="Motivo (obligatorio)"
                  error={state.fieldErrors?.reason}
                  className="min-w-64 flex-1"
                >
                  <Input
                    ref={reasonRef}
                    value={reason}
                    required
                    aria-required="true"
                    maxLength={500}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder="Por qué cambian estos permisos"
                  />
                </Field>
                <Button
                  variant="outline"
                  disabled={saving}
                  onClick={() => {
                    setDraft(new Map());
                    setState({});
                  }}
                >
                  Descartar
                </Button>
                <Button disabled={saving} onClick={requestSave}>
                  {saving ? "Guardando…" : "Guardar cambios"}
                </Button>
              </>
            ) : null}
          </div>
        ) : null}

        <Confirm
          open={confirming}
          onOpenChange={setConfirming}
          title="Permisos sensibles"
          description={
            sensitiveCount === 1
              ? "Vas a dar 1 permiso sensible: no se aplica al guardar, queda pendiente hasta que lo apruebe Dirección General. ¿Confirmás?"
              : `Vas a dar ${sensitiveCount} permisos sensibles: no se aplican al guardar, quedan pendientes hasta que los apruebe Dirección General. ¿Confirmás?`
          }
          confirmLabel="Sí, guardar"
          onConfirm={save}
        />
      </div>
    </TooltipProvider>
  );
}
