import type { Metadata } from "next";
import { Suspense } from "react";
import { redirect } from "next/navigation";

import { EnrollForm, VerifyForm } from "@/app/ingresar/doble-verificacion/forms";
import { Loading } from "@/components/app-shell";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { getMySession } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Doble verificación · Grupo LF" };

export default function DobleVerificacionPage() {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <div className="flex flex-col gap-1">
        <p className="text-base font-semibold text-ink">Grupo LF</p>
        <h1 className="text-2xl text-ink">Doble verificación</h1>
      </div>
      <Suspense fallback={<Loading />}>
        <Step />
      </Suspense>
    </main>
  );
}

async function Step() {
  const session = await getMySession();
  if (!session.signed_in) redirect("/ingresar");
  if (session.aal === "aal2") redirect("/");

  const supabase = await createClient();
  const { data } = await supabase.auth.mfa.listFactors();
  const hasFactor = data?.totp.some((f) => f.status === "verified") ?? false;

  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>
          {hasFactor ? "Ingresá el código" : "Registrá tu app de autenticación"}
        </CardTitle>
        <CardDescription>
          {hasFactor
            ? "Abrí tu app de autenticación y escribí el código de 6 números."
            : "Tu rol exige doble verificación. Escaneá el código con una app de autenticación (por ejemplo, Google Authenticator) y escribí el código que te muestra."}
        </CardDescription>
      </div>
      {hasFactor ? <VerifyForm /> : <EnrollForm />}
    </Card>
  );
}
