import Link from "next/link";
import { Suspense } from "react";

import { inviteAction } from "@/app/usuarios/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Card, CardDescription } from "@/components/ui/card";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { getPlaces, getRoles } from "@/lib/data";
import { requireOperable } from "@/lib/auth/session";

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
  await requireOperable();
  const [roles, places] = await Promise.all([getRoles(), getPlaces()]);
  return (
    <>
      <Link href="/usuarios" className="text-base text-primary underline-offset-4 hover:underline">
        Volver a usuarios
      </Link>
      <Card className="flex flex-col gap-4">
        <CardDescription>
          Solo podés invitar a los lugares y con los roles que tus permisos permiten.
        </CardDescription>
        <ActionForm action={inviteAction} submitLabel="Enviar invitación" pendingLabel="Enviando…">
          <Field id="email" label="Correo">
            <Input
              name="email"
              type="email"
              inputMode="email"
              autoComplete="off"
              required
              maxLength={320}
            />
          </Field>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field id="first_name" label="Nombre">
              <Input name="first_name" required maxLength={80} />
            </Field>
            <Field id="last_name" label="Apellido">
              <Input name="last_name" required maxLength={80} />
            </Field>
          </div>
          <Field id="role_code" label="Rol">
            <Select name="role_code" required defaultValue="">
              <option value="" disabled>
                Elegí un rol
              </option>
              {roles.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="place" label="Dónde">
            <Select name="place" required defaultValue="">
              <option value="" disabled>
                Elegí el lugar
              </option>
              {places.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="reason" label="Motivo" hint="Queda en el historial.">
            <Textarea name="reason" required maxLength={500} />
          </Field>
        </ActionForm>
      </Card>
    </>
  );
}
