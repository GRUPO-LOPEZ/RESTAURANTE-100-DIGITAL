"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, ServerForm, useServerForm } from "@/components/ui/form";
import type { ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { createClient } from "@/lib/supabase/client";

// Aceptar una invitación: el enlace del correo trae la sesión en el fragmento de la URL.
export default function InvitacionPage() {
  const router = useRouter();
  const [ready, setReady] = useState<"loading" | "ok" | "invalid">("loading");

  useEffect(() => {
    const params = new URLSearchParams(window.location.hash.slice(1));
    const access_token = params.get("access_token");
    const refresh_token = params.get("refresh_token");
    window.history.replaceState(null, "", window.location.pathname);
    // El estado se actualiza cuando termina de validar la sesión (en la respuesta, no durante el efecto).
    const check =
      access_token && refresh_token
        ? createClient()
            .auth.setSession({ access_token, refresh_token })
            .then(({ error }) => !error)
        : Promise.resolve(false);
    void check.then((ok) => setReady(ok ? "ok" : "invalid"));
  }, []);

  // La contraseña se guarda desde el navegador, con la sesión de la invitación. Mismo esquema que
  // la contraseña nueva de recuperación (lib/forms/schemas.ts).
  const form = useServerForm<ActionState>({
    schema: "newPassword",
    action: async (_prev, formData) => {
      const parsed = schemas.newPassword.safeParse(formValues(formData));
      if (!parsed.success) return { status: "bad", fieldErrors: fieldErrors(parsed.error) };
      const { error } = await createClient().auth.updateUser({ password: parsed.data.password });
      if (error)
        return { status: "bad", message: "No pudimos guardar la contraseña. Probá con otra." };
      router.replace("/");
      return {};
    },
  });

  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <div className="flex flex-col gap-1">
        <p className="text-base font-semibold text-ink">Grupo LF</p>
        <h1 className="text-2xl text-ink">Aceptar la invitación</h1>
      </div>
      <Card className="flex flex-col gap-4">
        {ready === "loading" ? (
          <p role="status" className="text-base text-ink-muted">
            Revisando la invitación…
          </p>
        ) : null}
        {ready === "invalid" ? (
          <FormNotice
            state={{
              status: "bad",
              message: "El enlace no es válido o ya venció. Pedí una invitación nueva.",
            }}
          />
        ) : null}
        {ready === "ok" ? (
          <>
            <div className="flex flex-col gap-1">
              <CardTitle>Elegí tu contraseña</CardTitle>
              <CardDescription>Mínimo 12 caracteres, con letras y números.</CardDescription>
            </div>
            <ServerForm form={form} className="flex flex-col gap-4">
              <FormInput
                id="password"
                label="Contraseña nueva"
                name="password"
                type="password"
                autoComplete="new-password"
                required
                maxLength={200}
              />
              <FormInput
                id="repeat"
                label="Repetí la contraseña"
                name="repeat"
                type="password"
                autoComplete="new-password"
                required
                maxLength={200}
              />
              <FormNotice state={form.state} />
              <Button type="submit" size="wide" disabled={form.pending}>
                {form.pending ? "Guardando…" : "Guardar y entrar"}
              </Button>
            </ServerForm>
          </>
        ) : null}
      </Card>
    </main>
  );
}
