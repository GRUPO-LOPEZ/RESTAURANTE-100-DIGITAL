"use client";

import { Printer } from "lucide-react";

import { Button } from "@/components/ui/button";

// Imprime la pantalla, sin el menú ni los formularios.
export function PrintButton() {
  return (
    <Button type="button" variant="outline" className="print:hidden" onClick={() => window.print()}>
      <Printer aria-hidden="true" />
      Imprimir
    </Button>
  );
}
