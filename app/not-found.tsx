import type { Metadata } from "next";
import Link from "next/link";

import { Button } from "@/components/ui/button";

export const metadata: Metadata = { title: "No encontrada · Grupo LF" };

// Página no encontrada, en español y con una salida (en lugar del 404 genérico en inglés).
export default function NotFound() {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center gap-6 px-4 py-10">
      <p className="text-base font-semibold text-ink">Grupo LF</p>
      <h1 className="text-2xl text-ink">No encontramos esta página</h1>
      <p className="text-base text-ink-muted">
        Puede que el enlace esté mal escrito o que no tengas permiso para ver lo que buscás.
      </p>
      <Button asChild className="self-start">
        <Link href="/">Volver al inicio</Link>
      </Button>
    </main>
  );
}
