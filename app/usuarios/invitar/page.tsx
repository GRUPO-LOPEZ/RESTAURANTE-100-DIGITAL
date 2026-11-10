import { Suspense } from "react";

import { inviteAction } from "@/app/usuarios/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Card, CardDescription } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { getPlaces, getRoles } from "@/lib/data";
import { requireMenu } from "@/lib/auth/session";
import { BackLink } from "@/components/back-link";

export default function InvitarPage() {
  return (
    <AppShell
      title="Invitar a una persona"
      description="El alta es solo por invitación. La persona recibe un correo para elegir su contraseña."
    >
      <Suspense fallback={<Loading />}>
        <InviteForm />
      </Suspense>
    </AppShell>
  );
}

async function InviteForm() {
  await requireMenu("invite");
  const [roles, places] = await Promise.all([getRoles(), getPlaces()]);
  return (
    <>
      <BackLink href="/usuarios">Volver a usuarios</BackLink>
      <Card className="flex max-w-3xl flex-col gap-4">
        <CardDescription>
          Solo podés invitar a los lugares y con los roles que tus permisos permiten.
        </CardDescription>
        <ActionForm
          action={inviteAction}
          schema="invite"
          submitLabel="Enviar invitación"
          pendingLabel="Enviando…"
        >
          <FormInput
            id="email"
            label="Correo"
            name="email"
            type="email"
            inputMode="email"
            autoComplete="off"
            required
            maxLength={320}
          />
          <div className="grid gap-4 sm:grid-cols-2">
            <FormInput id="first_name" label="Nombre" name="first_name" required maxLength={80} />
            <FormInput id="last_name" label="Apellido" name="last_name" required maxLength={80} />
          </div>
          <FormSelect id="role_code" label="Rol" name="role_code" required defaultValue="">
            <option value="" disabled>
              Elegí un rol
            </option>
            {roles.map((r) => (
              <option key={r.code} value={r.code}>
                {r.name}
              </option>
            ))}
          </FormSelect>
          <FormSelect id="place" label="Dónde" name="place" required defaultValue="">
            <option value="" disabled>
              Elegí el lugar
            </option>
            {places.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </FormSelect>
          <FormTextarea
            id="reason"
            label="Motivo"
            hint="Queda en el historial."
            name="reason"
            required
            maxLength={500}
          />
        </ActionForm>
      </Card>
    </>
  );
}
