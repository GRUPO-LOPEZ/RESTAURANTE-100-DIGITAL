"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";

import { buttonVariants } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";

// Alta simple en un modal corto (ADR-0036). Es un enlace a la página del alta: sin JavaScript lleva a esa página;
// con JavaScript abre el modal con el mismo formulario, que al crear lleva a la ficha nueva. Ctrl/Cmd+clic o el
// botón del medio abren la página en otra pestaña.
export function CreateModal({
  href,
  label,
  title,
  description,
  children,
}: {
  href: string;
  label: string;
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const opener = useRef<HTMLAnchorElement>(null);
  return (
    <>
      <Link
        ref={opener}
        href={href}
        className={buttonVariants({ variant: "default" })}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={(event) => {
          if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
          event.preventDefault();
          setOpen(true);
        }}
      >
        <Plus aria-hidden="true" />
        {label}
      </Link>
      <Modal
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          // Al cerrar, el foco vuelve al botón que lo abrió (WCAG 2.4.3). El modal no tiene un disparador de
          // Radix: un disparador abriría el modal también con Ctrl+clic, que tiene que abrir otra pestaña.
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
