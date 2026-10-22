"use client";

import { setNewPassword } from "@/app/ingresar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { FormInput, ServerForm, useServerForm } from "@/components/ui/form";

export function NewPasswordForm() {
  const form = useServerForm({ schema: "newPassword", action: setNewPassword });
  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      <FormInput
        id="password"
        label="Contraseña nueva"
        hint="Mínimo 12 caracteres, con letras y números."
        name="password"
        type="password"
        maxLength={200}
        autoComplete="new-password"
        required
      />
      <FormInput
        id="repeat"
        label="Repetí la contraseña"
        name="repeat"
        type="password"
        maxLength={200}
        autoComplete="new-password"
        required
      />
      <FormNotice state={form.state} />
      <Button type="submit" size="wide" disabled={form.pending}>
        {form.pending ? "Guardando…" : "Guardar y entrar"}
      </Button>
    </ServerForm>
  );
}
