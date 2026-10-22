"use client";

import { useActionState } from "react";

import { setNewPassword, type FormState } from "@/app/ingresar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/field";

export function NewPasswordForm() {
  const [state, formAction, pending] = useActionState<FormState, FormData>(setNewPassword, {});
  return (
    <form action={formAction} className="flex flex-col gap-4" noValidate>
      <Field
        id="password"
        label="Contraseña nueva"
        hint="Mínimo 12 caracteres, con letras y números."
      >
        <Input name="password" type="password" autoComplete="new-password" required />
      </Field>
      <Field id="repeat" label="Repetí la contraseña">
        <Input name="repeat" type="password" autoComplete="new-password" required />
      </Field>
      <FormNotice state={state} />
      <Button type="submit" size="wide" disabled={pending}>
        {pending ? "Guardando…" : "Guardar y entrar"}
      </Button>
    </form>
  );
}
