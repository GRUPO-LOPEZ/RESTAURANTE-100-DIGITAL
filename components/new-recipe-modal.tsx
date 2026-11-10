import { CreateModal } from "@/components/create-modal";

// "Nueva receta" en la lista (ADR-0036): el modal común de altas, con el formulario de /recetas/nueva.
export function NewRecipeModal({ children }: { children: React.ReactNode }) {
  return (
    <CreateModal
      href="/recetas/nueva"
      label="Nueva receta"
      title="Nueva receta"
      description="Primero sus datos; después cargás los componentes, los pasos y el rendimiento en el borrador."
    >
      {children}
    </CreateModal>
  );
}
