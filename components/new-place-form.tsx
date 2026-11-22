"use client";

import { useEffect, useState } from "react";
import { useFormContext } from "react-hook-form";

import { createPlaceAction, peekPlaceAction } from "@/app/configuracion/structure-actions";
import { ActionForm } from "@/components/action-form";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { SegmentedField } from "@/components/ui/segmented-field";
import { SITE_TYPE_OPTIONS } from "@/lib/org-sheet";

// Alta corta de un local (Tanda 1 de Soy, ADR-0061): marca (botones), zona, tipo y motivo. El nombre (marca + zona) y
// el código (RAGU-002) los arma la base; «Así va a quedar» los muestra antes de crear, sin consumir el número. El local
// nace En apertura y el resto se completa en su ficha. Lo usan el modal del Panel y /configuracion/locales/nuevo.
export function NewPlaceForm({
  brands,
  defaultBrandId,
}: {
  brands: { id: string; name: string }[];
  defaultBrandId?: string;
}) {
  return (
    <ActionForm
      action={createPlaceAction}
      schema="placeNew"
      submitLabel="Crear y completar la ficha"
    >
      <SegmentedField
        id="local-nuevo-marca"
        name="brand_id"
        label="Marca"
        options={brands.map((b) => ({ value: b.id, label: b.name }))}
        defaultValue={defaultBrandId ?? (brands.length === 1 ? brands[0]?.id : undefined)}
      />
      <FormInput
        id="local-nuevo-zona"
        name="zone"
        label="Zona o ubicación"
        required
        maxLength={80}
        placeholder="Por ejemplo: Belgrano"
      />
      <SegmentedField
        id="local-nuevo-tipo"
        name="site_type"
        label="Tipo"
        options={SITE_TYPE_OPTIONS}
        defaultValue="restaurant"
      />
      <Preview />
      <FormTextarea
        id="local-nuevo-motivo"
        name="reason"
        label="Motivo"
        hint="Por ejemplo: apertura nueva en Belgrano. Queda en el historial."
        required
        maxLength={500}
      />
    </ActionForm>
  );
}

// «Así va a quedar»: lo que va a armar la base con la marca y la zona.
function Preview() {
  const form = useFormContext();
  const brandId = (form?.watch("brand_id") as string | undefined) ?? "";
  const zone = (form?.watch("zone") as string | undefined) ?? "";
  const [preview, setPreview] = useState<{ name: string | null; code: string } | null>(null);

  useEffect(() => {
    if (!brandId) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      void peekPlaceAction(brandId, zone).then((p) => {
        if (!cancelled) setPreview(p);
      });
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [brandId, zone]);

  const shown = brandId ? preview : null;
  return (
    <div className="flex flex-col gap-1 rounded-sm border border-line bg-app p-3">
      <p className="text-sm font-medium text-ink">Así va a quedar</p>
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm" aria-live="polite">
        <dt className="text-ink-muted">Nombre</dt>
        <dd className="font-medium text-ink">{shown?.name ?? "—"}</dd>
        <dt className="text-ink-muted">Código</dt>
        <dd className="font-medium text-ink tabular-nums">{shown?.code ?? "—"}</dd>
      </dl>
      <p className="text-xs text-ink-muted">El número sigue solo y el código no cambia nunca.</p>
    </div>
  );
}
