import type { Metadata } from "next";

import { NewPasswordForm } from "@/app/ingresar/nueva-contrasena/new-password-form";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Contraseña nueva · Grupo LF" };

// Llega desde el enlace del correo (/ingresar/confirmar), con una sesión de recuperación.
export default function NuevaContrasenaPage() {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <div className="flex flex-col gap-1">
        <p className="text-base font-semibold text-ink">Grupo LF</p>
        <h1 className="text-2xl text-ink">Elegí una contraseña nueva</h1>
      </div>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <CardTitle>Contraseña nueva</CardTitle>
          <CardDescription>
            Si tu rol usa doble verificación, después te vamos a pedir el código.
          </CardDescription>
        </div>
        <NewPasswordForm />
      </Card>
    </main>
  );
}
