import * as React from "react";
import Link from "next/link";
import { Suspense } from "react";
import { LogOut } from "lucide-react";

import { signOut } from "@/app/ingresar/actions";
import { MainNav, type NavLink } from "@/components/main-nav";
import { RestaurantSelector } from "@/components/restaurant-selector";
import { Button } from "@/components/ui/button";
import { displayName, getMenus, requireOperable } from "@/lib/auth/session";
import { getActiveRestaurantId, getMyScopes, getUnreadCount } from "@/lib/data";

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
      <header className="relative border-b border-line bg-surface print:hidden">
        <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center gap-2 px-4 py-2">
          <Link
            href="/"
            className="mr-auto flex min-h-touch items-center text-base font-semibold text-ink"
          >
            Grupo LF
          </Link>
          <Suspense fallback={<span className="text-sm text-ink-muted">Cargando…</span>}>
            <SessionMenu />
          </Suspense>
        </div>
      </header>
      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-6 px-4 py-6">
        <div className="flex flex-col gap-1 print:hidden">
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
  const [menus, scopes, activeId, unread] = await Promise.all([
    getMenus(),
    getMyScopes(),
    getActiveRestaurantId(session.user_id),
    getUnreadCount(),
  ]);
  const all: (NavLink & { show: boolean })[] = [
    { href: "/", label: "Inicio", show: true },
    { href: "/recetas", label: "Recetas", show: menus.recipes },
    { href: "/materias-primas", label: "Materias primas", show: menus.catalog },
    { href: "/costos", label: "Costos", show: menus.costs },
    { href: "/usuarios", label: "Usuarios", show: menus.users },
    { href: "/aprobaciones", label: "Aprobaciones", count: unread, show: menus.approvals },
    { href: "/historial", label: "Historial", show: menus.audit },
    { href: "/roles", label: "Roles y permisos", show: menus.roles },
    { href: "/configuracion", label: "Panel de control", show: menus.panel },
    { href: "/mi-cuenta", label: "Mi cuenta", show: true },
  ];
  const links: NavLink[] = all
    .filter((l) => l.show)
    .map(({ href, label, count }) => ({ href, label, count }));

  // Celular: arriba la marca, "Menú" y "Salir"; abajo el selector de local a todo el ancho.
  // Computadora: arriba la marca, el selector y "Salir"; abajo el menú completo.
  return (
    <>
      {scopes.length > 1 ? (
        <RestaurantSelector
          value={scopes.some((s) => s.restaurant_id === activeId) ? activeId : null}
          options={scopes.map((s) => ({
            id: s.restaurant_id,
            label: `${s.restaurant_name} · ${s.brand_code}`,
          }))}
        />
      ) : null}
      <MainNav links={links} />
      <form action={signOut}>
        <Button type="submit" variant="ghost" aria-label={`Salir (${displayName(session)})`}>
          <LogOut aria-hidden="true" />
          Salir
        </Button>
      </form>
    </>
  );
}

export function Loading({ label = "Cargando…" }: { label?: string }) {
  return (
    <p role="status" className="text-base text-ink-muted">
      {label}
    </p>
  );
}
