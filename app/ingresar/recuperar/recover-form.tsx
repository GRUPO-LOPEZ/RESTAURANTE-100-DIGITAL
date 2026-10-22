"use client";

import { useActionState } from "react";

import { requestRecovery, type FormState } from "@/app/ingresar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/field";

export function RecoverForm() {
  const [state, formAction, pending] = useActionState<FormState, FormData>(requestRecovery, {});
  return (
    <form action={formAction} className="flex flex-col gap-4" noValidate>
      <Field id="email" label="Correo">
        <Input name="email" type="email" autoComplete="username" inputMode="email" required />
      </Field>
      <FormNotice state={state} />
      <Button type="submit" size="wide" disabled={pending}>
        {pending ? "Enviando…" : "Enviar el enlace"}
      </Button>
    </form>
  );
}
