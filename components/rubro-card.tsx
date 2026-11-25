"use client";

import { Plus } from "lucide-react";

import {
  createRubroAction,
  deactivateRubroAction,
  reactivateRubroAction,
} from "@/app/rubros/actions";
import { ActionForm } from "@/components/action-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { usesLabel, type RubroClass } from "@/lib/rubros";

// Alta, baja y reactivación de un rubro (ADR-0038 y ADR-0066): cada una en su ventana, con motivo.
// Dar de baja (con destino si tiene usos) o reactivar.
export function RubroStatusDialog({
  rubro,
  targets,
}: {
  rubro: { id: string; name: string; rubroClass: RubroClass; isActive: boolean; uses: number };
  // Rubros activos de la misma clase, para elegir el destino de una baja.
  targets: { id: string; label: string }[];
}) {
  const trigger = (
    <Button type="button" variant="outline">
      {rubro.isActive ? "Dar de baja" : "Reactivar"}
      <span className="sr-only"> {rubro.name}</span>
    </Button>
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

// Alta de un rubro de la clase elegida. El código lo genera la base con su prefijo.
export function NewRubro({
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
        <Button type="button">
          <Plus aria-hidden="true" />
          Nuevo rubro
        </Button>
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
