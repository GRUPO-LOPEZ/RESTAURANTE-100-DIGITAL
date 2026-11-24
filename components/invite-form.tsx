import { inviteAction } from "@/app/usuarios/actions";
import { ActionForm } from "@/components/action-form";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";

// Invitar a una persona (Tanda 1 de Soy, decisión 6; ADR-0062): correo, nombre, rol y dónde trabaja. El resto (puesto,
// área, otros roles) se completa en su ficha. Lo usan el modal de Usuarios y la página /usuarios/invitar, que queda para
// cuando no hay JavaScript.
export function InviteForm({
  roles,
  places,
}: {
  roles: { code: string; name: string }[];
  places: { value: string; label: string }[];
}) {
  return (
    <ActionForm
      action={inviteAction}
      schema="invite"
      submitLabel="Enviar invitación"
      pendingLabel="Enviando…"
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput id="first_name" label="Nombre" name="first_name" required maxLength={80} />
        <FormInput id="last_name" label="Apellido" name="last_name" required maxLength={80} />
      </div>
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
        <FormSelect id="place" label="Dónde trabaja" name="place" required defaultValue="">
          <option value="" disabled>
            Elegí el lugar
          </option>
          {places.map((p) => (
            <option key={p.value} value={p.value}>
              {p.label}
            </option>
          ))}
        </FormSelect>
      </div>
      <FormTextarea
        id="reason"
        label="Motivo"
        hint="Queda en el historial."
        name="reason"
        required
        maxLength={500}
      />
    </ActionForm>
  );
}
