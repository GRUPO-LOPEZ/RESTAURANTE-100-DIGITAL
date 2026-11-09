"use client";

import * as React from "react";
import { AlertDialog, Dialog } from "radix-ui";
import { X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

// Ventanas (ADR-0036): modal para altas simples, panel lateral para ver un detalle sin perder la lista,
// y confirmación para acciones que no se deshacen. Radix maneja el foco, Escape y el lector de pantalla.

const overlay = "fixed inset-0 z-40 bg-ink/40";

function Modal({
  open,
  onOpenChange,
  trigger,
  title,
  description,
  children,
}: {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  trigger?: React.ReactNode;
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      {trigger ? <Dialog.Trigger asChild>{trigger}</Dialog.Trigger> : null}
      <Dialog.Portal>
        <Dialog.Overlay className={overlay} />
        <Dialog.Content
          className="fixed top-1/2 left-1/2 z-50 flex max-h-[90vh] w-[calc(100%-2rem)] max-w-lg -translate-x-1/2 -translate-y-1/2 flex-col gap-4 overflow-y-auto rounded-md border border-line bg-surface p-6"
          {...(description ? {} : { "aria-describedby": undefined })}
        >
          <div className="flex items-start justify-between gap-4">
            <Dialog.Title className="text-xl font-semibold text-ink">{title}</Dialog.Title>
            <Dialog.Close asChild>
              <Button variant="ghost" size="icon" aria-label="Cerrar">
                <X aria-hidden="true" />
              </Button>
            </Dialog.Close>
          </div>
          {description ? (
            <Dialog.Description className="text-sm text-ink-muted">
              {description}
            </Dialog.Description>
          ) : null}
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function SidePanel({
  open,
  onOpenChange,
  title,
  description,
  children,
  className,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className={overlay} />
        <Dialog.Content
          className={cn(
            "fixed inset-y-0 right-0 z-50 flex w-full flex-col gap-4 overflow-y-auto border-l border-line bg-surface p-6 desk:w-[32rem]",
            className,
          )}
          {...(description ? {} : { "aria-describedby": undefined })}
        >
          <div className="flex items-start justify-between gap-4">
            <Dialog.Title className="text-xl font-semibold text-ink">{title}</Dialog.Title>
            <Dialog.Close asChild>
              <Button variant="ghost" size="icon" aria-label="Cerrar">
                <X aria-hidden="true" />
              </Button>
            </Dialog.Close>
          </div>
          {description ? (
            <Dialog.Description className="text-sm text-ink-muted">
              {description}
            </Dialog.Description>
          ) : null}
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

// Confirmación: el botón de confirmar dice qué hace ("Desactivar la cuenta"), nunca solo "Aceptar".
function Confirm({
  trigger,
  title,
  description,
  confirmLabel,
  onConfirm,
  destructive = false,
}: {
  trigger: React.ReactNode;
  title: string;
  description: string;
  confirmLabel: string;
  onConfirm: () => void;
  destructive?: boolean;
}) {
  return (
    <AlertDialog.Root>
      <AlertDialog.Trigger asChild>{trigger}</AlertDialog.Trigger>
      <AlertDialog.Portal>
        <AlertDialog.Overlay className={overlay} />
        <AlertDialog.Content className="fixed top-1/2 left-1/2 z-50 flex w-[calc(100%-2rem)] max-w-md -translate-x-1/2 -translate-y-1/2 flex-col gap-4 rounded-md border border-line bg-surface p-6">
          <AlertDialog.Title className="text-xl font-semibold text-ink">{title}</AlertDialog.Title>
          <AlertDialog.Description className="text-base text-ink-muted">
            {description}
          </AlertDialog.Description>
          <div className="flex flex-wrap justify-end gap-2">
            <AlertDialog.Cancel asChild>
              <Button variant="outline">Cancelar</Button>
            </AlertDialog.Cancel>
            <AlertDialog.Action asChild>
              <Button variant={destructive ? "destructive" : "default"} onClick={onConfirm}>
                {confirmLabel}
              </Button>
            </AlertDialog.Action>
          </div>
        </AlertDialog.Content>
      </AlertDialog.Portal>
    </AlertDialog.Root>
  );
}

export { Confirm, Modal, SidePanel };
