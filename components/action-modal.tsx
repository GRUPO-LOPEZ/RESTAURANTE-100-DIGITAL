"use client";

import { useId, useRef, useState } from "react";
import { Plus } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";
import { Segmented } from "@/components/ui/segmented";

// Un alta o una propuesta con su propio flujo (su motivo, su aprobación), en un panel corto al lado (ADR-0036). La
// ficha única la usa para lo que no entra en el guardado en lote: agregar un producto, proponer una merma (ADR-0043).
// El formulario de adentro avisa el resultado; al cerrar, el foco vuelve al botón que lo abrió (WCAG 2.4.3).
export function ActionModal({
  label,
  title,
  description,
  variant = "outline",
  children,
}: {
  label: string;
  title: string;
  description?: string;
  variant?: "default" | "outline";
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const opener = useRef<HTMLButtonElement>(null);
  return (
    <>
      <Button
        ref={opener}
        type="button"
        variant={variant}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => setOpen(true)}
        className="self-start"
      >
        <Plus aria-hidden="true" />
        {label}
      </Button>
      <Modal
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) requestAnimationFrame(() => opener.current?.focus());
        }}
        title={title}
        description={description}
      >
        {children}
      </Modal>
    </>
  );
}

// «Proponer merma o rendimiento»: un solo botón, y adentro se elige qué se propone (dos opciones a la vista). Cada
// formulario es el de siempre, con su aprobación.
export function ProposalModal({
  label,
  options,
}: {
  label: string;
  options: { value: string; label: string; content: React.ReactNode }[];
}) {
  const [kind, setKind] = useState(options[0]?.value ?? "");
  const name = useId();
  return (
    <ActionModal
      label={label}
      title="Proponer merma o rendimiento"
      description="No cambia el costo hasta que lo apruebe un Chef de todo el grupo, distinto de vos."
    >
      <Segmented
        name={`${name}-propuesta-tipo`}
        legend="Qué proponés"
        options={options.map((o) => ({ value: o.value, label: o.label }))}
        value={kind}
        onChange={setKind}
      />
      {options.map((o) => (
        <div key={o.value} hidden={o.value !== kind}>
          {o.content}
        </div>
      ))}
    </ActionModal>
  );
}
