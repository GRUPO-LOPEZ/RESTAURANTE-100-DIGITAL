"use client";

import { useActionState } from "react";
import { Check, X } from "lucide-react";

import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Field, Textarea } from "@/components/ui/field";
import type { ActionState } from "@/lib/auth/results";

// Aprobar o rechazar. Que no sea la misma persona que pidió lo valida la base, no la pantalla.
export function DecisionForm({
  action,
  requestId,
}: {
  action: (state: ActionState, formData: FormData) => Promise<ActionState>;
  requestId: string;
}) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(action, {});
  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="requestId" value={requestId} />
      <Field
        id={`comentario-${requestId}`}
        label="Comentario"
        hint="Obligatorio para rechazar. Queda en el historial."
      >
        <Textarea name="comment" maxLength={500} />
      </Field>
      <FormNotice state={state} />
      <div className="flex flex-col gap-2 sm:flex-row">
        <Button type="submit" name="decision" value="approved" disabled={pending}>
          <Check aria-hidden="true" />
          Aprobar
        </Button>
        <Button
          type="submit"
          name="decision"
          value="rejected"
          variant="destructive"
          disabled={pending}
        >
          <X aria-hidden="true" />
          Rechazar
        </Button>
      </div>
    </form>
  );
}
