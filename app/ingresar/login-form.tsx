"use client";

import { useActionState } from "react";
import Link from "next/link";

import { signIn, type FormState } from "@/app/ingresar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, Input } from "@/components/ui/field";

export function LoginForm() {
  const [state, formAction, pending] = useActionState<FormState, FormData>(signIn, {});
  return (
    <form action={formAction} className="flex flex-col gap-4" noValidate>
      <Field id="email" label="Correo">
        <Input name="email" type="email" autoComplete="username" inputMode="email" required />
      </Field>
      <Field id="password" label="Contraseña">
        <Input name="password" type="password" autoComplete="current-password" required />
      </Field>
      <Checkbox
        id="remember"
        name="remember"
        label="Recordar mi sesión en este dispositivo"
        defaultChecked
      />
      <FormNotice state={state} />
      <Button type="submit" size="wide" disabled={pending}>
        {pending ? "Ingresando…" : "Ingresar"}
      </Button>
      <Link
        href="/ingresar/recuperar"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        ¿Olvidaste tu contraseña?
      </Link>
    </form>
  );
}
