import { CreateModal } from "@/components/create-modal";
import { InviteForm } from "@/components/invite-form";
import { getPlaces, getRoles } from "@/lib/data";

// El botón «Invitar a una persona» con su modal corto (ADR-0062). Lo usan el tablero y la lista de usuarios.
export async function InviteModal() {
  const [roles, places] = await Promise.all([getRoles(), getPlaces()]);
  return (
    <CreateModal
      href="/usuarios/invitar"
      label="Invitar a una persona"
      title="Invitar a una persona"
      description="Recibe un correo para elegir su contraseña; el resto se completa en su ficha. Solo podés invitar a los lugares y con los roles que tus permisos permiten."
    >
      <InviteForm roles={roles.map((r) => ({ code: r.code, name: r.name }))} places={places} />
    </CreateModal>
  );
}
