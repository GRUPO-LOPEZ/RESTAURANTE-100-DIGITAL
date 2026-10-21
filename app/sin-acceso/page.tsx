import type { Metadata } from "next";
import { ShieldOff } from "lucide-react";

import { signOut } from "@/app/ingresar/actions";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Sin acceso · Grupo LF" };

export default function SinAccesoPage() {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <p className="text-base font-semibold text-ink">Grupo LF</p>
      <Card className="flex flex-col gap-4">
        <div className="flex items-center gap-2">
          <ShieldOff aria-hidden="true" className="size-6 text-bad-ink" />
          <h1 className="text-2xl text-ink">Sin acceso</h1>
        </div>
        <CardTitle className="sr-only">Por qué no podés entrar</CardTitle>
        <CardDescription className="text-base">
          Tu cuenta no tiene permisos en este momento: puede estar desactivada o todavía no tener un
          rol asignado. Si creés que es un error, hablá con quien administra tu local.
        </CardDescription>
        <form action={signOut}>
          <Button type="submit" variant="outline" size="wide">
            Salir
          </Button>
        </form>
      </Card>
    </main>
  );
}
