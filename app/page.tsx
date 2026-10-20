import { CircleCheck } from "lucide-react";

import { Badge, type BadgeStatus } from "@/components/ui/badge";

// Página de verificación del entorno (Fase 0). No es una pantalla de negocio:
// muestra la paleta y la tipografía para que Playwright y axe las revisen.
const STATUSES: { status: BadgeStatus; label: string }[] = [
  { status: "ok", label: "Aprobado" },
  { status: "warn", label: "Pendiente" },
  { status: "bad", label: "Rechazado" },
  { status: "info", label: "Información" },
  { status: "review", label: "En revisión" },
  { status: "draft", label: "Borrador" },
];

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-8 px-4 py-12">
      <header className="flex flex-col gap-2">
        <p className="text-sm font-medium text-ink-muted">Grupo LF</p>
        <h1 className="text-2xl">Sistema Operativo Gastronómico</h1>
        <p className="text-ink-muted">
          El entorno de desarrollo está listo. Las pantallas llegan después de identidad, permisos y
          auditoría.
        </p>
      </header>

      <section
        aria-labelledby="estado-entorno"
        className="flex flex-col gap-4 rounded-lg border border-line bg-surface p-6"
      >
        <h2 id="estado-entorno" className="flex items-center gap-2 text-xl">
          <CircleCheck aria-hidden className="size-5 text-ok-ink" />
          Fase 0: entorno
        </h2>
        <ul className="flex flex-wrap gap-2" aria-label="Estados del sistema de diseño">
          {STATUSES.map(({ status, label }) => (
            <li key={status}>
              <Badge status={status}>{label}</Badge>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}
