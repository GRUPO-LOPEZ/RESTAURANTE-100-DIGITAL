"use client";

import { useRef, useState } from "react";

import { createInvoiceAction } from "@/app/compras/facturas/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Field } from "@/components/ui/field";
import { FileUpload } from "@/components/ui/file-upload";
import { FormInput, FormSelect, ServerForm, useServerForm } from "@/components/ui/form";
import { SegmentedField } from "@/components/ui/segmented-field";
import { todayInArgentina } from "@/lib/forms/schemas";
import {
  INVOICE_CLASSES,
  OTHER_INVOICE_CLASSES,
  isFiscal,
  type InvoiceClass,
} from "@/lib/invoices";
import type { InvoiceableOrder } from "@/lib/invoices-data";
import { shrinkPhoto } from "@/lib/photos";

// Alta corta de una factura (ADR-0058; criterios 3 y 11 de Soy, ADR-0070): un modal sin scroll con el proveedor, el
// comprobante (los tres de siempre como botones y «Otro»), el punto de venta y el número, y la foto si está a mano. La
// fecha arranca en hoy y el CAE se carga en la ficha: la base lo exige al controlar, no al cargar. Las líneas salen
// solas de las órdenes recibidas del proveedor, con el precio de la lista. Lo usan el modal del listado y
// /compras/facturas/nueva.
const PICKS = [
  { value: "invoice_a", label: "Factura A" },
  { value: "invoice_b", label: "Factura B" },
  { value: "invoice_remito_a", label: "Factura-remito A" },
  { value: "other", label: "Otro" },
];

export function NewInvoiceForm({
  place,
  orders,
  suppliers,
}: {
  place: { id: string; name: string } | null;
  orders: InvoiceableOrder[];
  suppliers: { id: string; name: string; taxId: string | null }[];
}) {
  const form = useServerForm({ schema: "invoiceNew", action: createInvoiceAction });
  const fileInput = useRef<HTMLInputElement>(null);
  const [photoNote, setPhotoNote] = useState("");
  const supplierId = String(form.methods.watch("supplierId") ?? "");
  const pick = String(form.methods.watch("class_pick") ?? "invoice_a");
  const other = String(form.methods.watch("other_class") ?? "invoice_c");
  const invoiceClass = (pick === "other" ? other : pick) as InvoiceClass;
  if (!place)
    return (
      <p className="text-base text-ink">
        Elegí arriba, en «Local», dónde se recibió la mercadería.
      </p>
    );
  const fiscal = isFiscal(invoiceClass);
  const own = orders.filter((o) => o.supplierId === supplierId);
  // Primero los proveedores con órdenes recibidas para facturar.
  const withOrders = new Set(orders.map((o) => o.supplierId));
  const sorted = [...suppliers].sort(
    (a, b) =>
      Number(withOrders.has(b.id)) - Number(withOrders.has(a.id)) ||
      a.name.localeCompare(b.name, "es"),
  );

  // La foto se achica en el navegador y viaja con el formulario (la acción la sube después de crear la factura).
  async function choose(file: File | null) {
    setPhotoNote("");
    const input = fileInput.current;
    if (!input) return;
    const box = new DataTransfer();
    if (file) {
      try {
        box.items.add(
          file.type === "application/pdf"
            ? file
            : new File([await shrinkPhoto(file)], "foto.jpg", { type: "image/jpeg" }),
        );
      } catch {
        setPhotoNote("No pudimos leer la foto: probá con otra o subila después en la ficha.");
      }
    }
    input.files = box.files;
  }

  const received = (o: InvoiceableOrder) =>
    `${o.number}${o.partial ? " (recibida en parte)" : ""}${o.receivedOn ? ` · recibida el ${o.receivedOn.split("-").reverse().join("/")}` : ""}`;

  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      <input type="hidden" name="restaurantId" value={place.id} />
      {/* Registrados: el formulario valida solo lo que conoce. */}
      <input
        type="hidden"
        defaultValue={todayInArgentina()}
        {...form.methods.register("issued_on")}
      />
      <FormSelect id="fc-nueva-proveedor" name="supplierId" label="Proveedor" required>
        <option value="">Elegí el proveedor</option>
        {sorted.map((s) => {
          const n = orders.filter((o) => o.supplierId === s.id).length;
          return (
            <option key={s.id} value={s.id}>
              {n > 0
                ? `${s.name} (${n === 1 ? "1 orden recibida" : `${n} órdenes recibidas`})`
                : s.name}
            </option>
          );
        })}
      </FormSelect>

      {supplierId ? (
        own.length === 1 && own[0] ? (
          <p className="text-sm text-ink">
            <input type="hidden" name="orderId" value={own[0].id} />
            Tiene la orden {received(own[0])}: las líneas salen de ahí.
          </p>
        ) : own.length > 1 ? (
          // Con muchas órdenes, la lista se desplaza adentro y el modal no crece (criterio 4).
          <fieldset className="relative flex max-h-40 flex-col gap-1 overflow-y-auto">
            <legend className="mb-1 text-sm font-medium text-ink">
              Órdenes recibidas: las líneas salen de las que dejes marcadas
            </legend>
            {own.map((o) => (
              <Checkbox
                key={o.id}
                id={`fc-nueva-oc-${o.id}`}
                name="orderId"
                value={o.id}
                defaultChecked
                label={received(o)}
              />
            ))}
          </fieldset>
        ) : (
          <p className="text-sm text-ink">
            Sin órdenes recibidas para facturar. Queda sin orden (un flete, un servicio) y la da por
            conforme otra persona.
          </p>
        )
      ) : null}

      <div className="flex flex-wrap items-end gap-3">
        <SegmentedField
          id="fc-nueva-clase"
          name="class_pick"
          label="Comprobante"
          options={PICKS}
          defaultValue="invoice_a"
        />
        {pick === "other" ? (
          <FormSelect
            id="fc-nueva-otro"
            name="other_class"
            label="Qué comprobante"
            defaultValue="invoice_c"
            className="w-44"
          >
            {INVOICE_CLASSES.filter((c) => OTHER_INVOICE_CLASSES.includes(c.value)).map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </FormSelect>
        ) : (
          <input type="hidden" defaultValue="invoice_c" {...form.methods.register("other_class")} />
        )}
      </div>
      <div className="grid gap-4 sm:grid-cols-[8rem_1fr]">
        {fiscal ? (
          <FormInput
            id="fc-nueva-pv"
            name="point_of_sale"
            label="Punto de venta"
            inputMode="numeric"
            maxLength={5}
            required
          />
        ) : (
          <input type="hidden" name="point_of_sale" value="" />
        )}
        <FormInput
          id="fc-nueva-numero"
          name="number"
          label="Número"
          inputMode="numeric"
          maxLength={8}
          required
          hint="Sin el punto de venta ni guiones."
          className={fiscal ? undefined : "sm:col-span-2"}
        />
      </div>
      <div className="flex flex-col gap-1">
        <Field
          id="fc-nueva-foto"
          label="Foto o PDF de la factura"
          hint="Opcional: si no, subila en la ficha."
        >
          <FileUpload accept="image/*,application/pdf" onFile={(f) => void choose(f)} />
        </Field>
        <input
          ref={fileInput}
          type="file"
          name="file"
          tabIndex={-1}
          aria-hidden="true"
          className="hidden"
        />
        {photoNote ? <p className="text-sm text-bad-ink">{photoNote}</p> : null}
      </div>
      <p className="text-sm text-ink-muted">
        La fecha arranca en hoy. La fecha del papel, el CAE y los totales se completan en la ficha.
      </p>
      <FormNotice state={form.state} />
      <Button type="submit" disabled={form.pending} className="w-full sm:w-auto sm:self-end">
        {form.pending ? "Creando…" : "Crear y abrir la factura"}
      </Button>
    </ServerForm>
  );
}
