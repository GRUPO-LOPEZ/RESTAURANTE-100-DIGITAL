"use client";

import { requestRecovery } from "@/app/ingresar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { FormInput, ServerForm, useServerForm } from "@/components/ui/form";

export function RecoverForm() {
  const form = useServerForm({ schema: "recover", action: requestRecovery });
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
      <FormNotice state={form.state} />
      <Button type="submit" size="wide" disabled={form.pending}>
        {form.pending ? "Enviando…" : "Enviar el enlace"}
      </Button>
    </ServerForm>
  );
}
