import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { RecoverForm } from "@/app/ingresar/recuperar/recover-form";
import { FormNotice } from "@/components/form-notice";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Recuperar la contraseña · Grupo LF" };

export default function RecuperarPage({ searchParams }: PageProps<"/ingresar/recuperar">) {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <div className="flex flex-col gap-1">
        <p className="text-base font-semibold text-ink">Grupo LF</p>
        <h1 className="text-2xl text-ink">Recuperar la contraseña</h1>
      </div>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <CardTitle>Te mandamos un enlace</CardTitle>
          <CardDescription>
            Escribí el correo de tu cuenta. Si la cuenta existe, vas a recibir un enlace para elegir
            una contraseña nueva.
          </CardDescription>
        </div>
        <Suspense fallback={null}>
          <ExpiredNotice searchParams={searchParams} />
        </Suspense>
        <RecoverForm />
      </Card>
      <Link
        href="/ingresar"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a ingresar
      </Link>
    </main>
  );
}

async function ExpiredNotice({
  searchParams,
}: {
  searchParams: PageProps<"/ingresar/recuperar">["searchParams"];
}) {
  const { enlace } = await searchParams;
  if (enlace !== "vencido") return null;
  return (
    <FormNotice
      state={{
        status: "warn",
        message:
          "El enlace no es válido, ya se usó o venció. Pedí uno nuevo. Si tu cuenta está suspendida o desactivada, hablá con quien administra tu local.",
      }}
    />
  );
}
