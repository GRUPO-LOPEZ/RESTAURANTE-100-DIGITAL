"use client";

import { useId, useState, useTransition } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Upload } from "lucide-react";

import { addNoteAction, uploadInvoiceFileAction } from "@/app/compras/facturas/actions";
import { ActionForm } from "@/components/action-form";
import { FormNotice } from "@/components/form-notice";
import { FormInput, FormTextarea, FormDate } from "@/components/ui/form";
import { SegmentedField } from "@/components/ui/segmented-field";
import type { ActionState } from "@/lib/auth/results";
import { todayInArgentina } from "@/lib/forms/schemas";
import { NOTE_KINDS } from "@/lib/invoices";
import { shrinkPhoto } from "@/lib/photos";
import { cn } from "@/lib/utils";

// La foto (o el PDF) de una factura o de una nota (ADR-0058). La foto se achica en el navegador; el PDF va como está.
// La base controla que la sesión cargue facturas en el local y que la factura todavía se pueda cambiar; al registrar la
// foto de una nota, vuelve a controlar la factura.
export function InvoiceFileUpload({
  invoiceId,
  sourceTable,
  sourceId,
  label,
  className,
}: {
  invoiceId: string;
  sourceTable: "invoices" | "credit_debit_notes";
  sourceId: string;
  label: string;
  className?: string;
}) {
  const id = useId();
  const router = useRouter();
  const pathname = usePathname();
  const [state, setState] = useState<ActionState>({});
  const [pending, start] = useTransition();

  function upload(file: File | undefined) {
    if (!file) return;
    start(async () => {
      try {
        const body =
          file.type === "application/pdf"
            ? file
            : new File([await shrinkPhoto(file)], "foto.jpg", { type: "image/jpeg" });
        const form = new FormData();
        form.set("invoiceId", invoiceId);
        form.set("sourceTable", sourceTable);
        form.set("sourceId", sourceId);
        form.set("file", body);
        const result = await uploadInvoiceFileAction({}, form);
        setState(result);
        // Bien: vuelve a la ficha con el aviso en la barra (este botón puede desaparecer: la nota ya tiene su foto).
        if (result.status !== "bad" && result.notice)
          router.replace(`${pathname}?aviso=${result.notice}`, { scroll: false });
      } catch {
        setState({
          status: "bad",
          message: "No pudimos leer el archivo: probá con otra foto o un PDF.",
        });
      }
    });
  }

  return (
    <div className={cn("flex flex-col gap-1", className)}>
      <label
        htmlFor={id}
        className="inline-flex min-h-touch w-fit cursor-pointer items-center gap-2 rounded-sm border border-line bg-surface px-3 text-sm font-medium text-ink hover:bg-line/50 has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-primary desk:min-h-8"
      >
        <Upload aria-hidden="true" className="size-4" />
        {pending ? "Subiendo…" : label}
        <input
          id={id}
          type="file"
          accept="image/*,application/pdf"
          className="sr-only"
          disabled={pending}
          onChange={(e) => {
            upload(e.target.files?.[0]);
            e.target.value = "";
          }}
        />
      </label>
      <FormNotice state={state} />
    </div>
  );
}

// «+ Nota»: crédito, débito o descuento, con su número, fecha, importe y motivo. La foto se sube después, en la lista.
export function NoteForm({ invoiceId, invoiceIsA }: { invoiceId: string; invoiceIsA: boolean }) {
  return (
    <ActionForm action={addNoteAction} schema="invoiceNote" submitLabel="Guardar la nota">
      <input type="hidden" name="invoiceId" value={invoiceId} />
      <SegmentedField
        id="fc-nota-clase"
        name="note_kind"
        label="Qué es"
        options={NOTE_KINDS}
        defaultValue="credit"
      />
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput id="fc-nota-numero" name="number" label="Número" maxLength={40} />
        <FormDate
          id="fc-nota-fecha"
          name="issued_on"
          label="Fecha"
          max={todayInArgentina()}
          defaultValue={todayInArgentina()}
          required
        />
        <FormInput
          id="fc-nota-neto"
          name="net_amount"
          label={invoiceIsA ? "Importe sin IVA" : "Importe"}
          inputMode="decimal"
          required
          hint="Es lo que se compara con la diferencia del control."
        />
        <FormInput
          id="fc-nota-total"
          name="total_amount"
          label="Total"
          inputMode="decimal"
          hint="Vacío: el mismo importe."
        />
      </div>
      <FormTextarea
        id="fc-nota-motivo"
        name="reason"
        label="Motivo"
        hint="Por qué se emitió. Queda en el historial."
        required
        maxLength={500}
      />
    </ActionForm>
  );
}
