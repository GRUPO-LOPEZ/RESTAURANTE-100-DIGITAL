"use client";

import { Check, X } from "lucide-react";

import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { FormTextarea, ServerForm, useServerForm } from "@/components/ui/form";
import type { ActionState } from "@/lib/auth/results";

// Aprobar o rechazar. Que no sea la misma persona que pidió lo valida la base, no la pantalla.
export function DecisionForm({
  action,
  requestId,
}: {
  action: (state: ActionState, formData: FormData) => Promise<ActionState>;
  requestId: string;
}) {
  const form = useServerForm({
    schema: "decision",
    action: action,
    // La decisión sale del botón: para rechazar, el motivo (la base lo vuelve a revisar).
    check: (fd) =>
      fd.get("decision") === "rejected" && !String(fd.get("comment") ?? "").trim()
        ? { comment: "Para rechazar, escribí el motivo." }
        : undefined,
  });
  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      <input type="hidden" name="requestId" value={requestId} />
      <FormTextarea
        id={`comentario-${requestId}`}
        label="Comentario"
        hint="Obligatorio para rechazar. Queda en el historial."
        name="comment"
        maxLength={500}
      />
      <FormNotice state={form.state} />
      <div className="flex flex-col gap-2 sm:flex-row">
        <Button type="submit" name="decision" value="approved" disabled={form.pending}>
          <Check aria-hidden="true" />
          Aprobar
        </Button>
        <Button
          type="submit"
          name="decision"
          value="rejected"
          variant="destructive"
          disabled={form.pending}
        >
          <X aria-hidden="true" />
          Rechazar
        </Button>
      </div>
    </ServerForm>
  );
}
