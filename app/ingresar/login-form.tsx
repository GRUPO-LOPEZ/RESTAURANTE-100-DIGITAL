"use client";

import Link from "next/link";

import { signIn } from "@/app/ingresar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { FormInput, ServerForm, useServerForm } from "@/components/ui/form";

export function LoginForm() {
  const form = useServerForm({ schema: "login", action: signIn });
  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      <FormInput
        id="email"
        label="Correo"
        name="email"
        type="email"
        autoComplete="username"
        inputMode="email"
        required
      />
      <FormInput
        id="password"
        label="Contraseña"
        name="password"
        type="password"
        maxLength={200}
        autoComplete="current-password"
        required
      />
      {/* Sin marcar: en las tablets compartidas de la cocina, la sesión no queda guardada (ADR-0015). */}
      <Checkbox id="remember" name="remember" label="Recordar mi sesión en este dispositivo" />
      <FormNotice state={form.state} />
      <Button type="submit" size="wide" disabled={form.pending}>
        {form.pending ? "Ingresando…" : "Ingresar"}
      </Button>
      <Link
        href="/ingresar/recuperar"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        ¿Olvidaste tu contraseña?
      </Link>
    </ServerForm>
  );
}
