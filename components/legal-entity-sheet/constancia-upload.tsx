"use client";

import { useId, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Upload } from "lucide-react";

import { uploadConstanciaAction } from "@/app/configuracion/structure-actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";
import { Input } from "@/components/ui/field";
import type { ActionState } from "@/lib/auth/results";
import { todayInArgentina } from "@/lib/forms/schemas";

// «Subir constancia de ARCA» (ADR-0061, decisión 4 de Soy): el PDF de la constancia de inscripción y su fecha de
// emisión. Se suma a las anteriores (nada se borra) y vale la más reciente. Storage y la base controlan que la sesión
// administre todo el grupo.
export function ConstanciaUpload({ legalEntityId }: { legalEntityId: string }) {
  const id = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [state, setState] = useState<ActionState>({});
  const [pending, start] = useTransition();
  const today = todayInArgentina();

  function submit(form: HTMLFormElement) {
    const data = new FormData(form);
    data.set("legalEntityId", legalEntityId);
    start(async () => {
      const result = await uploadConstanciaAction({}, data);
      setState(result);
      if (result.status === "ok") {
        setOpen(false);
        router.refresh();
      }
    });
  }

  return (
    <>
      <Button type="button" variant="outline" onClick={() => setOpen(true)} aria-haspopup="dialog">
        <Upload aria-hidden="true" />
        Subir constancia de ARCA
      </Button>
      <Modal
        open={open}
        onOpenChange={setOpen}
        title="Subir constancia de ARCA"
        description="El PDF de la constancia de inscripción, como lo baja ARCA. La anterior queda en la historia."
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            submit(e.currentTarget);
          }}
        >
          <FormNotice state={state} />
          <div className="flex flex-col gap-1">
            <label htmlFor={`${id}-file`} className="text-sm font-medium text-ink">
              PDF de la constancia<span aria-hidden="true"> *</span>
            </label>
            <Input
              id={`${id}-file`}
              name="file"
              type="file"
              accept="application/pdf"
              required
              aria-describedby={`${id}-file-hint`}
            />
            <span id={`${id}-file-hint`} className="text-xs text-ink-muted">
              Hasta 3,5 MB.
            </span>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor={`${id}-date`} className="text-sm font-medium text-ink">
              Fecha de emisión<span aria-hidden="true"> *</span>
            </label>
            <Input
              id={`${id}-date`}
              name="issued_on"
              type="date"
              max={today}
              defaultValue={today}
              required
            />
          </div>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
              Cancelar
            </Button>
            <Button type="submit" disabled={pending}>
              {pending ? "Subiendo…" : "Subir"}
            </Button>
          </div>
        </form>
      </Modal>
    </>
  );
}
