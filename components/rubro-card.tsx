"use client";

import * as React from "react";
import { Check, Plus, X } from "lucide-react";

import {
  createRubroAction,
  deactivateRubroAction,
  reactivateRubroAction,
  renameRubroAction,
} from "@/app/rubros/actions";
import { ActionForm } from "@/components/action-form";
import { Modal } from "@/components/ui/dialog";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import type { ActionState } from "@/lib/auth/results";
import { schemas } from "@/lib/forms/schemas";
import { sharePercent, usesLabel, type Rubro, type RubroClass } from "@/lib/rubros";
import { cn } from "@/lib/utils";

// Tarjeta de un rubro (ADR-0038). Arriba, el nombre a todo el ancho (hasta dos líneas, editable en el lugar).
// Abajo, el código con su parte del total de la pestaña y cuánto se usa, y a la derecha el estado con ícono y
// palabra. Al pie, una barra fina. Dados de baja, en gris (la página los pone al final). La base controla el
// permiso; la tarjeta solo oculta lo que la persona no puede hacer.
//
// 88 px en la computadora (alto mínimo): 4 de relleno, nombre de 36, fila de 36 (controles), barra de 4,
// 4 de relleno y el borde. En el celular los controles miden 44 px y la tarjeta crece lo justo.

// La barra lleva el tono fuerte de su pestaña (design.md: barras con chart-strong).
const BAR: Record<RubroClass, string> = {
  purchase: "bg-chart-strong-2",
  subrecipe: "bg-chart-strong-5",
  menu: "bg-chart-strong-6",
};

export function RubroCard({
  rubro,
  total,
  canManage,
  targets,
}: {
  rubro: Rubro;
  // Usos de toda la pestaña: el denominador del porcentaje.
  total: number;
  canManage: boolean;
  // Rubros activos de la misma clase, para elegir el destino de una baja.
  targets: { id: string; label: string }[];
}) {
  const pct = sharePercent(rubro.uses, total);
  return (
    <article
      aria-label={`${rubro.name} (${rubro.code})`}
      className={cn(
        "flex min-h-22 flex-col justify-between rounded-md border border-line px-3 py-1",
        rubro.isActive ? "bg-surface" : "bg-app",
      )}
    >
      {canManage ? (
        <RubroName rubro={rubro} />
      ) : (
        <h3
          className={cn(
            "flex min-h-control-sm items-center text-sm leading-4 font-medium [overflow-wrap:anywhere]",
            rubro.isActive ? "text-ink" : "text-ink-muted",
          )}
        >
          <span className="line-clamp-2">{rubro.name}</span>
        </h3>
      )}
      <div className="flex flex-wrap items-center justify-between gap-x-2">
        <div className="flex min-w-0 flex-col text-xs text-ink-muted tabular-nums">
          <span>
            <span className="font-medium">{rubro.code}</span>
            {" · "}
            <span className="text-ink">{pct === null ? "Sin datos" : `${pct} %`}</span>
            <span className="sr-only"> del total de la pestaña</span>
          </span>
          {rubro.uses === 0 ? (
            <span>
              <span className="rounded-sm bg-none px-1 text-none-ink">Sin uso</span>
              <span className="sr-only"> ({usesLabel(rubro.rubroClass, 0)})</span>
            </span>
          ) : (
            <span>{usesLabel(rubro.rubroClass, rubro.uses)}</span>
          )}
        </div>
        {canManage ? (
          <StatusDialog rubro={rubro} targets={targets} />
        ) : (
          <StatusPill active={rubro.isActive} />
        )}
      </div>
      <span aria-hidden="true" className="block h-1 overflow-hidden rounded-sm bg-line">
        {pct !== null ? (
          <span
            className={cn("block h-full", BAR[rubro.rubroClass])}
            style={{ width: `${pct}%` }}
          />
        ) : null}
      </span>
    </article>
  );
}

// El estado, igual para quien administra (dentro del botón) y para quien solo ve: ícono y palabra, nunca solo
// color. Dado de baja va en gris (no es crítico).
function StatusPill({ active }: { active: boolean }) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center gap-1 rounded-sm px-1.5 text-xs leading-5 font-medium",
        active ? "bg-ok text-ok-ink" : "bg-none text-none-ink",
      )}
    >
      {active ? (
        <Check aria-hidden="true" className="size-4" />
      ) : (
        <X aria-hidden="true" className="size-4" />
      )}
      {active ? "Activo" : "De baja"}
    </span>
  );
}

// Nombre editable en el lugar: clic para editar, Enter guarda y Escape cancela. El motivo es fijo
// («Cambio de nombre desde Rubros») y la auditoría guarda quién y cuándo.
function RubroName({ rubro }: { rubro: Rubro }) {
  const [editing, setEditing] = React.useState(false);
  // Al cerrar la edición, el foco vuelve al nombre cuando el botón aparece (no antes).
  const refocus = React.useRef(false);
  const focusIfNeeded = React.useCallback((el: HTMLButtonElement | null) => {
    if (el && refocus.current) {
      refocus.current = false;
      el.focus();
    }
  }, []);
  // Una respuesta buena cierra la edición y devuelve el foco al nombre.
  const [state, action, pending] = React.useActionState<ActionState, FormData>(
    async (prev, formData) => {
      const result = await renameRubroAction(prev, formData);
      if (result.status === "ok") {
        setEditing(false);
        refocus.current = true;
      }
      return result;
    },
    {},
  );
  const [clientError, setClientError] = React.useState<string | null>(null);
  // La respuesta que ya estaba al abrir: no se vuelve a mostrar ni a anunciar.
  const [openedWith, setOpenedWith] = React.useState<ActionState | null>(null);
  const fresh = state !== openedWith;
  const error =
    clientError ??
    (state.status === "bad" && fresh ? (state.fieldErrors?.name ?? state.message ?? null) : null);
  const inputId = `rub-nombre-${rubro.id}`;

  return (
    <div className="flex min-h-touch min-w-0 flex-col justify-center desk:min-h-control-sm">
      {editing ? (
        <form
          action={action}
          onSubmit={(event) => {
            const name = new FormData(event.currentTarget).get("name");
            const parsed = schemas.rubroName.safeParse({ name });
            if (!parsed.success) {
              event.preventDefault();
              setClientError(parsed.error.issues[0]?.message ?? "Revisá el nombre.");
            } else {
              setClientError(null);
            }
          }}
          className="flex min-w-0 flex-col gap-1"
        >
          <input type="hidden" name="rubroId" value={rubro.id} />
          <input type="hidden" name="rubroClass" value={rubro.rubroClass} />
          <label htmlFor={inputId} className="sr-only">
            Nombre de {rubro.code}
          </label>
          <input
            id={inputId}
            name="name"
            defaultValue={rubro.name}
            maxLength={80}
            autoFocus
            disabled={pending}
            aria-invalid={error ? true : undefined}
            aria-describedby={`${inputId}-ayuda${error ? ` ${inputId}-error` : ""}`}
            onKeyDown={(event) => {
              if (event.key === "Escape") {
                event.preventDefault();
                setEditing(false);
                refocus.current = true;
              }
            }}
            className="min-h-touch w-full min-w-0 rounded-sm border border-line bg-surface px-2 text-sm text-ink desk:min-h-control-sm"
          />
          {/* La ayuda la lee el lector de pantalla: a la vista no agranda la tarjeta. */}
          <span id={`${inputId}-ayuda`} className="sr-only">
            Enter guarda, Escape cancela.
          </span>
          {error ? (
            <p id={`${inputId}-error`} role="alert" className="text-xs text-bad-ink">
              {error}
            </p>
          ) : null}
        </form>
      ) : (
        <button
          ref={focusIfNeeded}
          type="button"
          onClick={() => {
            setOpenedWith(state);
            setClientError(null);
            setEditing(true);
          }}
          className={cn(
            "min-h-touch min-w-0 rounded-sm text-left text-sm leading-4 font-medium [overflow-wrap:anywhere] underline-offset-4 hover:underline desk:min-h-control-sm",
            rubro.isActive ? "text-ink" : "text-ink-muted",
          )}
        >
          <span className="line-clamp-2">{rubro.name}</span>
          <span className="sr-only"> (cambiar el nombre)</span>
        </button>
      )}
      {/* El aviso de que se guardó, para el lector de pantalla (la región existe siempre). */}
      <span role="status" className="sr-only">
        {state.status === "ok" && fresh ? state.message : ""}
      </span>
    </div>
  );
}

// Estado con ícono y palabra. Quien administra lo toca para dar de baja (con destino si tiene usos) o
// reactivar, en una ventana que pide el motivo.
function StatusDialog({
  rubro,
  targets,
}: {
  rubro: Rubro;
  targets: { id: string; label: string }[];
}) {
  const trigger = (
    <button
      type="button"
      title={rubro.isActive ? "Dar de baja" : "Reactivar"}
      className="inline-flex min-h-touch shrink-0 items-center rounded-sm underline-offset-4 hover:underline desk:min-h-control-sm"
    >
      <StatusPill active={rubro.isActive} />
      <span className="sr-only">
        {rubro.isActive ? ` (dar de baja ${rubro.name})` : ` (reactivar ${rubro.name})`}
      </span>
    </button>
  );
  const prefix = `rub-${rubro.id}`;
  if (!rubro.isActive) {
    return (
      <Modal
        trigger={trigger}
        title={`Reactivar «${rubro.name}»`}
        description="Vuelve a aparecer para elegirlo al cargar."
      >
        <ActionForm action={reactivateRubroAction} schema="reason" submitLabel="Reactivar">
          <input type="hidden" name="rubroId" value={rubro.id} />
          <input type="hidden" name="rubroClass" value={rubro.rubroClass} />
          <FormTextarea
            id={`${prefix}-alta-motivo`}
            name="reason"
            label="Motivo"
            hint="Queda en el historial."
            required
            maxLength={500}
          />
        </ActionForm>
      </Modal>
    );
  }
  return (
    <Modal
      trigger={trigger}
      title={`Dar de baja «${rubro.name}»`}
      description="Deja de aparecer para elegirlo al cargar. Se puede reactivar y la historia se conserva."
    >
      <ActionForm
        action={deactivateRubroAction}
        schema="rubroDeactivate"
        submitLabel="Dar de baja"
        variant="destructive"
      >
        <input type="hidden" name="rubroId" value={rubro.id} />
        <input type="hidden" name="rubroClass" value={rubro.rubroClass} />
        {rubro.uses > 0 ? (
          targets.length > 0 ? (
            <FormSelect
              id={`${prefix}-destino`}
              name="target_id"
              label="Pasar a"
              hint={`Tiene ${usesLabel(rubro.rubroClass, rubro.uses)}: pasan todos a este rubro.`}
              required
              defaultValue=""
            >
              <option value="" disabled>
                Elegí el rubro destino
              </option>
              {targets.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.label}
                </option>
              ))}
            </FormSelect>
          ) : (
            <p className="text-base text-ink">
              Tiene {usesLabel(rubro.rubroClass, rubro.uses)} y no hay otro rubro activo para
              pasarlos. Creá uno antes.
            </p>
          )
        ) : null}
        <FormTextarea
          id={`${prefix}-baja-motivo`}
          name="reason"
          label="Motivo"
          hint="Queda en el historial."
          required
          maxLength={500}
        />
      </ActionForm>
    </Modal>
  );
}

// Última tarjeta: alta de un rubro de la pestaña. El código lo genera la base con el prefijo de la clase.
export function NewRubroCard({
  groupId,
  rubroClass,
  classLabel,
  prefix,
}: {
  groupId: string;
  rubroClass: RubroClass;
  classLabel: string;
  prefix: string;
}) {
  return (
    <Modal
      trigger={
        <button
          type="button"
          className="flex min-h-22 w-full items-center justify-center gap-2 rounded-md border border-dashed border-line bg-surface px-3 text-sm font-medium text-primary underline-offset-4 hover:underline"
        >
          <Plus aria-hidden="true" className="size-4" />
          Nuevo rubro
        </button>
      }
      title="Nuevo rubro"
      description={`En ${classLabel.toLowerCase()}. El código se arma solo: ${prefix}- y tres letras del nombre.`}
    >
      <ActionForm
        action={createRubroAction}
        schema="rubro"
        submitLabel="Crear rubro"
        pendingLabel="Creando…"
      >
        <input type="hidden" name="groupId" value={groupId} />
        <input type="hidden" name="rubroClass" value={rubroClass} />
        <FormInput id="rub-alta-nombre" label="Nombre" name="name" required maxLength={80} />
        <FormTextarea
          id="rub-alta-motivo"
          name="reason"
          label="Motivo"
          hint="Queda en el historial."
          required
          maxLength={500}
        />
      </ActionForm>
    </Modal>
  );
}
