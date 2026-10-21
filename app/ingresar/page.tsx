import type { Metadata } from "next";

import { LoginForm } from "@/app/ingresar/login-form";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Ingresar · Grupo LF" };

export default function IngresarPage() {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <div className="flex flex-col gap-1">
        <p className="text-base font-semibold text-ink">Grupo LF</p>
        <h1 className="text-2xl text-ink">Ingresar</h1>
      </div>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <CardTitle>Tu cuenta</CardTitle>
          <CardDescription>Entrá con el correo y la contraseña de tu invitación.</CardDescription>
        </div>
        <LoginForm />
      </Card>
      <p className="text-sm text-ink-muted">
        ¿No tenés cuenta? El alta es solo por invitación: pedísela a quien administra tu local.
      </p>
    </main>
  );
}
