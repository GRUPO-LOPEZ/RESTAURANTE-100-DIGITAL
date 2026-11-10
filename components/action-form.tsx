"use client";

import * as React from "react";

import { FormNotice } from "@/components/form-notice";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import { Button } from "@/components/ui/button";
import { ServerForm, useServerForm } from "@/components/ui/form";
import type { ActionState } from "@/lib/auth/results";
import type { FormSchemaName } from "@/lib/forms/schemas";

// Formulario que llama a una acción de servidor y muestra lo que respondió la base. Valida antes
// de enviar con el esquema indicado (React Hook Form + Zod, ADR-0016): los campos van con
// FormInput, FormSelect o FormTextarea de components/ui/form.tsx.
export function ActionForm({
  action,
  schema,
  submitLabel,
  pendingLabel = "Enviando…",
  variant = "default",
  warnUnsaved = false,
  children,
  className,
}: {
  action: (state: ActionState, formData: FormData) => Promise<ActionState>;
  schema?: FormSchemaName;
  submitLabel: string;
  pendingLabel?: string;
  variant?: "default" | "outline" | "destructive";
  // Pregunta antes de irse si se escribió algo y no se guardó (formularios largos de las fichas).
  warnUnsaved?: boolean;
  children?: React.ReactNode;
  className?: string;
}) {
  const form = useServerForm({ schema, action });
  // Lo escrito queda guardado cuando llega una respuesta buena posterior a la última edición.
  const [editedAt, setEditedAt] = React.useState<ActionState | null>(null);
  const dirty = editedAt !== null && !(form.state.status === "ok" && form.state !== editedAt);
  useUnsavedWarning(warnUnsaved && dirty);
  return (
    <ServerForm form={form} className={className ?? "flex flex-col gap-4"}>
      {warnUnsaved ? (
        <div className="contents" onInput={() => setEditedAt(form.state)}>
          {children}
        </div>
      ) : (
        children
      )}
      <FormNotice state={form.state} />
      <Button type="submit" variant={variant} disabled={form.pending} className="w-full sm:w-auto">
        {form.pending ? pendingLabel : submitLabel}
      </Button>
    </ServerForm>
  );
}
