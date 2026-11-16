"use client";

import * as React from "react";
import { Copy } from "lucide-react";

import { Button } from "@/components/ui/button";

// Copiar un texto (por ejemplo, el mensaje de una OC para mandarlo a mano). Avisa si se copió o si el navegador no dejó.
export function CopyButton({ text, label = "Copiar" }: { text: string; label?: string }) {
  const [state, setState] = React.useState<"idle" | "ok" | "bad">("idle");
  return (
    <span className="inline-flex items-center gap-2">
      <Button
        type="button"
        variant="outline"
        onClick={() => {
          navigator.clipboard
            .writeText(text)
            .then(() => setState("ok"))
            .catch(() => setState("bad"));
        }}
      >
        <Copy aria-hidden="true" className="size-4" />
        {label}
      </Button>
      <span role="status" className="text-sm text-ink-muted">
        {state === "ok"
          ? "Copiado."
          : state === "bad"
            ? "No se pudo copiar: seleccionalo a mano."
            : ""}
      </span>
    </span>
  );
}
