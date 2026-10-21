"use client";

import Link from "next/link";
import { RotateCcw } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";

// Pantalla de error (design.md: estados de error diseñados, nunca una pantalla en blanco).
// No muestra el detalle técnico: queda en los registros del servidor.
export default function ErrorPage({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <p className="text-base font-semibold text-ink">Grupo LF</p>
      <h1 className="text-2xl text-ink">Algo no salió bien</h1>
      <Notice status="bad">No pudimos cargar los datos. Probá de nuevo en un rato.</Notice>
      <div className="flex flex-col gap-2 sm:flex-row">
        <Button type="button" onClick={reset}>
          <RotateCcw aria-hidden="true" />
          Reintentar
        </Button>
        <Button asChild variant="outline">
          <Link href="/">Volver al inicio</Link>
        </Button>
      </div>
    </main>
  );
}
