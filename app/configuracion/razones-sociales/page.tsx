import Link from "next/link";
import { Suspense } from "react";

import { createLegalEntityAction, updateLegalEntityAction } from "@/app/configuracion/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import {
  VAT_CONDITION_LABELS,
  formatTaxId,
  getLegalEntities,
  getOrgPermissions,
  getRestaurants,
  type LegalEntityRow,
  type VatCondition,
} from "@/lib/org";
import { requireMenu } from "@/lib/auth/session";

// Razones sociales del grupo (ADR-0031; respuesta 2 de Soy, ADR-0030): ¿qué sociedades hay y qué
// locales usa cada una? Las administra quien administra todo el grupo. La condición frente al IVA
// decide si el costo de sus locales va con o sin IVA.
export default function RazonesSocialesPage() {
  return (
    <AppShell
      title="Razones sociales"
      description="Las sociedades del grupo, con su CUIT y su condición frente al IVA."
    >
      <Suspense fallback={<Loading />}>
        <LegalEntities />
      </Suspense>
    </AppShell>
  );
}

function EntityFields({ prefix, entity }: { prefix: string; entity?: LegalEntityRow }) {
  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id={`${prefix}-nombre`}
          label="Nombre"
          hint="Como figura en el CUIT."
          name="name"
          required
          maxLength={200}
          defaultValue={entity?.name}
        />
        <FormInput
          id={`${prefix}-cuit`}
          label="CUIT"
          hint="Con o sin guiones, por ejemplo 30-12345678-9."
          name="tax_id"
          required
          maxLength={15}
          autoComplete="off"
          defaultValue={entity ? formatTaxId(entity.taxId) : undefined}
        />
      </div>
      <FormSelect
        id={`${prefix}-iva`}
        label="Condición frente al IVA"
        hint="Solo un responsable inscripto descuenta el IVA de sus costos."
        name="vat_condition"
        required
        defaultValue={entity?.vatCondition ?? ""}
      >
        <option value="" disabled>
          Elegí la condición
        </option>
        {(Object.keys(VAT_CONDITION_LABELS) as VatCondition[]).map((v) => (
          <option key={v} value={v}>
            {VAT_CONDITION_LABELS[v]}
          </option>
        ))}
      </FormSelect>
      <FormTextarea
        id={`${prefix}-motivo`}
        label="Motivo"
        hint="Queda en el historial."
        name="reason"
        required
        maxLength={500}
      />
    </>
  );
}

async function LegalEntities() {
  await requireMenu("orgManageGroup");
  const [entities, restaurants, permissions] = await Promise.all([
    getLegalEntities(),
    getRestaurants(),
    getOrgPermissions(),
  ]);
  // Hoy hay un solo grupo. Si se suman otros, el alta va a tener que elegir el grupo.
  const groupId = permissions.groups[0];
  const without = restaurants.filter((r) => !r.legalEntityId);
  return (
    <>
      <Link
        href="/configuracion"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver al panel de control
      </Link>
      {without.length > 0 ? (
        <Notice status="warn">
          <p>
            {without.length === 1
              ? "1 local todavía no tiene razón social"
              : `${without.length} locales todavía no tienen razón social`}
            : su costo sin IVA queda incompleto. Elegila en la ficha de cada uno:
          </p>
          <ul className="mt-2 flex flex-col gap-1">
            {without.map((r) => (
              <li key={r.id}>
                <Link
                  href={`/configuracion/locales/${r.id}`}
                  className="inline-flex min-h-touch items-center font-medium underline underline-offset-4"
                >
                  {r.name}
                </Link>
              </li>
            ))}
          </ul>
        </Notice>
      ) : null}
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {entities.length === 1 ? "1 razón social" : `${entities.length} razones sociales`}
        </CardTitle>
        <CardDescription>
          Varios locales pueden compartir una razón social. Cambiar la condición frente al IVA
          cambia el costo de todos sus locales.
        </CardDescription>
        {entities.length === 0 ? (
          <EmptyState title="Todavía no hay razones sociales.">
            Cargá la primera con «Nueva razón social».
          </EmptyState>
        ) : (
          <ul aria-label="Razones sociales" className="flex flex-col gap-2">
            {entities.map((e) => {
              const uses = restaurants.filter((r) => r.legalEntityId === e.id);
              return (
                <li key={e.id} className="flex flex-col gap-2 rounded-sm border border-line p-3">
                  <span className="font-medium text-ink">{e.name}</span>
                  <span className="text-sm text-ink-muted tabular-nums">
                    {formatTaxId(e.taxId)} · {VAT_CONDITION_LABELS[e.vatCondition]}
                  </span>
                  <span className="text-sm text-ink-muted">
                    {uses.length === 0
                      ? "Ningún local la usa todavía."
                      : `${uses.length === 1 ? "La usa" : "La usan"}: ${uses.map((r) => r.name).join(", ")}.`}
                  </span>
                  <Disclosure summary={`Editar «${e.name}»`}>
                    <ActionForm
                      action={updateLegalEntityAction}
                      schema="legalEntity"
                      submitLabel="Guardar razón social"
                    >
                      <input type="hidden" name="legalEntityId" value={e.id} />
                      <EntityFields prefix={`razon-${e.id}`} entity={e} />
                    </ActionForm>
                  </Disclosure>
                </li>
              );
            })}
          </ul>
        )}
        {groupId ? (
          <Disclosure summary="Nueva razón social">
            <ActionForm
              action={createLegalEntityAction}
              schema="legalEntity"
              submitLabel="Crear razón social"
              pendingLabel="Creando…"
            >
              <input type="hidden" name="groupId" value={groupId} />
              <EntityFields prefix="razon-nueva" />
            </ActionForm>
          </Disclosure>
        ) : null}
      </Card>
    </>
  );
}
