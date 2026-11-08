"use client";

import { Printer } from "lucide-react";
import { useState, useTransition } from "react";

import { logReportPrint } from "@/app/reportes/actions";
import { Button } from "@/components/ui/button";

// Imprime o guarda como PDF desde el navegador. Antes deja el registro: si no se puede, no imprime.
export function ReportPrintButton({
  report,
  local,
  rows,
  fileName,
  recipe,
}: {
  report: string;
  local: string;
  rows: number;
  fileName: string;
  recipe?: string;
}) {
  const [failed, setFailed] = useState(false);
  const [pending, start] = useTransition();
  return (
    <span className="flex flex-col gap-2 print:hidden">
      <Button
        type="button"
        variant="outline"
        aria-busy={pending}
        onClick={() => {
          if (pending) return;
          start(async () => {
            const logged = await logReportPrint(report, local, rows, recipe).catch(() => false);
            setFailed(!logged);
            if (!logged) return;
            // El navegador propone el título de la página como nombre del PDF.
            const title = document.title;
            document.title = fileName;
            window.print();
            document.title = title;
          });
        }}
      >
        <Printer aria-hidden="true" />
        {pending ? "Preparando…" : "Imprimir o guardar como PDF"}
      </Button>
      {failed ? (
        <span role="alert" className="text-sm text-bad-ink">
          No pudimos preparar la impresión. Probá de nuevo.
        </span>
      ) : null}
    </span>
  );
}
