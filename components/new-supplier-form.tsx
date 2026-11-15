import { createSupplierAction } from "@/app/proveedores/actions";
import { ActionForm } from "@/components/action-form";
import { FormInput, FormTextarea } from "@/components/ui/form";

// Alta corta de proveedor (ADR-0050): lo usan el modal de la lista y la página /proveedores/nuevo (sin JavaScript).
// Crea el borrador con código automático y lleva a la ficha para completar el resto.
export function NewSupplierForm() {
  return (
    <ActionForm
      action={createSupplierAction}
      schema="supplier"
      submitLabel="Crear y completar la ficha"
    >
      <FormInput
        id="prov-nuevo-nombre"
        label="Razón social"
        name="name"
        required
        maxLength={120}
        hint="Como figura en el CUIT. El nombre de fantasía va en la ficha."
      />
      <FormInput
        id="prov-nuevo-cuit"
        label="CUIT"
        name="tax_id"
        maxLength={15}
        inputMode="numeric"
        hint="Opcional (un puesto del mercado no tiene). Con o sin guiones."
      />
      <FormTextarea
        id="prov-nuevo-motivo"
        name="reason"
        label="Motivo"
        hint="Queda en el historial."
        required
        maxLength={500}
      />
    </ActionForm>
  );
}
