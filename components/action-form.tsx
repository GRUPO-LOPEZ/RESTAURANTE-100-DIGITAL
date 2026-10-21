"use client";

import * as React from "react";
import { useActionState } from "react";

import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import type { ActionState } from "@/lib/auth/results";

// Formulario que llama a una acción de servidor y muestra lo que respondió la base.
export function ActionForm({
  action,
  submitLabel,
  pendingLabel = "Enviando…",
  variant = "default",
  children,
  className,
}: {
  action: (state: ActionState, formData: FormData) => Promise<ActionState>;
  submitLabel: string;
  pendingLabel?: string;
  variant?: "default" | "outline" | "destructive";
  children?: React.ReactNode;
  className?: string;
}) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(action, {});
  return (
    <form action={formAction} className={className ?? "flex flex-col gap-4"}>
      {children}
      <FormNotice state={state} />
      <Button type="submit" variant={variant} disabled={pending} className="w-full sm:w-auto">
        {pending ? pendingLabel : submitLabel}
      </Button>
    </form>
  );
}
