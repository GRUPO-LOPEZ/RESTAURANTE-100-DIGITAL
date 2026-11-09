import * as React from "react";
import { CircleAlert, LoaderCircle } from "lucide-react";

import { cn } from "@/lib/utils";

// Estados de una pantalla o un bloque (ADR-0036): vacío, carga y error, diseñados. Nunca una pantalla en blanco.

function EmptyState({ title, children }: { title: string; children?: React.ReactNode }) {
  return (
    <div
      data-slot="empty-state"
      className="rounded-md border border-dashed border-line bg-surface p-6 text-center"
    >
      <p className="text-base font-medium text-ink">{title}</p>
      {children ? <div className="mt-2 text-sm text-ink-muted">{children}</div> : null}
    </div>
  );
}

function LoadingState({ label = "Cargando…", className }: { label?: string; className?: string }) {
  return (
    <p role="status" className={cn("flex items-center gap-2 text-base text-ink-muted", className)}>
      <LoaderCircle aria-hidden="true" className="size-5 animate-spin motion-reduce:animate-none" />
      {label}
    </p>
  );
}

function ErrorState({
  title = "No pudimos cargar esta información.",
  children,
  action,
  className,
}: {
  title?: string;
  children?: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      role="alert"
      data-slot="error-state"
      className={cn(
        "flex flex-col items-start gap-3 rounded-md bg-bad p-6 text-bad-ink",
        className,
      )}
    >
      <p className="flex items-center gap-2 text-base font-medium">
        <CircleAlert aria-hidden="true" className="size-5 shrink-0" />
        {title}
      </p>
      {children ? <div className="text-sm">{children}</div> : null}
      {action}
    </div>
  );
}

export { EmptyState, ErrorState, LoadingState };
