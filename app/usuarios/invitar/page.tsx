import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { InviteForm } from "@/components/invite-form";
import { Card, CardDescription } from "@/components/ui/card";
import { requireMenu } from "@/lib/auth/session";
import { getPlaces, getRoles } from "@/lib/data";

// Invitar sin JavaScript (con JavaScript, el tablero y la lista lo abren en un modal corto; ADR-0062).
export default function InvitarPage() {
  return (
    <AppShell
      title="Invitar a una persona"
      description="El alta es solo por invitación. La persona recibe un correo para elegir su contraseña."
    >
      <Suspense fallback={<Loading />}>
        <Invite />
      </Suspense>
    </AppShell>
  );
}

async function Invite() {
  await requireMenu("invite");
  const [roles, places] = await Promise.all([getRoles(), getPlaces()]);
  return (
    <>
      <BackLink href="/usuarios">Volver a usuarios</BackLink>
      <Card className="flex max-w-3xl flex-col gap-4">
        <CardDescription>
          Solo podés invitar a los lugares y con los roles que tus permisos permiten.
        </CardDescription>
        <InviteForm roles={roles.map((r) => ({ code: r.code, name: r.name }))} places={places} />
      </Card>
    </>
  );
}
