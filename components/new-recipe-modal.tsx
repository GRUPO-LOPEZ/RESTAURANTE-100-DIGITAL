"use client";

import { useState } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";

import { buttonVariants } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";

// "Nueva receta" en la lista (ADR-0036: las altas simples en un modal corto que crea el borrador).
// Es un enlace a /recetas/nueva: sin JavaScript lleva a la página; con JavaScript abre el modal con el mismo
// formulario (NewRecipeForm), que al crear la receta lleva a su ficha.
export function NewRecipeModal({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Link
        href="/recetas/nueva"
        className={buttonVariants({ variant: "default" })}
        onClick={(event) => {
          // Ctrl/Cmd+clic o el botón del medio abren la página en otra pestaña.
          if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
          event.preventDefault();
          setOpen(true);
        }}
      >
        <Plus aria-hidden="true" />
        Nueva receta
      </Link>
      <Modal
        open={open}
        onOpenChange={setOpen}
        title="Nueva receta"
        description="Primero sus datos; después cargás los componentes, los pasos y el rendimiento en el borrador."
      >
        {children}
      </Modal>
    </>
  );
}
