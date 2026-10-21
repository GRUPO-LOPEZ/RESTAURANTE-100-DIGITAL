import * as React from "react";
import Link from "next/link";
import { Suspense } from "react";
import { LogOut } from "lucide-react";

import { signOut } from "@/app/ingresar/actions";
import { Button } from "@/components/ui/button";
import { displayName, getMenus, requireOperable } from "@/lib/auth/session";

// Marco de las pantallas con sesión: encabezado fijo (parte estática) y menú según permisos,
// que lee la sesión y por eso va detrás de un Suspense (Cache Components).
export function AppShell({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-full flex-col">
      <header className="border-b border-line bg-surface">
        <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-2 px-4 py-2">
          <Link href="/" className="flex min-h-touch items-center text-base font-semibold text-ink">
            Grupo LF
          </Link>
          <Suspense fallback={<span className="text-sm text-ink-muted">Cargando…</span>}>
            <SessionMenu />
          </Suspense>
        </div>
      </header>
      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-6 px-4 py-6">
        <div className="flex flex-col gap-1">
          <h1 className="text-2xl text-ink">{title}</h1>
          {description ? <p className="text-base text-ink-muted">{description}</p> : null}
        </div>
        {children}
      </main>
    </div>
  );
}

async function SessionMenu() {
  const session = await requireOperable();
  const menus = await getMenus();
  const links = [
    { href: "/", label: "Inicio", show: true },
    { href: "/usuarios", label: "Usuarios", show: menus.users },
    { href: "/aprobaciones", label: "Aprobaciones", show: menus.approvals },
    { href: "/historial", label: "Historial", show: menus.audit },
  ].filter((l) => l.show);

  return (
    <nav aria-label="Menú principal" className="flex flex-wrap items-center gap-1">
      {links.map((l) => (
        <Link
          key={l.href}
          href={l.href}
          className="flex min-h-touch items-center rounded-sm px-3 text-base text-ink hover:bg-line/50"
        >
          {l.label}
        </Link>
      ))}
      <form action={signOut}>
        <Button type="submit" variant="ghost" aria-label={`Salir (${displayName(session)})`}>
          <LogOut aria-hidden="true" />
          Salir
        </Button>
      </form>
    </nav>
  );
}

export function Loading({ label = "Cargando…" }: { label?: string }) {
  return (
    <p role="status" className="text-base text-ink-muted">
      {label}
    </p>
  );
}
