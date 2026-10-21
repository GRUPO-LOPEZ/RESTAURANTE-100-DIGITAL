"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { z } from "zod";

import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Input } from "@/components/ui/field";
import { createClient } from "@/lib/supabase/client";

// Contraseña: mínimo 12 caracteres, con letras y números (P8; mismo criterio que Auth).
const passwordSchema = z
  .string()
  .min(12, "La contraseña tiene que tener al menos 12 caracteres.")
  .regex(/[A-Za-z]/, "La contraseña tiene que tener letras.")
  .regex(/[0-9]/, "La contraseña tiene que tener números.");

type State = { status?: "ok" | "info" | "warn" | "bad"; message?: string };

// Aceptar una invitación: el enlace del correo trae la sesión en el fragmento de la URL.
export default function InvitacionPage() {
  const router = useRouter();
  const [ready, setReady] = useState<"loading" | "ok" | "invalid">("loading");
  const [state, setState] = useState<State>({});
  const [pending, setPending] = useState(false);

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

  async function onSubmit(formData: FormData) {
    const password = String(formData.get("password") ?? "");
    const repeat = String(formData.get("repeat") ?? "");
    const parsed = passwordSchema.safeParse(password);
    if (!parsed.success)
      return setState({ status: "bad", message: parsed.error.issues[0]?.message });
    if (password !== repeat)
      return setState({ status: "bad", message: "Las dos contraseñas no coinciden." });
    setPending(true);
    const { error } = await createClient().auth.updateUser({ password });
    setPending(false);
    if (error)
      return setState({
        status: "bad",
        message: "No pudimos guardar la contraseña. Probá con otra.",
      });
    router.replace("/");
  }

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
            <form action={onSubmit} className="flex flex-col gap-4">
              <Field id="password" label="Contraseña nueva">
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
          </>
        ) : null}
      </Card>
    </main>
  );
}
