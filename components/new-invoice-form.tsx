"use client";

import { createInvoiceAction } from "@/app/compras/facturas/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { FormInput, FormSelect, ServerForm, useServerForm, FormDate } from "@/components/ui/form";
import { SegmentedField } from "@/components/ui/segmented-field";
import { todayInArgentina } from "@/lib/forms/schemas";
import { AUTHORIZATION_KINDS, INVOICE_CLASSES, isFiscal, type InvoiceClass } from "@/lib/invoices";
import type { InvoiceableOrder } from "@/lib/invoices-data";
import { formatCuit } from "@/lib/suppliers";

// Alta corta de una factura (ADR-0058): lo usan el modal del listado y la página /compras/facturas/nueva. Proveedor,
// las órdenes recibidas que cubre y los datos del papel; las líneas salen solas de lo recibido, con el precio de la
// lista, y se ajustan en la ficha. El CUIT del emisor es el del proveedor (lo pone la acción).
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
  // Lo elegido decide qué órdenes y qué campos se muestran.
  const supplierId = String(form.methods.watch("supplierId") ?? "");
  const invoiceClass = (form.methods.watch("invoice_class") ?? "invoice_a") as InvoiceClass;
  if (!place)
    return (
      <p className="text-base text-ink">
        Elegí arriba, en «Local», dónde se recibió la mercadería.
      </p>
    );
  const fiscal = isFiscal(invoiceClass);
  const supplier = suppliers.find((s) => s.id === supplierId);
  const own = orders.filter((o) => o.supplierId === supplierId);
  // Primero los proveedores con órdenes recibidas para facturar.
  const withOrders = new Set(orders.map((o) => o.supplierId));
  const sorted = [...suppliers].sort(
    (a, b) =>
      Number(withOrders.has(b.id)) - Number(withOrders.has(a.id)) ||
      a.name.localeCompare(b.name, "es"),
  );
  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      <input type="hidden" name="restaurantId" value={place.id} />
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
        own.length > 0 ? (
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-sm font-medium text-ink">Órdenes que cubre</legend>
            {own.map((o) => (
              <Checkbox
                key={o.id}
                id={`fc-nueva-oc-${o.id}`}
                name="orderId"
                value={o.id}
                defaultChecked={own.length === 1}
                label={`${o.number}${o.partial ? " (recibida en parte)" : ""}${o.receivedOn ? ` · recibida el ${o.receivedOn.split("-").reverse().join("/")}` : ""}`}
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

      <FormSelect
        id="fc-nueva-clase"
        name="invoice_class"
        label="Comprobante"
        required
        defaultValue="invoice_a"
      >
        {INVOICE_CLASSES.map((c) => (
          <option key={c.value} value={c.value}>
            {c.label}
          </option>
        ))}
      </FormSelect>
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
        />
      </div>
      <FormDate
        id="fc-nueva-fecha"
        name="issued_on"
        label="Fecha de la factura"
        max={todayInArgentina()}
        defaultValue={todayInArgentina()}
        required
      />
      {fiscal ? (
        <>
          <SegmentedField
            id="fc-nueva-aut"
            name="authorization_kind"
            label="Autorización"
            options={AUTHORIZATION_KINDS}
            defaultValue="cae"
          />
          <FormInput
            id="fc-nueva-cae"
            name="authorization_code"
            label="Número de autorización"
            inputMode="numeric"
            maxLength={14}
            required
            hint="Los 14 números del CAE, CAI o CAEA."
          />
          <p className="text-sm text-ink">
            CUIT del emisor:{" "}
            <span className="tabular-nums">
              {supplier
                ? supplier.taxId
                  ? formatCuit(supplier.taxId)
                  : "el proveedor no tiene CUIT"
                : "el del proveedor"}
            </span>
          </p>
        </>
      ) : (
        <>
          <input type="hidden" name="authorization_kind" value="cae" />
          <input type="hidden" name="authorization_code" value="" />
        </>
      )}
      <FormNotice state={form.state} />
      <Button type="submit" disabled={form.pending} className="w-full sm:w-auto">
        {form.pending ? "Cargando…" : "Cargar y completar la factura"}
      </Button>
    </ServerForm>
  );
}
